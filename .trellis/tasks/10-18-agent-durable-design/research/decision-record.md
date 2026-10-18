# 本次决策来源与核对

来源：本会话用户确认，非外部源码核验。用户明确要求仅更新本地设计，后续另建代码任务，项目早期无需旧格式兼容。

最终确认：Agent 不保存聊天 transcript 或重复 LLM/Tool 正文，只拥有原始输入、配置和编排关系。LLM call 是 Operation，确定 prompt 与 schema/模型参数归 Operation，输出以权威 accepted Result 为准，executor final result 是证据。引用可共享正文；分布式可靠性副本不能误删。上下文沿引用生成并固定到下一次 Operation。纯事件归约重建 Agent，检查点仅加速，不重执行副作用。

核对入口：apps/beamlet_agent/lib/beamlet/agent/durable.ex（旧 messages/assistant 检查点）、apps/beamlet_runtime/lib/beamlet/runtime/persistence.ex（Operation 投影）、apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex（accept）、apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex（journal）。这些是现有实现证据，不证明目标已实现。

DeepSeek-Harness 来源仅为用户提供的总结：事件优先、先记后做、提交屏障、显式中断和未知不重试。本次未核验其 repository、版本、SessionHandle 或 flush/fsync 保证。旧 pi/其他框架研究保留在 docs/architecture/research/durable-agent-mechanisms.md，明确区分旧结论与本次目标。
