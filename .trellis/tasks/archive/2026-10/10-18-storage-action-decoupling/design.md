# Storage / Actions / Agent 解耦设计

## 1. 设计目标与依赖

本设计已获用户批准并已实施；独立检查 READY，无剩余阻塞。需求见 prd.md；实际源码契约与最终证据见 research/spec-sync.md 和 research/independent-review.md。下文保留批准时的设计决策与约束。

```text
beamlet_actions                       纯 Operation/Execution/Result/Handler contracts
beamlet_storage                       Ecto/驱动、连接、事务、通用数据集、内容
beamlet_actions_storage -> actions + storage
beamlet_runtime -> actions + actions_storage + storage（直接使用基础能力时）
beamlet_agent_storage -> actions_storage + storage
beamlet_agent -> agent_core + actions + runtime + harness + agent_storage
beamlet_node -> 已有库 + 显式持久化组合
产品 hosts -> node
```

新增 `beamlet_actions_storage`、`beamlet_agent_storage` 两个无 Application callback 的库，模块前缀分别为 `Beamlet.Actions.Storage`、`Beamlet.Agent.Storage`。声明实际直接使用的 Ecto/JSON 等依赖，不能依赖 umbrella 根或偶然的传递依赖。Agent Storage 不依赖 Agent、Core、Runtime 或任何 host，避免循环。

选择独立应用而非只在原 Storage 中改 namespace：安装、测试和 release 闭包可以证明 Actions-only 不包含 Agent schema/migration/逻辑。Actions contracts 保持无持久化依赖。Agent Storage 的独立性也避免基础存储通过编译或动态回调依赖 Agent。

## 2. 职责归属

| 所属 | 保留或迁入的能力 |
| --- | --- |
| Storage | 通用 Repo/驱动配置、路径隔离、事务与安全错误、数据集 identity/format/component manifest、显式迁移执行、实时可写性探测、通用 canonical JSON/hash/UUID 与本地 artifact 内容/引用完整性 |
| Actions Storage | Operation/attempt/evidence/accepted Result、Operation 事件与读接口、通用 dispatch fence、executor journal/terminal artifacts、领域 codec 限制 |
| Agent Storage | Agent/event/checkpoint/command、编排关联、Agent CAS、来源授权/继承、Agent history/read 接口、Agent 事件词汇与 control payload 规则 |
| Runtime | durable 执行流程、结果转换、已准备请求核对、journal 使用；只使用 Actions Storage 的中立接口 |
| Agent | orchestration、纯 Core 调用、history/trace 的产品投影与 offline 验证，调用 Agent Storage 和 Actions Storage |
| Node | 已有角色组合之上选择具体数据集 profile、构造 host 接线、显式 operator 操作；产品主机继续只负责启用与配置 |

`Beamlet.Storage.Records` 拆出通用 validation/transaction helpers；`cas_agent` 等留在 Agent Storage。JSON canonical 编码及 digest 算法保持稳定；`:checkpoint`、Agent 事件白名单等领域 policy 移到各自所属层，通过基础编码参数使用，不让 Storage 靠领域 kind 选择规则。Artifact 是跨域实际共享的内容能力，可留在基础层；基础 artifact 表不引用领域表。

## 3. 数据模型

Actions authority 模型：

- `operations`：immutable description/digest、accepted result/evidence、CAS/version、高水位与记录时间。移除 Agent owner/turn/step/role/tool-call/ordinal/prepared_seq/sources。
- `executions`、`execution_evidence`：保留现有身份、去重、单 attempt 和 evidence 绑定约束。
- `operation_events`：Operation 的 prepared/accepted 事件；不共用 Agent 事件词汇或 Agent-only 列。
- `dispatch_scopes`：不透明 UUID 和单调 epoch。Operation 可选关联 `dispatch_scope_id` / `dispatch_epoch`；无 scope 的独立工作同样合法。

Agent 模型：

- `agents`、`agent_events`、`checkpoints`、`commands`：保留领域语义与唯一性。
- `agent_operations`：immutable operation_id、agent_id、turn/step/role/tool-call/ordinal、owner_generation、prepared_seq、ordered sources。operation_id 唯一并引用 Actions Operation，Agent 和 turn 查询索引保持。
- Agent 持有其 dispatch scope 的引用；generation 与 scope epoch 由同一受控事务推进。

跨域外键只从 Agent 关联指向 Actions Operation；Actions 表不引用 Agent。编排来源不塞入通用 metadata，不以重命名 owner_agent_id 伪装解耦。非 Agent 使用方可在自身模型中保存关系，通过完整逻辑请求和通用 artifact refs 提供输入，无需提供 Agent sources。

Agent 读取可在 Agent Storage 中联合领域关系和通用 Operation，向既有 Loader/History/Core 提供需要的领域投影。投影包含 owner_agent_id 等字段不等于通用 Operation 存储仍拥有这些字段。仓库读取方必须改为调用所属层，禁止保留旧 Storage facade 转发层。

## 4. 通用数据集与迁移

基础 `Dataset` 接受显式、可信、编译期定义的安装描述：profile 标识、容器格式、组件及版本、完整有序 migration 清单。基础层检查描述与磁盘清单一致，不查找 Agent/Actions 模块，也不接受数据/网络中任意模块名。迁移模块由所属库提供；profile 由组合方显式构造。

三个实际 profile：

1. Actions authority：foundation + Actions authority。
2. Agent authority：foundation + Actions authority + Agent。
3. Executor journal：foundation + Actions journal。

采用新的 dataset 容器格式 3，三种 profile 的首个领域组件版本为 1；它与原 authority2/journal1 都有显式区别。基础元数据记录 profile、完整组件版本及 migration 集合；migration ID 在 profile 内唯一、有序，组合冲突在创建文件/启动 Repo 前拒绝。组件命名与完整 migration IDs 由实现落定并写进契约测试，不能运行时探测后拼装。

`initialize` 仅安装新数据集，任一不完整安装不能被 `open` 当作可用；`open` 与 `verify` 永不迁移、补建组件或修复。缺失/额外/未知或新版本组件、错误 migration 集、错误 ID/profile、restored_backup 均明确拒绝。

SQLite 打开前保持 readonly preflight；PostgreSQL 连接后只读核验，不执行迁移。保持 WAL/FULL/FK、即时写事务、忙处理器与 PG fsync/synchronous_commit 等现有保证。两个物理 SQLite 数据集路径隔离由组合方提供对端路径，基础层只理解路径/实例隔离，不认识 authority/executor 业务角色。Repo adapter 支持与实例名来自显式可信配置，移除基于旧固定 Repo 模块推断领域 format/role 的逻辑；不顺带增加多 authority 实例承诺。

## 5. 事务组合接口

所有业务 facade 仍封装事务与安全错误。增加窄的事务参与接口：受控 `in_transaction` 入口或等价的 Ecto.Multi participant，只能在已开启的同一 Repo 事务内运行、仍验证自身输入，不自行提交、不调用外部效果。基础 Transaction 负责一次提交/rollback，Agent facade 不暴露 Repo/SQL 给产品上层。

Agent 准备流程：

1. 核对 command identity、generation/version 与 active turn；锁定/CAS Agent。
2. 验证 Agent sources、继承授权、orchestration 及通用 artifact 引用。
3. 经 Actions Storage participant 写 Operation/attempt/Operation event，绑定当前 dispatch scope/epoch。
4. 写 immutable agent_operations 关联及 Agent preparation events，提交原始 command response。
5. 一次提交成功后，才允许现有 Runtime 使用该 prepared identity 派发。

任一步失败整个事务回滚，包括所有批成员。未知提交结果继续依靠 command replay 查询，不自动再次准备或执行。来源和消费验证在 Agent Storage 内完成，结果唯一采纳与 evidence 约束在 Actions Storage 内完成。

## 6. 派发隔离与并发

通用 scope/epoch 用于撤销一组尚未派发请求的派发资格；它不依赖 Agent、不是权限/远程安全令牌，也不新增自动重试或 exactly-once 承诺。

- 创建 Agent 时同事务创建 scope；准备 Operation 时冻结 scope ID/epoch。独立 Actions 可无 scope，也可使用同一中立机制。
- restore 在 Agent transition 中先锁定/CAS Agent，再排他锁 scope 并推进 epoch；与 generation 更新一起提交。
- claim 先读取 immutable scope 绑定，再在 PG 持有 scope `FOR SHARE` 锁、Operation `FOR UPDATE` 锁直到 claim commit，检查 scope epoch、未 accepted、attempt/version，最后 CAS prepared -> send_claimed。SQLite 继续由 immediate 写事务串行化。
- participant/rotate 若需同时接触 scope 与 Operation，遵守 scope -> Operation 锁序；Agent 操作统一 Agent -> scope -> Operation。claim 不锁 Agent，accept 只锁/CAS Operation，不回头请求 scope/Agent 锁。
- restore 先提交则旧 epoch claim 拒绝；claim 先线性化则它保留既有已认领语义。restore 不撤销已发生的网络发送，不保证已运行 worker 被物理终止。
- 晚到 evidence 和 accepted Result 保留现有语义，不因 epoch 改写结果；Agent 消费仍核对自身 generation、关联及 accepted digest。

Runtime.Persistence 删除 Agent-shaped owner；已准备调用以明确期望的 Operation/attempt/digest/version 和可选 scope/epoch 绑定核验，核对实际 description、executor/boot、状态与未 accepted 条件。Agent 在上层完成 turn/step 关联校验；Runtime 不回调 Agent。`submit` 的 PID owner 生命周期语义与持久化作用域是不同概念，不能一起删除。

并发测试通过同步点/真实事务锁建立顺序，不以 sleep 或重试掩盖竞态。

## 7. Host、operator 与发布

通用 Storage.Host 仅管理显式命名的数据集描述和资源生命周期，返回不透明 handles/状态；不选择领域 migration、不制造 Runtime/Agent 配置。通用 Admission 依据 descriptor 核验与真实 rollback 写探测。

`Beamlet.Node.Storage` 组合现有角色配置、Agent authority profile 与 journal profile，并提供运行接线和显式 operator 初始化；现有 Server 启动和发布脚本迁入此入口。`mix beamlet.storage.migrate` 可保留操作命令名，但实现归 Node app，并调用组合层；Storage app 不反向调用 Node/Server。Actions-only 嵌入者直接选 Actions profiles，不需要 Node/Agent。

保留原 host storage 配置中不必变化的字段，说明新模块入口和新库安装步骤。更新根 backend_apps、直接依赖、所有 release 构建/复制验收脚本与 README。产品不增加新的 UI 选项或角色。Server 默认组合 Agent authority，不意味着基础 Storage 默认装 Agent。

## 8. 兼容、风险与回退

允许必要的持久化 API/格式变化，无兼容 shim；旧库安全拒绝并提示显式新库初始化，绝不覆盖旧文件。新旧代码分别使用各自数据集，回退时恢复旧代码并使用原未动旧库；不能把新格式库交给旧程序。代码中不实现数据导入或有损转换。

最高风险是 scope fencing 的锁序/原子性、读取投影与离线 trace 完整性、迁移组件核验、release 依赖。新格式如需调整 trace envelope/version，显式提升并让旧版本拒绝，不把旧/新规则默默混用；摘要保持 canonical 字节语义，不随文件迁移重算历史。

详细验证见 implement.md。实现与最终独立验证已完成；原始失败日志保持历史记录，最终结果见 research/independent-review.md。规格同步核验见 research/spec-sync.md；提交与 finish 仍由父会话负责。
