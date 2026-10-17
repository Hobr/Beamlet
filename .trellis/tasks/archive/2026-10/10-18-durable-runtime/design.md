# Runtime 权威记录与执行日志设计

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施：每阶段完成并提交后自动进入下一阶段；B–F 不再逐段请求确认。

## 设计依据

- [主设计](../../../docs/architecture/agent-operation-persistence.md)
- [实施与验收计划](../../../docs/architecture/persistence-delivery.md)
- [术语](../../../GLOSSARY.md)

以上文档是契约来源；本文只收敛本任务范围，不另建相互竞争的设计。代码兼容性核对基线为 `a078aa3`，开工前重新核对后续变化。

## 归属与方案

主设计第 5、6.2–6.4、7.2、11–12 节及交付计划 B。Runtime 拥有 Operation/Execution 转换；Storage 只做具体数据事务。按 prepared → CAS send_claimed → 单次发送，admit 带稳定 authority/operation/attempt/executor 身份及 digest。Gateway 本地串行准入先落 start_intent，再启动临时 worker；规范化终态/停止观察/receipt 同事务落盘。重启遗留 start_intent 变 unknown，不重建 worker。权威 evidence、accepted_result 和 ACK 明确分离。

## Interface 与交接

沿用 submit/status/cancel，增加持久 locator 的状态查询；证据核对为 Runtime 私有协作函数，不建 Reconciler 服务。PID/boot 运行句柄不落库；已记录的停止原因是数据，不恢复旧 timer。

## 依赖与兼容

先决：[持久数据契约与存储基础](../10-18-durable-storage/prd.md) 验收通过后才能实施。

遵循[父设计](../10-18-agent-operation-persistence/design.md)的跨阶段契约、单权威部署与回退限制。具体源码位置开工前重新核对；这里只记录 seam 和职责，不以基线函数签名冻结未来实现细节。现有临时模式不能被持久失败静默接管。

## 验证边界

本阶段以自身 PRD 验收及交付计划对应阶段为准；保存实际测试命令、适配器/SQLite 引擎版本、故障切点和证据路径。未执行的故障模型必须明示，不能把相邻阶段或内存测试当作本阶段证据。
