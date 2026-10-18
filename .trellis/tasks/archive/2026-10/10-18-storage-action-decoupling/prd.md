# Storage / Actions / Agent 职责解耦

## 目标与价值

让 beamlet_storage 成为可复用的持久化基础设施，Actions 和 Agent 各自拥有领域持久化实现。非 Agent 调用者应能独立使用 Actions/Runtime 的完整持久化执行路径，既不安装 Agent 表，也不提供 Agent 类型或配置。

## 背景与证据

用户要求：agent/action 的 storage 实现解耦，借助通用 storage 实现；actions 系统及对应 storage 不应耦合 agent 等具体场景。

Actions contracts 已无 Agent/Storage 依赖，但持久化存在以下问题：

- `apps/beamlet_storage/lib/beamlet/storage/schema/operation.ex:7`：Operation 混入 Agent owner/turn/step/role 等编排字段。
- `apps/beamlet_storage/lib/beamlet/storage/operation_records.ex:215`：派发直接查询 Agent generation。
- `apps/beamlet_runtime/lib/beamlet/runtime/persistence.ex:28`：持久化 owner 固定为 Agent 身份结构。
- `apps/beamlet_storage/lib/beamlet/storage/agent_records.ex:91`：Agent 准备 Operation/attempt 与追加 Agent 事件在同一事务，必须保留原子性。
- Storage helpers、事件词汇与数据集安装也混入领域职责；完整锚点见 [源码调研](research/boundary-findings.md)。

## 已确认范围与约束

- 用户已批准创建任务和规划。
- 用户已明确允许必要的持久化格式和公开持久化接口调整。
- 旧数据集明确拒绝打开；不自动转换、清空、删除或修复真实数据。不提供旧格式/API 兼容层。
- 本任务作为一项集成迁移推进：数据模型、原子事务、Runtime 接线与产品调用必须共同成立，内部按执行阶段分步检查，不创建可被误认为独立交付的子任务。

## 要求

- R1：基础 Storage 不拥有 Agent/Actions 领域模型、事件词汇或业务约束；两个领域作为使用方持久化自身数据。
- R2：Actions contracts、Runtime 和 Actions 持久化不依赖 Agent 类型、表、回调或配置；非 Agent 调用者能完成正常 durable 执行。
- R3：Agent 持久化拥有编排、来源授权、继承与关联信息；保留联合准备原子提交、generation fencing、command replay、accepted Result 唯一采纳及引用完整性。
- R4：保留 opt-in 启动、显式初始化、unknown outcome 保守处理及不自动重试/重放副作用等保证；持久化失败不能冒充不存在。
- R5：迁移仓库内调用、配置说明、测试及发布闭包；基础层与两个领域的依赖方向可验证，Agent Core 保持纯计算。
- R6：按照本轮兼容性决定管理格式；旧库、缺失/不匹配/较新组件及恢复标记安全拒绝，真实数据不会被自动修改。

## 验收标准

- AC1/R1,R5：依赖和源码检查确认 Storage 不理解 Agent/Operation/Runtime 业务；Actions contracts 不新增存储依赖，Actions 持久化及 Runtime 不依赖 Agent。
- AC2/R2：仅安装 Actions 模型、不存在 Agent 表及配置的数据集，完成正常 Runtime prepare、dispatch claim、执行日志、evidence、accepted Result 及重启后查询；以非 model/tool 的通用 Handler 验证。
- AC3/R3：Agent 联合准备在任一参与者失败时全回滚；命令重放返回原响应，参数变更冲突；外域/错误关联和来源被拒绝。
- AC4/R3：受控并发覆盖 restore-before-claim 拒绝旧派发，以及 claim-before-restore 的既有线性化语义；晚到证据可保留，已采纳结果不被覆盖，旧 generation 不能消费为新编排结果。
- AC5/R3,R5：Agent 恢复、fork、固定高水位 history/export 与离线验证保留来源和摘要校验，不复制 Operation 为新执行；Core 不增加 IO 或存储依赖。
- AC6/R4：加载库不启动 Repo；host 不初始化或迁移；无 storage 配置行为不变，admission 实测验证，unknown outcome 不触发业务重试。
- AC7/R6：新数据集显式初始化；旧 authority/journal、组件集合/版本/迁移清单不匹配、dataset identity 错误和恢复标记均拒绝；验证旧库业务内容及 schema 未被改写。
- AC8/R1–R6：SQLite/PostgreSQL 执行同一适用契约；全伞编译/测试、静态检查、命名节点与相关 copied-release/durable e2e 实际结果记录完整，不把缺失适配器或环境当作通过。

## 不在范围

任意 KV/ORM 框架、新存储后端、通用 Workflow/调度器、自动重试/切主、物理分库、GC、新 provider、UI 功能及跨物理主机/断电保证。旧库迁移工具与兼容层不在本次范围。

## 规划交付

- [设计](design.md)：应用归属、通用数据集、事务组合与派发版本隔离。
- [执行计划](implement.md)：步骤、验证命令、风险与回退点。
- `implement.jsonl` / `check.jsonl`：实施与检查上下文。

需求已收敛，无阻塞产品问题。用户于 2026-10-18 在审阅最终规划摘要后明确回复“批准”，授权按本 PRD、design.md、implement.md 进入实施。实现与验收结果另行记录，不将规划视为通过证据。
