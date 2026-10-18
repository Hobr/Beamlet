# Storage/actions/agent 解耦：初步源码调研

基线：`a8acffd`；2026-10-18。本文件保留实施前历史调研：下列旧路径、接口与依赖仅描述基线，不是当前源码。设计已获批准、实现完成且独立检查 READY；当前归属/契约见 ../../../spec/backend/database-guidelines.md，最终证据见 independent-review.md，同步审计见 spec-sync.md。

## 历史基线事实

| 位置 | 事实 | 影响 |
| --- | --- | --- |
| `apps/beamlet_actions/mix.exs:26` | Actions 无 umbrella 业务依赖 | 纯 contracts 层已独立，不能因持久化引入 Ecto/Agent 依赖 |
| `apps/beamlet_runtime/mix.exs:26` | Runtime 依赖 Actions 与 Storage | Runtime 是独立运行 Actions 的现有入口 |
| `apps/beamlet_storage/lib/beamlet/storage/schema/operation.ex:7` | Operation 持久化含 owner_agent_id、turn_id、tool_call_id、role、owner_generation、prepared_seq | 通用 Operation 存储结构承载 Agent 编排语义 |
| `apps/beamlet_storage/priv/authority_migrations/2_authority_v2.exs:16` | operations.owner_agent_id 外键到 agents；统一 authority migration 安装两域表 | Actions-only 存储不能独立安装自己的数据模型 |
| `apps/beamlet_storage/lib/beamlet/storage/operation_records.ex:9` | prepare 的 independent? 禁止 owner/turn/step/role/ordinal/tool_call_id，并要求空 sources | 已有非 Agent 持久化路径，但它只是受限特例 |
| `apps/beamlet_storage/lib/beamlet/storage/operation_records.ex:215` | 派发校验直接锁定 Agent 并比较 generation | 移动文件无法消除业务耦合；必须设计等价并发约束 |
| `apps/beamlet_runtime/lib/beamlet/runtime/persistence.ex:28` | Runtime.Persistence.owner 的类型是 agent_id/turn_id/step_id | Runtime 持久化接线也理解 Agent，不只 Storage 有问题 |
| `apps/beamlet_storage/lib/beamlet/storage/agent_records.ex:91` | Agent 事务中准备 Operation/attempt，并追加 Agent preparation events | 必须保留单库原子提交，不应拆成独立提交 |
| `apps/beamlet_storage/lib/beamlet/storage/records.ex:10` | 共享 helpers 导入 Agent/Event 并提供 cas_agent | 底层通用 helpers 与领域 helper 混杂 |
| `apps/beamlet_storage/lib/beamlet/storage/events.ex:5` | Storage 定义 Agent 与 Operation 的事件词汇、Agent control 限制 | 底层仍拥有领域协议 |
| `apps/beamlet_storage/lib/beamlet/storage/transaction.ex:25` | 已封装 SQLite immediate transaction 和驱动错误语义 | 有可保留的基础设施能力，无需先发明完整通用数据库框架 |

## 历史建议方向（后续已批准并实施）

1. Storage 拥有连接、事务、数据集元信息与显式迁移机制，以及有实际共享价值的编码/内容能力；不拥有 Agent/Operation 业务词汇和 schema。
2. Actions contracts 保持纯数据；Actions/Runtime 的持久化模块拥有 Operation/attempt/evidence/accepted Result 与 executor journal，不理解 Agent。是否独立 Mix app 在详细设计时按 release 依赖闭包确定。
3. Agent 持久化拥有 Agent/event/checkpoint、turn/step/tool-call、来源授权与继承规则；通过 Agent 专有关系记录关联 Operation。
4. Agent 与 Actions 的持久化通过同一事务组合。需研究通用派发 fencing/capability 机制，保持 restore 与 claim 的并发安全，避免让通用 Actions 反向查询 Agent，也不能仅在上层先检查再提交。
5. Host/Operator 组合迁移与运行接线；基础存储不得硬编码全部上层数据模型。数据库物理分库不是职责拆分的前提。
6. 不扩展为任意 KV、ORM、工作流框架或多存储后端协议；通用性以已有 Agent、独立 Actions 两种实际使用方为验证对象。

## 兼容性证据与已确认决定

既往 durable 重建任务明确允许破坏 API/schema，并拒绝旧格式，禁止自动修改或删除真实数据：
`.trellis/tasks/archive/2026-10/10-18-durable-storage-core/prd.md:28`、
`.trellis/tasks/archive/2026-10/10-18-durable-rebuild/prd.md:16`。
最近纯 Agent Core 抽取则要求存储兼容：
`.trellis/tasks/archive/2026-10/10-18-agent-core-extraction/prd.md:19`。
这些说明策略取决于任务范围。2026-10-18 用户在本任务中明确回复“允许”，批准必要的持久化格式/API 调整；旧库明确拒绝，不自动转换或删除。此条仅记录当时的兼容性授权；最终设计随后已获明确批准并实施。

## 详细设计收敛

新增 Actions Storage / Agent Storage 库，分别拥有领域模型；Agent 关联表承载编排来源，通用 scope/epoch 替代 Actions 对 Agent generation 的反向查询。基础 Dataset 通过显式 profile/component 描述执行和核对迁移；Node 组合产品 profile。具体接口、事务锁序与兼容策略以 ../design.md 为准。

## 历史后续验证方向（最终结果见 independent-review.md）

- Actions-only 数据集与正常 Runtime prepare/dispatch/evidence/accept，无 Agent 表或配置前提。
- Agent 联合准备任一失败时全部回滚；command replay/accepted CAS 行为保留。
- claim 与 restore 并发时不会因拆分丢失 fencing；保留 SQLite/PostgreSQL 的真实适配器验证。
- Agent restore/fork/history/export 引用完整性不降低；纯 Agent Core 无新增 IO 依赖。
- Host opt-in、显式迁移、无自动执行/重试、unknown outcome 与旧格式安全拒绝的保证保留。
