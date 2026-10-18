# A：重建存储格式、事件事务与内容引用

## Goal

交付已确认 durable 设计的本阶段代码，使 Storage schema、migration/format、Codec/JSON、AgentRecords/OperationRecords/History、事务及引用完整性。

## Dependencies

无前置实现子任务，先于 B/C/D 执行。 父任务为 [durable-rebuild](../10-18-durable-rebuild/prd.md)；子任务未完成不等于产品可发布。

## Requirements

- R1：authority 新格式2、journal 保持适用格式，按 role 核对；旧 authority 不自动迁移/清空，open 不创建或修复。
- R2：原始输入独立保存；Operation 保存完整逻辑请求和来源，accepted Result 内容权威侧可读；Agent payload/控制检查点拒绝请求/回复正文副本。
- R3：事件类型/版本集中定义，seq 只为已提交事件分配；去掉 accept_seq 预留；Operation 采纳历史归自身 scope，不争用 Agent 事件位置。
- R4：原子 prepare_operations 写 Agent 事件与全部 Operation/attempt；consume 只写合法 accepted 引用与去重；checkpoint 增 through_seq/reducer version/摘要，允许无 checkpoint 建立 Agent。
- R5：引用验证覆盖同权威、owner/turn、已采纳 digest、版本/代际；保持已有存储准入、错误未知分类、无外部副作用及 artifact 完整性。

## Acceptance Criteria

- [x] AC1：真实 SQLite/PostgreSQL 同一契约通过；并发 seq 连续且无重复，重复命令返回原响应、不同参数冲突。
- [x] AC2：准备/消费事务中途失败全回滚，跨 Agent/turn/伪造摘要/旧 generation 拒绝。
- [x] AC3：缺失或坏 checkpoint 不损害原始事件/正文读取；旧 authority open 安全拒绝且文件内容未被自动改写。
- [x] AC4：更新只验证旧表示的测试为新的业务不变量；保留 codec、锁等待、数据集身份、秘密和大小限制覆盖。

## Out of Scope

旧格式/API 兼容、删除已有数据、通用调度/Workflow/Branch/GC、自动重试/切主、图 UI、全部摘要/检索策略。只做本阶段及必要适配，不顺带修改前序设计文档的未提交内容。API/schema 允许破坏性变更，但不能降低 accepted/unknown/不重放保证。
