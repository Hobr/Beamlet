# Beamlet 领域术语

> 语言状态：本页是当前维护的中文版本。同目录 `GLOSSARY.md` 是早期的中文词表（无语言后缀），英文对照在后续阶段才补齐；本页不把它标成英文目标。

Agent、Operation 与执行历史的统一用语。词条按"归属应用 + 主模块"核对当前源码；定义描述**已实现的语义与边界**，凡是仅存在于设计文档的词汇会单独标注。字段、版本与预算以各应用 README 和 `.trellis/spec/backend/` 为准，本表不重复参数细节。

## 归属速查

| 概念 | 归属应用 | 主要模块 / 持久化位置 |
| --- | --- | --- |
| Agent、Authority、Agent definition、Continuation、Fork | `beamlet_agent` / `beamlet_agent_core` | `Beamlet.Agent`、`Beamlet.Agent.Durable`、`Beamlet.Agent.Core.Reducer`、`Beamlet.Agent.Core.Decision`；表 `agents`、`checkpoints` |
| Operation、Execution、Result、Handler | `beamlet_actions` | `Beamlet.Actions.Operation`、`Beamlet.Actions.Contracts` |
| 提交、放置、取消、执行证据核对 | `beamlet_runtime` | `Beamlet.Runtime`、`Beamlet.Runtime.OperationCoordinator` |
| 模型、工具、模型上下文来源 | `beamlet_harness` + `beamlet_agent` | `Beamlet.Harness.Model/Tool`、`Beamlet.Agent.ContextBuilder` |
| 中立持久化与准入 | `beamlet_storage` / `beamlet_actions_storage` / `beamlet_agent_storage` | `Beamlet.Actions.Storage.OperationRecords`、`Beamlet.Actions.Storage.DispatchScopes`、`Beamlet.Agent.Storage.AgentRecords` |
| 轨迹导出 | `beamlet_agent` | `Beamlet.Agent.TraceExport`、`Beamlet.Agent.TraceVerifier` |

## 核心实体

**Agent**：具有明确权威归属的推理主体，拥有自身输入、配置、编排关系和可暂停的继续位置；它只引用已采纳 Result，不保存模型/工具正文。
_避免_：Worker、Execution、Elixir `Agent` 进程状态容器（与 OTP `Agent` 模块无关）。

**Authority（权威）**：拥有某个 Agent 或独立 Operation 的业务状态与决定权的节点。一个 authority 数据集同一时刻只能由一个活动主机拥有；version/generation 只防本地并发与旧实例写入，不是跨分区 fencing。
_避免_：全局主节点、执行节点。

**Agent definition（Agent 定义）**：版本化的模型/工具策略、指令、环境与 secret 引用。配置版本摘要包含模型配置、目录与可移植配置，排除消息、工具参数与凭证，也不检查执行器根或适配器代码。
_避免_：每次请求重复提交的可变参数。

**Generation**：Agent 每被重新激活就递增的本地激活代数，用于串行化本地激活并退役旧发送者；它不等于跨节点租约。
_避免_：分布式锁、fencing token。

**Operation（操作）**：一次提交所请求工作的结构化描述，提交后其含义固定；kind、能力和环境标签都是不透明数据，不被解析为代码。
_避免_：Intent、Invocation、自然语言目标。

**Execution（执行尝试）**：为执行某个 Operation 而分配身份的一次尝试，包含尚未确认准入的情况；每 Operation 默认只有一次尝试。
_避免_：Worker 进程、Operation 的别名。

**Result（结果值）**：描述成功、失败、拒绝、取消、超时或不确定等终态的共享值；只有被权威接受后才成为该 Operation 的终态事实。
_避免_：独立结果实体、进度、取消请求。

**Execution evidence（执行证据）**：执行节点对准入、启动意图或完成情况保存的观察，可供权威核对；按执行端与证据 ID 去重，不等同于已接受的 Result。
_避免_：外部副作用证明、第二份权威状态。

**Result acceptance（结果接受）**：权威为某个 Operation 以 CAS 与唯一约束确认唯一终态值的决定；同一 Result 可重放，不同终态冲突。
_避免_：结果到达、结果消费。

**Result consumption（结果消费）**：Agent 将已接受的结果或显式采纳的证据纳入某个 Agent 上下文的决定；按 `agent_id + operation_id + consumption_kind` 去重。
_避免_：再次执行、结果接受。

**Command（幂等命令）**：写入接口的去重身份，保存 request digest 与提交响应；写入结果未知时按命令 ID 读取原响应，而不是重发写入。
_避免_：业务重试、外部幂等键。

**Checkpoint（检查点）**：绑定 `through_seq`、reducer 版本与 `safe_to_fork` 的 Agent 控制状态缓存，只用于加速从历史重建；可丢弃后重放，绝不保存模型/工具正文。
_避免_：权威聊天记录、进程快照、环境快照。

**Model context（模型上下文）**：按明确策略选择并组织 Agent 输入、Operation 描述及已采纳结果后，供一次模型调用使用的内容；它是构建产物，不落库为消息数组。
_避免_：完整执行历史、Agent 的永久消息数组。

**Continuation（继续位置）**：说明 Agent 下一步应等待、转换或请求什么工作的明确位置；以检查点上的枚举（如 `await_input`、`model_prepared`、`blocked`、`completed`）和 `Beamlet.Agent.Core.Decision` 的分类表达。
_避免_：可执行闭包、自动重试指令。

**Recovery（恢复）**：用已保存事实重建可审阅、可控制的 Agent 状态；恢复结果一律为暂停，是否继续工作是另一个显式决定。
_避免_：重执行、自动故障转移。

**Reconciliation（证据核对）**：按稳定身份查询或重读已有证据与记录来解释未决工作，不创建新的执行尝试；写入结果未知时也只重读。
_避免_：重试、重新派发。

**Fork（派生）**：从安全历史位置继承明确选择的内容引用，创建具有独立身份与编排历史的新 Agent；新 Agent 默认暂停且不确认共享环境风险，源执行归属保持不变。
_避免_：同一 Agent 的分支切换、执行历史重放。

**Rewind（回撤）**：设计词汇，指选择较早的安全位置派生新 Agent 作为后续推理起点。当前实现没有独立的 rewind API，等价操作是"对较早位置执行 fork"；不提供外部环境回滚或副作用撤销。
_避免_：撤销现实改变、回放执行历史。

**Trace（轨迹）**：对已观察输入、决策、请求、结果及相关因果关系的固定高水位导出（轨迹包 format2，区别于数据集 format3），可用离线校验器核对引用闭包。
_避免_：模型私有思维链、保证相同输出的重放脚本。

**Dispatch scope（派发作用域）与 epoch**：Operation 派发许可的不透明栅栏。轮换使旧 epoch 无法取得新派发许可，但不证明已派发的外部工作已经停止。
_避免_：业务状态、执行状态、分布式锁。

**Journal attempt（执行端日志尝试）**：执行端本地 SQLite 中记录的启动意图与回执事实；ACK 只证明权威保存了内容，不证明外部进程已停止。
_避免_：权威状态副本、结果接受凭据。
