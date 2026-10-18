# C：Agent 事件归约、上下文与暂停恢复：执行清单

## 前置门禁

必须等待 A、B 验收；D 依赖本任务。 在规划最终审阅获批且 task.py start 本子任务之后实施。先加载 owning spec、父 design/research；不要在父任务路径派发全部实现。

## 步骤

- [x] 集中定义事件 decoder 与 reducer，先用真实历史测试投影等价和错误边界。
- [x] 实现有界 loader/缓存恢复与普通上下文策略，接入模型/Tool 原子准备和引用消费。
- [x] 替换 Server 的旧 transcript 权威路径，适配内存/展示/helpers，完成各恢复位置和故障窗口测试。
- [x] 对照 PRD 每项 AC 验证并记录证据；更新实现契约说明及受影响 spec。
- [x] 独立 check，最终影响范围通过后准备提交计划，不推送。

## 验证命令

mix test apps/beamlet_agent/test apps/beamlet_node/test apps/beamlet_harness/test；mix compile --warnings-as-errors；mix credo --strict --all；named Agent/Node 按父命令执行。从 umbrella root 执行，详见[父执行计划](../10-18-durable-rebuild/implement.md)。先读取实际脚本前提；真实 PG 与 named peer 没执行不能算通过，LSP 超时不算 clean。双库 fixture 只操作自己的隔离测试库。

## 回退点

不自动打开/改写旧库，不保留旧消息模型作为 fallback。各事务/派发边界可控故障注入，保持已有凭据、大小、停止 provenance、capacity/helper 清理约束。阶段结束记录尚待后续子任务适配的调用，不能隐藏失败。
