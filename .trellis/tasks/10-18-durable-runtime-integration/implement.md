# B：Runtime 持久操作与并发结果采纳：执行清单

## 前置门禁

必须等待 A 的新格式与事务契约验收；C 依赖本任务。 在规划最终审阅获批且 task.py start 本子任务之后实施。先加载 owning spec、父 design/research；不要在父任务路径派发全部实现。

## 步骤

- [x] 读取 A 交付契约，替换 owner/persistence/prepared 结构，不在 Agent 侧另造提交逻辑。
- [x] 改造 prepare/claim/accept 与证据关联，保留 Worker 生命周期和清理。
- [x] barrier 故障注入与调用计数、named peer 和现有停止/容量回归，记录供 C 接线的签名。
- [x] 对照 PRD 每项 AC 验证并记录证据；更新实现契约说明及受影响 spec。
- [x] 独立 check，最终影响范围通过后准备提交计划，不推送。

## 验证命令

mix test apps/beamlet_runtime/test apps/beamlet_actions/test；named distributed 按父 implement 命令显式运行；mix compile --warnings-as-errors；mix credo --strict --all。从 umbrella root 执行，详见[父执行计划](../10-18-durable-rebuild/implement.md)。先读取实际脚本前提；真实 PG 与 named peer 没执行不能算通过，LSP 超时不算 clean。双库 fixture 只操作自己的隔离测试库。

## 回退点

不自动打开/改写旧库，不保留旧消息模型作为 fallback。各事务/派发边界可控故障注入，保持已有凭据、大小、停止 provenance、capacity/helper 清理约束。阶段结束记录尚待后续子任务适配的调用，不能隐藏失败。
