# Agent 历史、检查点与暂停恢复设计

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施；先决阶段 A/B 已验收并提交（3aefa85、11577fb）。

## 设计依据

- [主设计](../../../../../docs/architecture/agent-operation-persistence.md)
- [实施与验收计划](../../../../../docs/architecture/persistence-delivery.md)
- [术语](../../../../../GLOSSARY.md)

以上文档是契约来源；本文只收敛本任务范围，不另建相互竞争的设计。代码兼容性核对基线为 `a078aa3`，开工前重新核对后续变化。

## 归属与方案

主设计第 3.3、4、6.1、6.4、7、10 节及交付计划 C。在 Agent.Server complete/complete_tool/batch 等业务转换接入事务，而非 publish/publish_activity 订阅。checkpoint 引用不可变消息/artifact 并保存 pending、顺序、消费和明确 continuation。模型回复落盘后可重做纯验证，不重新请求模型。Agent/Runtime 共用权威 Repo，终态接受和 Agent 消费是两个独立原子事务。

## Interface 与交接

沿用 Agent.start/input；新增 restore(locator, expected_version, command_id)、continue(ref, expected_version, decisions, command_id) 的收敛入口。恢复说明为普通数据，不是新持久实体。秘密引用、格式版本、资源上限及临时 API 兼容在开工前确定。

## 依赖与兼容

先决：[Runtime 权威记录与执行日志](../10-18-durable-runtime/prd.md) 验收通过后才能实施。

遵循[父设计](../../../10-18-agent-operation-persistence/design.md)的跨阶段契约、单权威部署与回退限制。具体源码位置开工前重新核对；这里只记录 seam 和职责，不以基线函数签名冻结未来实现细节。现有临时模式不能被持久失败静默接管。

## 验证边界

本阶段以自身 PRD 验收及交付计划对应阶段为准；保存实际测试命令、适配器/SQLite 引擎版本、故障切点和证据路径。未执行的故障模型必须明示，不能把相邻阶段或内存测试当作本阶段证据。
