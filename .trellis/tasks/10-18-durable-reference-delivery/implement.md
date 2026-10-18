# D：引用式 fork、历史导出与产品验收：执行清单

## 前置门禁

必须等待 A、B、C 的契约与局部验收通过；最后交付父任务 AC1–AC7。 在规划最终审阅获批且 task.py start 本子任务之后实施。先加载 owning spec、父 design/research；不要在父任务路径派发全部实现。

## 步骤

- [x] 适配 fork 引用闭包和历史/导出，补充缺引用/源退役/风险 gate 测试。
- [x] 接入宿主与既有交互、部署示例；确认旧表示不再作为隐式备用路径。
- [x] 执行父全范围门禁与故障矩阵，更新实现事实文档，父 AC 全部有证据后才建议交付。
- [x] 对照 PRD 每项 AC 验证并记录证据；更新实现契约说明及受影响 spec。
- [x] 独立 check，最终影响范围通过后准备提交计划，不推送。

## 验证命令

执行父 implement 全部最终门禁，包括真实 PG 全伞、--only distributed、strict Credo/Dialyzer/Sobelow、durable-e2e、copied release。从 umbrella root 执行，详见[父执行计划](../10-18-durable-rebuild/implement.md)。先读取实际脚本前提；真实 PG 与 named peer 没执行不能算通过，LSP 超时不算 clean。双库 fixture 只操作自己的隔离测试库。

## 回退点

不自动打开/改写旧库，不保留旧消息模型作为 fallback。各事务/派发边界可控故障注入，保持已有凭据、大小、停止 provenance、capacity/helper 清理约束。阶段结束记录尚待后续子任务适配的调用，不能隐藏失败。
