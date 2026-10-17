# Runtime 权威记录与执行日志执行计划

状态：planning。仅创建规划；用户尚未授权激活或实施，不运行 `task.py start`，不安装依赖、不修改应用代码。

## 开工门

- [ ] 用户评审并批准本子任务；先决：[持久数据契约与存储基础](../10-18-durable-storage/prd.md) 验收通过后才能实施。
- [ ] 重新核对主设计、父设计和当前代码；记录本阶段具体接口、默认资源上限及验收命令。
- [ ] 验证上下文 manifests，随后才可激活本子任务。父子链接本身不满足依赖或授权门。

## 实施顺序

- [ ] 确认 A 存储契约已验收，核对 Coordinator dispatch/accept、Gateway admission/stop/release 与 NodeEndpoint 转发顺序。
- [ ] 实现权威 prepare/claim/accept、journal start_intent/receipt、稳定身份查询及 ACK；网络消息不放进 DB 事务。
- [ ] 加入提交前后、外部改变后和消息丢失的 barrier/VM 故障测试，单列停止分类回归。
- [ ] 验证日志丢失/旧备份暂停准入、有限队列/超时与容量释放；更新 Runtime 契约和实际证据。

## 验证与收尾

- [ ] 逐项取得自身 PRD 验收及[主交付计划](../../../docs/architecture/persistence-delivery.md)阶段 B 的真实证据；纯存储阶段不声称已验证业务恢复。
- [ ] 按 backend/quality-guidelines 选择受影响代码的格式、warning-fatal compile、针对性/完整 ExUnit、显式 named distributed suite、静态检查和必要 release 验证，记录环境限制；涉及两库契约的用例必须两库运行。
- [ ] 更新已实现的 spec、接口和操作说明，不把下游规划写成现状；将证据及交接契约交给父任务和下游评审。
- [ ] 依父设计暂停点检查范围，阶段回退只关闭新持久入口/保持兼容读，不删除已提交事实或回退成内存权威。
