# A：重建存储格式、事件事务与内容引用：执行清单

## 前置门禁

无前置实现子任务，先于 B/C/D 执行。 在规划最终审阅获批且 task.py start 本子任务之后实施。先加载 owning spec、父 design/research；不要在父任务路径派发全部实现。

## 步骤

- [x] 细化 SQL/事件/入口参数并对照父 design 的 expected_position/返回契约，先建立新双库测试。
- [x] 实现 role 格式校验、schema/codec/引用与事务，删除旧消息检查点必需校验和预留槽位。
- [x] 并发/失败/未知提交测试，形成 A 的接口和实际证据供 B/C 消费；不声明上层已适配。
- [x] 对照 PRD 每项 AC 验证并记录证据；更新实现契约说明及受影响 spec。
- [x] 独立 check，最终影响范围通过后准备提交计划，不推送。

## 验证命令

mix test apps/beamlet_storage/test；mix format --check-formatted；mix compile --warnings-as-errors（若旧调用接口尚待 B/C 更新，记录具体中间断点）；mix credo --strict --all。从 umbrella root 执行，详见[父执行计划](../10-18-durable-rebuild/implement.md)。先读取实际脚本前提；真实 PG 与 named peer 没执行不能算通过，LSP 超时不算 clean。双库 fixture 只操作自己的隔离测试库。

## 回退点

不自动打开/改写旧库，不保留旧消息模型作为 fallback。各事务/派发边界可控故障注入，保持已有凭据、大小、停止 provenance、capacity/helper 清理约束。阶段结束记录尚待后续子任务适配的调用，不能隐藏失败。
