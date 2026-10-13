# Beamlet: Distributed Durable Effect Runtime - 架构研究与 SPEC 设计

我正在准备使用 Elixir / OTP 开发一个通用的**Distributed Durable Effect Runtime**. 其初始应用场景是 AI Agent, 但 Runtime
本身不应与某种 Agent 框架/LLM SDK 或特定业务绑定.

目前希望通过架构研究/讨论和形式化建模, 确定一份**简洁/优雅/可靠且可扩展的项目架构**, 并生成 RFC / SPEC 文档供人类和 AI
Agent 共同阅读/审阅和指导后续开发.

**当前阶段不追求代码实现. 不要直接生成项目代码, 而应优先讨论核心语义/状态机/数据模型/分布式协议与架构边界.**

以下内容包含已经形成的设计倾向和仍需验证的假设. 请保持批判性, 不要默认所有设计都正确.

## 核心目标

系统有两个主要需求:

1.**Distributed Execution**: 外部操作可以被调度到不同设备或节点执行, 支持异步/并发及跨设备执行. 2.**Durable Execution**:
外部操作的 Intent(意图)/Execution(执行尝试)/Outcome(权威结果)及必要的状态变化事实能够持久化,
并在进程退出/设备离线或系统故障后恢复.

这里的 Durable 不意味着保存进程内存/调用栈或语言级 Continuation, 我们主要追求**Effect Boundary 级别的恢复**.

例如, 在 AI Agent 场景中:

- Agent 收到用户 Prompt 后进行 LLM 调用, 这本身是一次外部操作.
- LLM 返回多个 Tool Call, 每个 Tool Call 被解析为独立的外部操作.
- 不存在依赖关系的 Tool Call 可以异步并发执行, 甚至被分配到不同设备.
- 需要用户确认时, Human Interaction 也是一次外部操作.
- Agent 可以等待多个外部操作完成, 也可以根据已完成的部分结果继续决策.

每次外部操作都独立记录/调度和恢复.

如果 Agent 崩溃, 我们不要求恢复原有函数调用栈, 而是允许根据已经持久化的操作事实/结果和必要上下文重新启动 Agent,
使其继续执行.

这种恢复暂称为**Effect-level Recovery**.

需要区分:

- Effect 的执行恢复;
- 已完成 Outcome 的复用;
- 多个 Effect 之间的依赖与等待关系;
- 任意函数控制流的恢复;
- Agent 上下文的重建.

本项目主要负责前两者, 并研究如何为上层提供必要的恢复能力.

## 原则

系统应该尽可能遵守:

- 核心模型简单, 不要过度设计.
- 操作意图是可序列化的数据.
- 明确操作生命周期/状态转换及其不变量.
- 不同外部操作能够独立异步执行.
- 调度/传输/存储和 Handler 可以替换.
- 已提交的操作事实/状态和结果能够恢复.
- 业务层不需要直接处理节点通信细节, 但可以显式指定执行约束.
- 核心领域模型尽可能独立于数据库/网络和具体执行环境.
- 允许未来支持新类型的外部操作与执行环境.
- 优先利用成熟的 Elixir / OTP / Ecto 生态, 避免重复实现已有基础设施.
- 在保证语义正确性的前提下, 优先选择实现成本较低的方案.

## 非目标

当前不追求:

- 任意函数内部状态的恢复;
- Continuation 级别的持久化与恢复;
- 指令级 Checkpoint;
- 分布式共享内存;
- 对外部副作用的自动回滚;
- 对外部操作保证 Exactly-once Execution;
- 完整 Event Sourcing;
- 自定义语言或 DSL;
- 默认中心化或去中心化;
- 通用 Workflow Engine 的全部能力.

以上是第一阶段的非目标, 不意味着未来永远不能支持.

## Effect 的定义

Effect 是对外部操作的可持久化描述, 其执行和结果独立于原始计算.

Effect 不是必须直接执行的函数, 而是描述需要外部环境完成什么操作的意图.

典型 Effect 包括:

- LLM 调用;
- 人类交互 / 审批;
- Tool Call;
- 文件系统操作;
- Browser / Device 操作;
- 外部 API 请求.

需要研究:

1. 这些操作能否真正共享统一的核心语义？
2. 哪些差异应该由 Handler/Policy 或独立协议表达？
3. Effect 是否应该具有同步 / 异步的区分, 还是所有 Effect 本质上都可以被异步提交并最终产生结果？
4. 对于长时间等待/外部回调和人工交互, 是否应采用不同的 Execution 协议？

## 初始领域模型: Intent / Execution / Outcome

当前倾向采用 Intent / Execution / Outcome(IEO) 作为三个核心领域概念.

这是待验证的设计假设, 不应预先认定其完全正确.

### Intent

Intent 描述一个逻辑操作意图.

- 可序列化;
- 操作定义创建后不可变;
- 生命周期状态可以变化;
- 不应绑定固定 Worker;
- 同样的输入可以对应不同 Intent;
- 可以拥有多个 Execution;
- 最多拥有一个权威 Outcome.

需要区分 Intent 的不可变定义与其可变生命周期状态.

### Execution

Execution 表示某个 Intent 的一次实际执行尝试.

- 一个 Intent 可以拥有多个 Execution;
- 每次重试或重新调度产生新的 Execution;
- 所有 Execution 都应保留, 而不是覆盖旧的执行记录;
- Execution 拥有独立生命周期;
- 不同 Intent 的 Execution 可以并发;
- 同一个 Intent 也可能存在多个并发 Execution;
- 超时不意味着外部操作必然失败;
- 执行成功不意味着结果一定被权威提交.

Execution 的生命周期可能包括:

`Created -> Dispatched -> Running -> Succeeded / Failed / Unknown`

以上状态仅为候选, 需要进一步研究其完整性与合法转换规则.

### Outcome

Outcome 表示某个 Intent 最终被系统接受的权威结果.

- 一个 Intent 最多拥有一个权威 Outcome;
- Outcome 一旦提交, 不允许原地修改;
- Outcome 可以表示成功/失败/取消等终态, 但具体分类需要研究;
- 已提交 Outcome 能够在恢复时直接复用;
- Execution 的实际结果与被接受的 Outcome 应明确区分.

需要研究:

- Outcome 应属于 Intent 还是 Execution？
- Execution 是否需要独立保存其执行结果？
- Outcome 是否必须关联某次 Execution？
- 取消/拒绝/超时和未知结果是否都应该产生 Outcome？
- 是否需要将终态与结果数据分开建模？

## 组合状态机模型

当前考虑将 IEO 建模为一个**组合状态机系统(Composed State Machines)**.

初步倾向:

- Intent 是父级逻辑状态机, 管理操作生命周期及最终结果.
- Execution 是从属的执行尝试状态机, 管理单次执行生命周期.
- 一个 Intent 可以拥有多个 Execution 状态机, 并允许它们并发运行.
- Outcome 是 Intent 最终接受的不可变结果事实, 不一定需要独立的状态机.
- 不同状态机之间存在需要原子提交的关联转换.

这里的父子关系主要表示逻辑归属与生命周期协调, 不应未经论证就采用严格的 Hierarchical State Machine 嵌套状态语义.

需要研究:

1. 组合状态机是否比独立 IEO 状态模型更合理？
2. Intent 和 Execution 的状态应该如何定义？
3. 哪些转换是局部的, 哪些需要跨状态机原子执行？
4. 是否需要一个统一的 Transition 协议？
5. 如何避免通用状态机框架抹平领域语义？
6. 状态机能否以纯函数形式描述, 以便测试和形式化验证？
7. 是否需要区分状态机命令/状态转换和持久化事实？

## Transition History

当前倾向持久化关键状态转换, 以便审阅/调试/诊断和追踪分布式执行问题.

例如:

`Execution: Created -> Dispatched -> Running -> Unknown`

Transition History 应能够解释:

- 什么状态发生了变化;
- 变化发生在什么时候;
- 谁发起或确认了转换;
- 为什么发生转换;
- 涉及哪个 Worker/租约或调度决策;
- 转换是否属于某次跨状态机原子提交.

当前倾向:

- Transition History 采用 Append-only;
- 状态更新与对应 Transition 在同一个本地数据库事务中提交;
- 当前实体状态仍然是权威状态来源;
- Transition History 主要用于审计/调试和诊断;
- 不强制从 Transition History 重放重建整个系统;
- 不引入完整 Event Sourcing.

需要研究:

1. 哪些状态变化必须记录？
2. 是否需要记录没有改变状态的拒绝/迟到结果和冲突事件？
3. 如何区分状态转换/领域事件和普通日志？
4. 如何保证状态与 Transition History 的原子一致性？
5. 是否需要全局 Sequence, 还是仅需实体内 Revision 和事务关联？
6. 如何处理不同节点的时钟差异与事件顺序？
7. 如何避免历史记录无限膨胀？
8. 是否应该支持可配置的历史保留策略？

不要仅因为存在 Append-only Transition History, 就认定系统必须采用 Event Sourcing.

## 持久化模型与 Ecto

计划使用**Ecto** 作为主要的数据映射和持久化基础设施, 并兼容多个存储后端.

候选包括:

- ETS: 内存模式/缓存或测试;
- SQLite3: 桌面/移动设备和单机 Durable Runtime;
- PostgreSQL: 服务端或多 Runtime 实例共享存储.

需要明确: ETS 是易失性内存存储, 不应被视为与 SQLite / PostgreSQL 具有相同 Durable 保证的后端.

当前倾向采用四个核心逻辑实体:

```text
intents
executions
outcomes
transitions
```

其中:

- `intents` 保存逻辑操作定义与当前生命周期状态;
- `executions` 保存每次独立执行尝试;
- `outcomes` 保存最终接受的权威结果;
- `transitions` 保存关键状态变化及原因.

这四个实体是当前首选方案, 但不是必须坚持的表数量.

请研究以下替代方案:

1. 独立 IEO 表 + Transition History;
2. 统一 State Machine 表 + Transition History;
3. 其他更简洁/约束更清晰的关系模型.

不要以减少数据库表数量作为主要优化目标.

### Storage Abstraction

当前倾向由 Runtime 定义自己的 Storage Behaviour, 避免核心状态机直接依赖具体 Ecto Repo.

需要研究:

- Ecto Schema/Repo/Adapter 与自定义 Storage Behaviour 应如何分工;
- 哪些操作必须成为 Storage 层的原子接口;
- 如何使用 Ecto.Multi 和数据库约束实现一致性;
- SQLite 与 PostgreSQL 的并发控制差异;
- ETS 是否应使用独立的 Memory Storage 实现;
- 是否应该定义 Durable Storage 与 Ephemeral Storage 的能力区别;
- 如何让不同后端满足同一套领域不变量;
- 是否需要 Storage Capability / Conformance Tests.

尤其需要避免把不同存储后端的事务语义错误地视为完全相同.

### 数据序列化

需要研究:

- 是否适合使用 Erlang External Term Format(ETF)保存输入/策略/结果和状态机数据;
- 如何避免持久化 PID/Reference/Function 等运行时对象;
- 如何保证旧数据在 Runtime 升级后仍然可解释;
- 是否需要为跨语言 Worker 定义独立的 Wire Format;
- 大型文件/二进制产物是否应仅保存引用和必要元数据.

## 状态转换与原子提交协议

这是本项目需要优先确定的核心问题.

当前倾向使用统一的 Transition Coordinator 或类似机制, 负责:

1. 接受领域命令;
2. 加载当前状态;
3. 验证状态转换是否合法;
4. 检查 Revision/Lease/Fencing 等并发约束;
5. 生成新的状态与转换事实;
6. 在同一个本地事务中持久化相关状态/Outcome 和 Transition;
7. 在提交后触发后续异步执行或通知.

需要研究:

- 是否应该将状态机定义为 `transition(state, command) -> result` 形式的纯函数;
- 如何表达跨 Intent / Execution 的原子转换;
- 如何处理并发 Coordinator;
- 如何避免重复 Outcome;
- 如何保证状态变更与 Transition History 一致;
- 如何保证数据库提交后/消息发送前崩溃时任务仍可被发现;
- 如何实现可靠派发与恢复扫描;
- 是否需要 Transactional Outbox, 还是可以使用数据库状态驱动的调度方式.

注意: 本地数据库事务不能跨越真实的外部 Effect 执行.

## 异步并发与依赖关系

系统必须允许多个互不依赖的 Intent 同时执行.

例如 LLM 一次返回三个 Tool Call:

```text
LLM Outcome
  |
  +-- Intent A -> Execution A -> Outcome A
  |
  +-- Intent B -> Execution B -> Outcome B
  |
  +-- Intent C -> Execution C -> Outcome C
```

三个 Intent 可以同时被创建/持久化和调度.

需要研究:

- 并发执行是否只需要独立的 Intent 生命周期;
- 是否需要为多个 Intent 提供统一的等待接口;
- `await_all`/`await_any`/`quorum` 等机制应属于 Runtime 还是上层 Computation;
- 多个 Intent 的依赖关系如何表示;
- 等待关系是否必须持久化;
- Agent 崩溃后如何知道自己正在等待哪些 Intent;
- 如何处理共享资源上的并发副作用;
- 是否需要将依赖图纳入核心模型.

当前倾向保持 IEO Engine 专注于 Effect 的执行与恢复, 而将复杂的 Computation / Workflow 协调放在上层.

但需要验证这一边界是否足够支持实际 Agent 场景.

## 分布式执行与恢复语义

需要研究以下场景:

1. Intent 已持久化, 但尚未派发, Coordinator 崩溃.
2. Execution 已创建, 但 Worker 尚未收到任务.
3. Worker 已收到任务, 但执行前崩溃.
4. Worker 已完成外部操作, 但 Outcome 尚未提交.
5. Outcome 已提交, 但 Agent 尚未收到通知.
6. Worker A 超时, Worker B 接管, 随后 Worker A 返回结果.
7. 两个 Execution 并发完成, 并同时尝试提交 Outcome.
8. Human Approval 等待期间所有运行时退出, 随后重新启动.
9. 同一个 Agent 重新启动后, 再次产生语义相同的操作请求.
10. 三个并发 Tool Call 已完成两个, Agent 随后崩溃.
11. Worker 与 Coordinator 发生网络分区.
12. Coordinator 所在设备永久离线, 但其他 Worker 仍然可用.

请明确:

- 哪些情况可以自动恢复;
- 哪些情况只能标记为 Unknown;
- 哪些情况需要幂等协议;
- 哪些情况需要外部状态查询;
- 哪些情况需要人工协调;
- 哪些情况必须依赖存储权威节点重新可用, 或明确的所有权迁移协议.

重点研究:

- Lease;
- Fencing Token;
- Idempotency;
- At-least-once Delivery;
- Result Reconciliation;
- Coordinator Ownership;
- Authority Transfer;
- Failure Detection;
- Retry Policy.

不要将 Exactly-once Outcome Commitment 与 Exactly-once External Execution 混为一谈.

也不要默认使用 Distributed Erlang 作为唯一通信方案.

## Effect Handler

研究 Handler 应提供哪些最小能力.

需要考虑:

- 同步执行;
- 异步执行;
- 长时间等待;
- 外部回调;
- 取消;
- 幂等;
- 结果未知;
- 状态查询与协调;
- 执行权限;
- 执行环境依赖;
- Handler 版本与兼容性.

请评估 Handler 的执行协议是否应该与 IEO 领域模型分离.

不要假定所有 Handler 都支持取消/查询或幂等. 应研究这些能力如何显式声明.

## Version / Schema Identity

目前不希望引入不必要的版本管理系统.

需要研究:

- 是否需要显式 Version;
- 是否可以将版本编入 Operation Identity, 例如 `llm.generate.v1`;
- Schema Hash 的实际价值是什么;
- Hash 能否替代 Version;
- 如何区分 Schema Identity/Implementation Identity 和 Content Identity;
- 如何让旧 Intent 在新 Runtime 中仍然可解释;
- 是否需要 Schema Registry;
- 如何处理执行过程中 Handler 升级;
- 状态机规则升级后, 旧状态和 Transition 如何解释.

优先寻找最小/稳定且能够长期演进的方案.

## 形式化建模与验证

计划研究使用**Quint** <https://quint-lang.org/>.

希望通过形式化建模确定核心状态机/并发提交和故障恢复协议.

需要研究:

1. Quint 是否适合描述组合状态机;
2. 如何表示 Intent / Execution / Outcome;
3. 如何表示 Transition History;
4. 如何建模并发 Worker/超时/重试/迟到结果与 Coordinator 崩溃;
5. 如何验证 Outcome 唯一性;
6. 如何验证状态与转换记录一致性;
7. 如何验证 Lease / Fencing 规则;
8. 如何验证恢复后的状态合法性;
9. 如何区分 Safety 与 Liveness;
10. 如何将 Quint 模型与工程 SPEC 对应起来.

Quint 模型应尽可能独立于 Elixir/Ecto/SQLite 和具体网络实现.

需要明确形式化验证的边界: 模型检查能够验证给定模型及假设下的性质, 但不能自动证明实际实现完全正确.

## 架构研究要求

请结合已有理论/论文/开源项目及成熟工程实践研究, 不要只凭直觉设计.

特别关注:

- Elixir / OTP;
- Ecto;
- SQLite / PostgreSQL;
- Skuld;
- Temporal;
- Restate;
- Durable Execution;
- Algebraic Effects;
- Actor Model;
- State Machines;
- Event Sourcing;
- Distributed Task Execution;
- Quint / TLA+.

需要区分:

- 已经存在的成熟工程方案;
- 有理论依据的设计原则;
- 当前项目特有的需求;
- 尚未验证的架构假设.

优先复用成熟组件, 但不要因为某个框架功能丰富就让其决定我们的核心领域语义.

## 预期结果

希望最终得到:

1. 一份清晰的项目整体架构;
2. 一份经过论证的核心领域模型;
3. Intent / Execution 状态机定义;
4. Outcome 提交协议;
5. Transition History 设计;
6. 分布式执行与恢复协议;
7. Storage Behaviour 与 Ecto 多后端方案;
8. 异步并发与等待关系的架构边界;
9. 关键不变量与 Quint 验证方案;
10. 一套能够指导后续开发的 RFC / SPEC;
11. 按照依赖关系组织的分阶段实现路线.

文档以中文编写, 保留必要的英文技术术语, 适当使用 Mermaid 图表, 不要使用全角符号.

SPEC 应明确可测试的行为与不变量, RFC 应记录设计动机/替代方案/权衡和未解决问题.

## 工作方式

**不要立即编写所有文档, 也不要直接进入代码实现.**

首先:

1. 重新归纳项目的核心需求与非目标.
2. 批判性评估 IEO + 组合状态机 + Transition History 的设计.
3. 判断四张逻辑表是否合理, 并与两张通用状态机表的方案比较.
4. 评估 Ecto + SQLite / PostgreSQL / ETS 的实现边界.
5. 找出当前设计中最关键的并发/一致性与恢复问题.
6. 提出你认为更简洁或更可靠的替代方案.
7. 整理需要由我决定的架构问题, 并解释各选项的后果.

之后与我逐项讨论. 每项关键设计决策确定后, 记录其理由/约束及被否决的替代方案, 再逐步生成 RFC / SPEC.

**最终目标不是构建一个庞大而复杂的通用框架, 而是设计一个核心语义清晰/能够形式化验证/充分利用 Elixir
生态/可以在不同设备运行且具有可靠恢复能力的 Distributed Durable Effect Runtime.**
