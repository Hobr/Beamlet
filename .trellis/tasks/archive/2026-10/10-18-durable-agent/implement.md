# Agent 历史、检查点与暂停恢复执行计划

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施；先决阶段 A/B 已验收并提交（3aefa85、11577fb）。

## 开工门

- [x] 用户批准连续实施；先决：[Runtime 权威记录与执行日志](../10-18-durable-runtime/prd.md) 验收通过后才能实施。
- [x] 重新核对主设计、父设计和当前代码；记录本阶段具体接口、默认资源上限及验收命令。
- [x] 验证上下文 manifests，随后才可激活本子任务。父子链接本身不满足依赖或授权门。

## 实施顺序

- [x] 确认 B 已验收；盘点完整 Agent 业务转换、OperationOwner 退役和所有 continuation，明确提交后的发布顺序。
- [x] 实现持久定义/输入、完整请求回复、原子批次、去重消费与自足检查点。
- [x] 实现恢复加载、版本/代次隔离、paused 实例和显式 continue/blocker；不恢复旧 PID/timer/provider session。
- [x] 用 fake provider/Tool 覆盖全部继续位置、反序结果、并发恢复、投影丢失和凭据边界；更新 Agent 契约。

## 验证与收尾

- [x] 逐项取得自身 PRD 验收及[主交付计划](../../../docs/architecture/persistence-delivery.md)阶段 C 的真实证据；纯存储阶段不声称已验证业务恢复。
- [x] 按 backend/quality-guidelines 选择受影响代码的格式、warning-fatal compile、针对性/完整 ExUnit、显式 named distributed suite、静态检查和必要 release 验证，记录环境限制；涉及两库契约的用例必须两库运行。
- [x] 更新已实现的 spec、接口和操作说明，不把下游规划写成现状；将证据及交接契约交给父任务和下游评审。
- [x] 依父设计暂停点检查范围，阶段回退只关闭新持久入口/保持兼容读，不删除已提交事实或回退成内存权威。
