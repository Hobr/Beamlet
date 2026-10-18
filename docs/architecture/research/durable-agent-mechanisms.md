# Agent durable / 恢复机制与轨迹用途调研

外部来源核查日期：2026-10-17。仅研究和设计，不实现代码。2026-10-18 新增已确认设计修订说明；未重新核验外部源码。

问题：在 Beamlet 已有 Agent / Operation / Execution 模型上，哪些持久化机制是必要的，哪些只是其他框架为其不同目标引入的抽象？

**当前结论以[修订主设计](../agent-operation-persistence.md)为准。** Agent 自身输入、配置与编排事件归 Agent，确定的 LLM/Tool 输入归 Operation，正文输出归 accepted Result。Agent 以纯事件归约恢复控制状态，检查点只加速，messages 仅是请求构建产物。正文不复制到 Agent 历史/检查点；fork 继承直接内容引用并保留来源，不重建父事件链。旧版“拒绝事件 reducer、复制消息检查点”决策已被替代；下文第 2–6 节保留前次研究与取舍，不应当作当前实施要求。

DeepSeek-Harness：用户提供了事件日志、关键提交屏障、SessionHandle、显式中断、未知 Tool 不自动重试及预设校验的思想总结；未提供锁定源码，本次未核验具体实现、flush/fsync 或故障保障。只借鉴事件优先、先记后做与恢复显式化，不把总结当一手实测证据，不照搬 JSONL/flush 接口。Beamlet 保留 Ecto 事务和 executor 本地日志；Agent replay 是纯数据归约，不是 Temporal 式业务代码重跑。预设标识必须结合版本/内容核对，同名配置不等于旧请求。

前次结论（历史决策，已被上述修订取代）：维持权威存储、执行证据、暂停恢复；durable 只新增**历史记录 + 检查点**两个原语。回撤通过复制安全检查点的有效上下文创建新 Agent，不设独立 Branch 实体或父前缀加载。不增加通用 Task、Document、Workflow 或确定性重放框架。会话记忆、执行恢复和观测 tracing 应区分保证，但可以共享记录内容和稳定身份。

配套：[主设计](../agent-operation-persistence.md)、[实施验收](../persistence-delivery.md)。

## 1. 范围与证据强度

- pi durable：读取 README、具体源码和恢复测试，锁定 commit `8efd314fa3d3232ce197d8d7a6a5660530b9d83e`。源码链接固定在该提交，不以未来 main 内容为本次证据。
- LangGraph、OpenAI Agents SDK、Temporal：核对官方专题文档；未锁 SDK 版本，也未运行其实现。以下是文档契约，不代表实测耐久性。
- “借鉴/不采纳/对 Beamlet 的影响”为本项目设计判断；不冒充来源原有结论。
- 未运行对方测试、kill VM、断电、跨主机或数据库一致性实验。pi 恢复测试的 close/reopen 也不能直接当作断电保障。

## 2. pi durable：有明确恢复语义的 Agent Harness

来源入口：[packages/durable](https://github.com/earendil-works/pi/tree/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable)，包在 README 中标为 experimental。

### 2.1 保存什么

[README 的 Concepts / Storage](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/README.md)区分：

- Conversation 是不可变 entries 构成的对话历史，含 user、assistant、tool-result、system change、reset 等。
- Document 是旁置的 JSON 状态，如 agent 配置、live 进度、inbox、usage；可独立指定历史和 fork 策略。
- Task 是持久状态机；GenerationTask 请求模型、等待 ToolTask，Task 保存 phase/checkpoint。
- Session 提供单条原子提交路径，已提交后才向观察者发布。

这不是把 Promise/函数栈保存下来。代码仍由 registry 重新提供，存储保存身份、版本与 JSON 检查点。[session.ts](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/src/session/session.ts)的 SessionImpl 将准备、写入、采纳和发布串行化；存储失败使 Session 失效，重新打开读取已提交状态。[SQLite commit](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/src/storage/sqlite/storage.ts#L187)将 writes 与 commit sequence 放进同一个数据库事务。

借鉴：业务记录、下一状态和对外可见性有共同提交点。Beamlet 使用 Ecto.Multi 及现有 Agent 状态机即可，不需要引入 Document registry 或通用任务层。

### 2.2 Tool 恢复与副作用窗口

[ToolTask 源码](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/src/harness/tool.ts#L48)明确保存执行意图：最终参数及 `replay: safe | unsafe`。正常路径先提交 execute checkpoint，再调用 Tool。

恢复后的 execute phase 只有在**保存的策略和当前 Tool 策略均为 safe** 时才重跑。否则产生“was interrupted and may have partially run”的结果，并保留已提交的部分输出。[恢复测试](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/test/harness-tools-recovery.test.ts)覆盖 unsafe 只调用一次、safe/safe 重跑，以及 safe/unsafe 或 unsafe/safe 均不重跑。

pi 的 unsafe 中断会作为错误结果交给模型，其测试可继续到回答完成；**这不等于模型之后不会自行再次请求相似副作用**。Beamlet 保持更保守的策略：不确定外部效果默认阻塞，先核对证据/显式决定，不能仅依靠“没有重跑同一个 ToolTask”判断整个 Agent 没有重复操作。

pi 允许 safe Tool 在重新执行时使用当前 cwd 环境，测试明确覆盖 cwd 变化。Beamlet 不采用该环境语义；既有计划要求稳定环境引用，不可恢复到同路径的另一环境。

### 2.3 打开、调度与模型请求

[Scheduler.open](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/src/harness/scheduler.ts#L289)将遗留 running Task 变回 pending 并保留 checkpoint，打开过程本身不派发。README 说明 `resume()` 或请求进展的接口可启用调度。不能把它概括成“打开存储后任何操作都保证不执行”。

[GenerationCheckpoint](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/src/harness/generation.ts#L50)包含 prepare/request/retry/poll/tools，固定请求模型、参数和历史 cutoff，并支持模型请求恢复/重发及 provider deferred handle。Beamlet 不引入通用任务调度，也不把模型请求天然当作无代价的安全重试；已 claim 的模型 Operation 同样核对证据。显式继续可以创建新的关联请求。

### 2.4 Fork、压缩与界面

[README](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/README.md)与[forks.ts](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/src/session/forks.ts)表明：fork 继承父 conversation 到指定 entry 的前缀，document 可选 initial/current/asOf；fork 获得新的 provider session 身份。Compaction/reset 改变模型看到的上下文，原 entries 留在存储中。

界面 watch/events 来自已提交状态；慢客户端积压超过限制后收敛为最新 snapshot，而非无限积压历史 delta。usage 按模型/Tool 累计，包含失败/取消尝试。

借鉴：从历史检查点继续探索，以及**完整历史和有效模型上下文不是同一个集合**；持久保存实际 context manifest 和压缩来源。pi 的共享前缀属于其实现选择，Beamlet 首版采用物化复制有效上下文，不复用父链解析或 document fork 策略。Beamlet fork 后不可复用旧 provider 会话句柄，新调用需重新建立 provider 会话身份；引用旧消息不代表复活旧远端 session。无需引入 pi 的通用 document fork 策略或 Chord 状态同步。

### 2.5 “durable”的实际故障模型

[Node SQLite adapter](https://github.com/earendil-works/pi/blob/8efd314fa3d3232ce197d8d7a6a5660530b9d83e/packages/durable/src/storage/sqlite/node.ts)使用 WAL、`synchronous=NORMAL`、`BEGIN IMMEDIATE`。README 明确承认最近提交可能在断电/主机故障时丢失；JSONL 需显式 fsync，每个 storage 假定单进程拥有，无跨进程所有权锁。

因此不能因为包名 durable 就推导断电不丢或分布式接管。Beamlet 仍用 SQLite FULL 和同权威独占部署；执行节点日志用于保存远端完成证据，pi 的本地单 storage 机制不能直接替代它。

## 3. 其他官方方案对比

| 方案 | 保存与恢复单位 | 可迁移经验 | 不迁移的机制/保证 |
| --- | --- | --- | --- |
| pi durable | entries + documents + Task checkpoint | 先提交意图、明确中断、历史前缀、上下文与历史分离 | 通用 Task/Document、safe 自动重跑、code-mode 重放 |
| LangGraph | thread、super-step checkpoint 与 pending writes | 清晰检查点边界、保留成功节点输出、历史 fork | 图执行器、节点重跑规则、通用 checkpointer 插件层 |
| Agents SDK sessions | run 前装载/后保存 conversation items | 会话上下文复用、分支与 usage 查询 | 不把 sessions 自身解释为 durable executor |
| Temporal | 服务端 Event History、确定性 Workflow replay、Activity completion | 已记录结果不用再执行；清楚说明成功未上报窗口 | Temporal 服务、Workflow DSL、确定性限制、自动 Activity retry |

### 3.1 LangGraph

[Checkpointers](https://docs.langchain.com/oss/python/langgraph/checkpointers)说明 checkpoint 位于 thread/super-step 边界，同一步中成功节点的 pending writes 可避免其他节点失败后的重复计算；pending writes 不等于可 time travel 的完整 checkpoint。持久模式 sync/async/exit 的提交时点和故障窗口不同，不能仅凭存在 checkpointer 声称进程崩溃后完整恢复。

[Time travel](https://docs.langchain.com/oss/python/langgraph/use-time-travel)会复用 checkpoint 以前的状态、重新执行之后的节点，包括 LLM/API；修改历史状态形成分支，后续输出可以不同。我们借鉴分支与状态边界，但不允许“回撤”悄悄重复真实 Tool 副作用。

### 3.2 OpenAI Agents SDK

[Sessions](https://openai.github.io/openai-agents-python/sessions/)定义 run 前读取历史、run 后保存本轮 items 的会话记忆；接口 get/add/pop/clear 并不独自提供任意 Tool 执行窗口的持久证明。[AdvancedSQLiteSession](https://openai.github.io/openai-agents-python/sessions/advanced_sqlite_session/)提供基于用户消息的分支和轮次 usage；usage 需要调用者保存，不能推出消息和用量始终原子。

[Tracing](https://openai.github.io/openai-agents-python/tracing/)保存 generation/tool/handoff/guardrail 等 spans，默认内存批处理并后台导出，适合调试、可视化、监控。正常退出 flush 不等于突然崩溃不丢；trace 不是权威恢复日志。输入输出与标注可以供离线评测使用，是记录的下游用途，不意味着所有 trace 自动成为完整、正确的评测集或训练集。

### 3.3 Temporal

[Workflow Execution](https://docs.temporal.io/workflow-execution)的 replay 重建确定性控制流，已完成 Activity 的结果从历史取得。[Activity Definition](https://docs.temporal.io/activity-definition)明确区分“观察到完成一次”和“只执行一次”：Activity 可执行多次、部分完成多次，并举出成功后 worker 未上报就崩溃导致重复扣款的窗口，因此建议业务幂等键。

[Activity Execution](https://docs.temporal.io/activity-execution)依赖 timeout/retry 检测和重新调度。Beamlet 不具备其服务端历史/可用性基础，也不需要其通用工作流能力；保留一次 attempt 和 unknown 处理即可。

## 4. 轨迹为什么值得保存

| 用途 | 保存什么 | 不应误解为 |
| --- | --- | --- |
| 恢复控制状态 | 检查点、稳定身份、请求/结果/消费记录 | 重跑全部历史 |
| 解释错误与审阅行为 | 实际模型上下文、完整回复、Tool 参数/结果、因果与证据 | 只记录最终答案或依赖 sampled spans |
| 回撤与比较替代路径 | 复制的上下文、来源检查点、配置版本 | 撤销现实世界或必须采用共享父前缀 |
| 分析延迟/用量/费用 | 本地 duration、usage、模型与价格版本（若有） | 从跨机 UTC 相减得到精确耗时，或 token 数等于账单 |
| 离线评测/回归样本 | 固定输入、配置、Tool 观察、预期结果/人工标签 | 直接重放有副作用 Tool 或保证模型逐字相同 |
| 改进上下文策略 | 原始消息、实际请求 manifest、压缩/重置的来源关系 | 用一份压缩后 transcript 覆盖全部历史 |

前四项直接影响首版数据契约；后两项可通过同一导出格式支持，不在核心加入 evaluator、span store、dataset manager 或训练引擎。恢复需要强持久提交；观测数据允许有界丢失。两者用稳定 ID 关联即可。

## 5. 对 Beamlet 提案的具体简化

| 上一版机制 | 收敛后的机制 | 保留的不变量 |
| --- | --- | --- |
| 规范化 messages/turns 与 events 并存 | 消息与轮次事实统一为类型化历史记录；用索引查询 | 完整模型输入输出、Tool 顺序、Agent 归属 |
| 独立 streams 表 | Agent/独立 Operation 内的历史序号 | 提交顺序、固定导出范围 |
| 独立 dispatch_intents | Execution 的 prepared/send_claimed 字段 | 发送前落盘、模糊窗口不重发 |
| evidence inbox / relations / artifact links | evidence 具体表；关系事件；artifact 引用；无自动 GC | 证据幂等、因果、完整性 |
| event reducer / upcaster 机制 | 自足检查点 + 普通版本读取 | 恢复无需旧业务代码，不执行副作用 |
| 通用 Storage.commit(bundle) | 具体存储函数内部使用 Ecto.Multi | 原子多表更新、跨库明确非原子 |
| 导出 pin/租期/后台任务 | 保留历史，有界分页流式导出 | 范围固定、内存有界 |
| 单独公开 reconcile/resolve 接口族 | 私有 Runtime 核对 + Agent.continue 决定入口 | 已接受 Result 不改写，用户决定可追溯 |
| 独立 branches 与父前缀共享 | 从安全检查点复制有效上下文，原子创建独立的新 Agent；仅记录 fork 来源 | 原历史不变、上下文自足、原 Agent 迟到结果不推进新 Agent |

首版权威模型从十六张逻辑表先收敛到九张，随后按用户确认移除 branches，最终为八张；executor 日志从两张收敛到一张。这不是性能结论或表数硬指标，而是去掉尚无必要的概念拆分。实现时新增表仍须由查询/完整性约束或实测需要证明。

只新增历史记录、检查点两个 durable 原语。fork/回撤是操作，继续位置仍是 Agent 状态字段，执行证据是 Execution 的观察，命令去重是接口可靠性字段。所有崩溃窗口、结果接受一次、每 Agent 消费一次、旧实例与原/新 Agent 隔离均保留。

复制与共享前缀的取舍：首版接受上下文存储重复，以移除祖先递归、cutoff 可见性、active-branch 切换及祖先导出依赖。只复制有效上下文，不复制整个审计历史、执行实体、待执行工作或命令去重；继承消息有来源标记，artifact 可共享，provider 会话重新建立。新 Agent 不依赖父 Agent 加载，原始执行证据仍归原 Agent；导出不能把继承观察伪装成新执行。

## 6. 未采纳与后续触发条件

- 不增加 Branch 实体或共享前缀：只有明确需要同一 Agent 内切换大量路径，或实测上下文复制成本不可接受时，再讨论。
- 不增加 replay-safe：只有产品明确需要自动恢复执行，并能定义 provider 幂等/副作用分类时，才单独讨论新 attempt 策略。
- 不增加通用 Task/Workflow：只有出现多个不能由 Agent/Operation 表达的可复用持久业务状态机时再评估。
- 不增加文档增量重放、GC lease 或对象存储协议：只有实测容量/吞吐需要时再引入。
- 不实现任意节点 time travel：首版仍从无未决效果的安全检查点 fork。
- 不把 trace 导出当作模型私有思维链采集；只保存系统实际可观察且允许保存的数据。

实际实现仍须完成[故障注入验收](../persistence-delivery.md)。外部框架文档和测试都不能替代 Beamlet 自己的双库、断连与进程/VM 重启证据。
