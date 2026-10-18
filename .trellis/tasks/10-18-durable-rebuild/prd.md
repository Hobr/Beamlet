# Storage 与 Agent durable 全面改造

## Goal

按已确认的 [目标设计](../../../docs/architecture/agent-operation-persistence.md)完成新 durable 模型的代码交付：正文归 Operation/accepted Result，Agent 以事件和引用编排、按策略构建上下文，通过纯归约恢复。彻底移除旧消息检查点作为权威模型的路径，不要求旧 API/数据格式兼容。

## Background

现有 Storage 的 AgentRecords/fork 读取 checkpoint.messages；OperationRecords 批次预留 accept_seq，Runtime.Persistence.owner 使用预留位置；Agent.Durable.model_persistence 不带 Agent owner；Host、历史和导出仍依赖旧表示。现有分布式证据和停止 provenance 应保留。本任务接续 agent-durable-design 文档任务，不覆盖其未提交文档。

## Requirements

- R1：原始输入/配置/编排归 Agent；LLM/Tool 请求及来源归 Operation；输出归 accepted Result；executor 只拥有执行证据。Agent 持久事件/检查点无正文 transcript 副本。
- R2：连续已提交 Agent 事件与严格版本/引用校验；纯 reducer 重建控制状态；检查点仅加速，缺失或损坏可从有效历史回退。
- R3：确定上下文由固定来源与策略构建，作为不可变模型 Operation 提交；模型/Tool 统一 agent/turn/step 归属，准备与等待状态原子提交，结果消费幂等。
- R4：重构双库格式、codec、事务、历史和读写入口，旧格式明确拒绝，启动不迁移/重建/删除旧数据；运行旧库时给出可操作的安全错误。
- R5：保持本地/分布式与内存/durable 可组合，先记后做、一次 attempt、唯一 accepted Result、未知默认阻塞、paused restore、显式 continue，无自动重发/内存降级。
- R6：fork 使用直接不可变引用闭包，历史/导出固定范围，现有 Server/CLI/Web 交互与展示适配新模型；不新增图 UI。
- R7：真实 SQLite/PostgreSQL、并发/断连/进程与 VM 故障、发布及静态检查取得新证据；旧验收只作回归参考。

## Task Map

| 子任务 | 交付 | 顺序 |
| --- | --- | --- |
| 10-18-durable-storage-core | 新存储格式、事件/内容/事务契约 | A，最先 |
| 10-18-durable-runtime-integration | Runtime 关联、准备/采纳和执行证据 | B，依赖 A |
| 10-18-durable-agent-reducer | Agent reducer、上下文、恢复与消费 | C，依赖 A、B |
| 10-18-durable-reference-delivery | fork、导出、宿主与端到端收口 | D，依赖 A、B、C |

父任务拥有跨子验收和最终审查，不直接替代各子任务实施。子任务中间态不发布；最终才允许将 spec 标为新模型已实现。

## Acceptance Criteria

- [x] AC1（R1）：查询所有正文有唯一业务归属；executor 离线时权威可完整读取 accepted 内容。
- [x] AC2（R2）：完整重放、检查点加后缀、活跃提交投影一致；事件无预留空洞；重放无外部调用。
- [x] AC3（R3）：请求提交后不受策略/配置变化影响；反序完成仍按 ordinal 消费；接受/消费/准备各提交窗口不重复副作用。
- [x] AC4（R4）：双库新格式契约通过；旧库不被自动修改；引用损坏/跨归属/旧 generation 明确拒绝。
- [x] AC5（R5）：named peer 与本地故障切点证明一次执行、未知诚实、零恢复重发，观察 ready 不等于持久准入。
- [x] AC6（R6）：独立 fork 控制与直接内容引用、完整导出、现有交互与 release smoke 通过，继承不计新执行。
- [x] AC7（R7）：全伞编译、格式、ExUnit、显式 distributed、Credo strict、Dialyzer、Sobelow、catalogue drift 和 copied release/e2e 记录实际结果；不可用前提不冒充通过。

## Out of Scope

旧格式迁移/兼容层、删除真实数据库、通用 Workflow/Task/Branch/图引擎、新增图 UI、全部摘要/向量检索策略、自动重试/故障转移、跨物理主机或断电保证、对象存储/GC/全局去重框架。首个上下文策略为普通对话，接口允许后续替换。
