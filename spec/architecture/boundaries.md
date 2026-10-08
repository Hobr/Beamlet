# 逻辑边界

## 1. 适用范围

定义通用层与领域层的边界及依赖方向。相关契约覆盖计算、存储、能力和应用交互界面。

## 2. 接口签名与职责

| 逻辑模块组 | 接口职责 | 允许依赖 |
| --- | --- | --- |
| Beamlet-core | DefinitionRef、RunRef、Invocation、Reply 与可移植数据契约 | OTP/Elixir |
| Cordex | Scope 描述符、服务选择、提供者代次与资源生命周期 | OTP/Elixir；不包含 Agent 或持久化计算逻辑 |
| Beamlet-effect | 意图规范化、提供者资格检查与单次提供者调用 | Core 与有限的 Cordex 集成 |
| Beamlet-durable | 权威命令、计算宿主、输入调度、执行主体与重复分发协议、控制及归档 | Core、Effect、Cordex 集成与选定存储 |
| Beamlet-lib | Beamlet 公共门面接口与按角色启动 | 通用模块组 |
| Beamlet-agent | Agent 定义，以及 LLM、工具、设置和子 Agent 的门面接口与提供者 | 通用公共契约 |
| 交互界面 | 交互、投影、经过认证的适配器与配置的宿主角色 | Agent 与通用公共控制接口 |

目标调用接口保持精简：

~~~text
Definition.step(state, application_input) -> step_result
CapabilityFacade.call(arguments, reply_key) -> Invocation
Effect.invoke(binding, intent, execution_context) -> observation
Authority.command(domain_ref, envelope) -> result
~~~

这些名称用于表达接口，不要求表中每一行都对应一个 OTP 应用或进程。先采用命名空间组织；仅在实际分布、生命周期或依赖需求要求时拆分应用。

## 3. 契约与数据流

~~~mermaid
flowchart TD
    A["应用状态与 Invocation"] --> H["通用计算宿主"]
    H --> S["权威状态 + 收件箱 + Effect"]
    S --> C["配置的控制器与 Scope 解析"]
    C -->|"条件执行授权"| S
    S -->|"已绑定的 Attempt 授权"| W["Durable 工作进程实例"]
    W --> E["Effect 调用"]
    E --> P["本地能力提供者"]
    P --> W
    W --> S
    S -->|"普通能力 Reply"| H
~~~

Durable 工作进程实例负责执行主体身份、同一 Attempt 的重复分发抑制和观测记录；Effect 负责单次提供者调用。Effect 执行层不导入 Durable，因此不需要引入形成循环依赖的结果接收抽象。纯步骤故障、输入顺序与终态由 Durable 权威命令处理，不移入 Agent 门面或提供者。

基础记录可以包含不透明的应用数据或元数据，但不得定义 model、effort、conversation、tool 或 subagent 字段与分支。这些内容属于应用自行管理的模式中的操作参数和状态。

Agent 定义与门面接口不构造或读取 Effect、Attempt 记录。提供者接收普通参数、稳定请求令牌和本地资源上下文，不接收持久化存储的实现对象。

Cordex 在本地管理运行中的服务。Durable 管理逻辑描述符，不管理服务对象、PID 或连接。Cordis 注册副作用、Ra 调度副作用和 Beamlet 持久化 Effect 是不同概念。

<a id="interface-obligations"></a>

### 已评审补充：接口前提与模块验证义务

Quint 核心的 I1–I4 是接口前提；下列责任属于未来具体模块的故障 / 契约测试。本仓库尚无运行时代码，形式协议检查不证明这些实现前提已满足。

| 前提 | 责任模块 | 运行时发布前必须完成的验证 |
| --- | --- | --- |
| I1：原子、线性化且持久保留的权威接口 | Durable 权威适配器与选定 Ra 实现 | 提交前后崩溃、确认丢失、日志 / 快照恢复、节点及磁盘丢失、法定人数分区；状态 / 输入 / Effect、结果 / 回复不出现部分提交；已确认回执及历史在压缩后保留 |
| I2：验证、授权、修订隔离与幂等命令 | Core 模式、Lib 接入适配器及 Durable 命令处理 | 未授权或畸形载荷拒绝；原键原载荷先查回执；改载荷 key_conflict；过期纪元 / execution_revision、暂停 / 终态及两个控制器竞态；通知与终局回复去重相互独立；同一 Attempt 的确定观测先提交、不同 observation_id 监视器报告后到时仅保留审计，不重新通知 |
| I3：兼容绑定、真实观测与原主体单次进入 | Cordex、Effect、Durable 工作进程及具体提供者 | 调用前后退出、重复分发、实例替换、绑定代次变化、预检拒绝；新实例不能继承授权；稳定令牌与实际去重域 / 保留期；捕获版本与局部 / 逻辑失败分类；超时不证明未执行；确定观测与监视器失联交错按证据含义处理，局部失败仍保留逻辑未决 |
| I4：可移植、兼容的定义、状态与前缀值 | Core 数据模式与 Durable 归档 / 编解码边界 | 有界 ETF 解码、尾随 / 压缩 / 运行时句柄拒绝、模式及版本兼容、持有提案捕获不变；源前缀完整性、分支新队列与只读历史；资源缺失不得激活 |

恢复职责由[权威层的已提交事实表](./authority-and-recovery.md#3-契约)交接。计算宿主负责队首与纯步骤；控制器负责当前新授权路径；原工作进程负责一次进入与原观测重报；权威层负责条件归约、唯一回复与持久待处理工作。任何模块都不得把其他模块的本地缓存或存活状态视为新的权限来源。

## 4. 验证与错误矩阵

| 违规情况 | 边界必须采取的行为 |
| --- | --- |
| Agent 定义导入 Effect / Durable 记录 | 依赖或契约检查失败 |
| 外部输入提供任意模块、函数或更新回调 | 在已注册代码 / 应用边界拒绝 |
| 持久化状态包含运行时句柄或闭包 | 在确认前返回 invalid_data |
| Effect 执行器导入 Durable 以记录结果 | 将结果记录移至 Durable 工作进程 |
| 缺少已注册且兼容的定义或提供者 | 阻止执行，明确返回兼容性或资源结果 |
| 新建实体进程或应用仅用于组织代码 | 使用模块，除非运行时职责确实需要进程或应用 |

## 5. 正例、基础场景与反例

正例：同一运行时驱动 Agent 和对象处理计算定义，两者使用不同的操作契约。

基础场景：一个节点承担全部角色，仍采用相同的逻辑接口。

反例：Durable 为 llm.chat 或子 Agent 创建实现专用处理；或者门面接口在 Definition.step 内执行 HTTP 请求。

## 6. 必需测试

<a id="s1"></a>

### S1 — 通用层与 Agent 边界

依赖与 API 断言必须证明：Agent 状态转换仅依赖可移植状态、Invocation 和 Reply。通用状态机不得依据 Agent 操作名称分支。跟踪 UI 输入经过权威层、解析、工作进程，直至已提交 Reply 的完整路径。

<a id="s6"></a>

### S6 — 非 Agent 场景的契约一致性

使用相同的状态、Effect、执行授权、结果和恢复契约，运行对象读取、摘要计算、内容寻址写入的计算定义。在节点间移动计算宿主，断言不需要任何 Agent 服务或类型。

## 7. 错误与正确做法

~~~text
错误：Definition.step -> LLM HTTP -> 随后写入状态。
正确：Definition.step -> Invocation -> 权威层原子提交 -> 提供者执行 -> 已提交 Reply。

错误：Effect.invoke -> Durable.record_outcome。
正确：Durable 工作进程 -> Effect.invoke -> Durable 权威层结果命令。
~~~
