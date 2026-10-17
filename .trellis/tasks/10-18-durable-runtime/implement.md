# Runtime 权威记录与执行日志执行计划

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施：每阶段完成并提交后自动进入下一阶段；B–F 不再逐段请求确认。

## 开工门

- [x] 用户于 2026-10-18 批准连续实施；先决 [持久数据契约与存储基础](../10-18-durable-storage/prd.md) 已验收（commit 3aefa85）。
- [x] 已核对主设计/父设计与当前代码（storage 记录门面 + Coordinator/Gateway 现状）；本阶段接口与上限见 design.md。
- [x] implement/check manifests 各 11 条通过校验；已激活本子任务（in_progress）。

## 实施顺序

- [x] 确认 A 存储契约已验收（3aefa85），核对 Coordinator dispatch/accept、Gateway admission/stop/release 与 NodeEndpoint 转发顺序。
- [x] 实现权威 prepare/claim/accept、journal start_intent/receipt、稳定身份查询；网络消息不放进 DB 事务。ACK 由 receipts 幂等接收承担。
- [x] 加入提交前/运行中/终态写入失败的测试（含 post-run 写入失败→uncertain、同 boot 网关重启→unknown），停止分类回归在临时与持久模式均通过。
- [x] 验证日志不可写时零启动与容量释放、重启不恢复容量；更新 operation-runtime 契约与 runtime-evidence。

## 验证与收尾

- [x] 逐项取得自身 PRD 验收及[主交付计划](../../../docs/architecture/persistence-delivery.md)阶段 B 的真实证据；纯存储阶段不声称已验证业务恢复。
- [x] 按 backend/quality-guidelines 选择受影响代码的格式、warning-fatal compile、针对性/完整 ExUnit、显式 named distributed suite、静态检查和必要 release 验证，记录环境限制；涉及两库契约的用例必须两库运行。
- [x] 更新已实现的 spec、接口和操作说明，不把下游规划写成现状；将证据及交接契约交给父任务和下游评审。
- [x] 依父设计暂停点检查范围，阶段回退只关闭新持久入口/保持兼容读，不删除已提交事实或回退成内存权威。
