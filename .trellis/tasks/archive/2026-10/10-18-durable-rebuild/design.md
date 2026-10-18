# 技术设计与跨子任务契约

依据：[主设计](../../../../../docs/architecture/agent-operation-persistence.md)。本文件将目标映射到实施边界；签名为待实现契约，不能解释为现有 API。

## 1. 内容与控制

保留 agents/events/checkpoints/operations/executions/execution_evidence/commands/artifacts 与 journal_attempts 的职责。允许重构文件和内部 API，不为每个名词建表。新 authority format_version 使用 2，journal 格式不变则保持 1；Dataset 根据 role 验证格式，旧 authority 明确 schema_unsupported。删除旧 authority 迁移与初始化分支，仅保留新格式的显式初始化路径；不自动从 v1 转换，不更改已存在库。具体 SQL/索引在 A 子任务设计细化并以双库验证。

Agent 事件内联原始输入/决定或引用 artifact；其余请求/回复只能引用 Operation/Result。Operation 增加模型/工具角色、step 身份和上下文来源清单，完整逻辑请求固定在 description/payload；accepted Result 可内联或引用同权威 artifact。源码不得通过 PID/journal 地址取回唯一正文。不同请求合法包含重复文本，不追求通用物理去重。

## 2. 事件与事务

建议内部具体入口（命名可在子任务内等价收敛）：
- AgentRecords.accept_input(repo, command, expected_position, input)
- AgentRecords.prepare_operations(repo, expected_position, operations, orchestration)
- AgentRecords.consume_results(repo, expected_position, accepted_refs, join)
- AgentRecords.events(repo, agent_id, after_seq, through_seq, limits)
- AgentRecords.checkpoint(repo, agent_id, through_seq, reducer_version, projection)
- OperationRecords.claim_dispatch / accept_result / record_evidence

expected_position 含 agent_id、lock_version、generation；所有引用/归属/内容摘要在事务中重校验。返回新 version/through_seq、已提交事件、prepared 身份及 command replay 状态。持久消息的公开字段采用字符串键，内部参数遵守现有明确类型约束。不要暴露任意 append 或 SQL 给客户端绕过领域不变量。

Agent seq 只按提交分配：同事务连续追加 N 条后推进 N，不预留 accept_seq。Runtime 采纳记录进入 Operation 自身 scope，Agent 通过明确消费/观察事件引用；采纳不争用 Agent 消费版本。拒绝过期 Agent 控制转换，但迟到真实执行证据仍可保存，不篡改已采纳 Result。跨对象关系由 operation_id/agent_id/turn_id/step_id 与摘要确定，不依赖跨 scope 全序。

准备事务原子写请求/attempt + Agent 编排事件 + version；不会先推进 Agent 再另建请求。消费事务验证 accepted 事实与唯一消费键，只记引用。投影是可重建缓存，不作为附加独立权威。发送、provider、文件 I/O 一律在事务外。

## 3. Reducer、上下文与恢复

新增 Agent 所有的版本化事件 decoder/reducer 与有界历史 loader；Storage 仅校验记录/引用/事务，不运行 prompt 策略。reduce(state,event) 纯函数，不访问 Repo。控制状态含 turn/continuation/input refs/pending/join/order/consumed refs/blocked/config revision，不含持久 messages/assistant 正文。

loader 固定 through_seq，校验连续性、版本、摘要与引用，checkpoint 绑定同位置。坏 checkpoint 丢弃后完整读取，坏事件/正文阻塞。恢复超限返回明确 limit/blocked，不能截断历史；允许后续有界继续加载，不引入后台调度器。

上下文构建器输入控制状态、已加载合法来源、policy/version/预算，输出 request + sources。先实现普通对话策略；摘要/检索不是本次功能。sources 由新 Operation 拥有，Agent 准备事件只引用它。模型/Tool 均走准备与消费，无 owner=nil 的模型捷径。runtime 将凭据临时注入，不影响已固定逻辑请求。

重建 paused 不调用 Handler；inspect 不写修复记录；激活显式增加 generation、退役旧发送者并幂等记录遗留中断。已接受未消费可继续消费，prepared 未 claim 可显式首次派发，send_claimed 未决只核对，不自动重发。显式 evidence resolution 留引用和决定，不改 accepted 结果。

## 4. 分布式与模式边界

保留 Runtime 发现/放置/准入、executor boot、prepared/send_claimed、start_intent/terminal/unknown、receipt、首停止原因与实际终止观察。Agent 只依赖稳定身份和统一 Result，不持有节点报告租期或 Gateway 句柄作为 durable 状态。

本地 durable 同样经过 Gateway/journal。内存模式复用控制和上下文语义但没有持久保证，不为此引入抽象数据库框架。存储失败不得降级。执行端证据与权威可有可靠性副本，不允许 Agent 再复制 transcript。

## 5. 错误、预算与读取

保留 invalid_data/limit/conflict/stale_generation/schema_unsupported/artifact_missing/storage_unavailable/storage_outcome_unknown 与安全 blocked 原因。写结果未知先重读稳定 command/Operation；不自动重试写事务。

沿用已有 5s 存储调用、页大小默认100/最大500/4MiB、Operation 262144/Result1048576 字节等现有边界作为起点，不因内容引用放大 wire cap。新增事件、投影、构建、恢复总预算由 A/C 写成具名配置/常量并验证边界：用现有 1MiB checkpoint、深度32/节点100000等适用 codec 限制，不把消息条数误用为历史记录总长度。加载采用有限分页与受限输出，保持配置/secret 严格分离。

## 6. Fork、历史、导出与产品

同库 fork 在事务内创建新 Agent + 继承清单 + 来源与风险 + 初始控制事件。清单直接指向 immutable 输入/Operation/Result/artifact 闭包，无父历史递归，无源 Operation 重归属；保留引用依赖，默认无 GC。新 Agent paused/await_input，不继承 pending、消费/命令去重、provider session。

History/export 由控制/引用读取构建，固定高水位，显式 performed/inherited、缺失/脱敏；图仅提供可派生因果数据，不实现 UI。现有 Agent display/CLI/Web/Server 调用应适配，不暴露内部内容格式给多处自行解析。只读历史不要求模型、secret 或 executor 可用。

## 7. 过渡与回退

子任务在同一集成工作线顺序实施，A/B 中间态可暂时不兼容旧调用，但不得发布；受影响调用必须在后续子任务修复，不保留双模型。最终全量验收前不得将新目标标为已交付。A 的包内检查不冒充全伞通过。

代码回退只对一次性测试数据集操作；新格式拒绝旧程序/旧库，禁止运行时自动降级或 DROP。用户真实数据处理不在授权范围。现有未提交设计文档归前序任务，提交时明确区分，不顺带打包。
