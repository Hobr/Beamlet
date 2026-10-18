# A：重建存储格式、事件事务与内容引用：技术边界

## 契约来源

[父技术设计](../10-18-durable-rebuild/design.md)和[目标设计](../../../docs/architecture/agent-operation-persistence.md)共同约束本任务；目标不是已有 API。无前置实现子任务，先于 B/C/D 执行。

## Owning Paths

apps/beamlet_storage/{lib,priv,test}、README.md。

## 必须实现

1. authority 新格式2、journal 保持适用格式，按 role 核对；旧 authority 不自动迁移/清空，open 不创建或修复。
2. 原始输入独立保存；Operation 保存完整逻辑请求和来源，accepted Result 内容权威侧可读；Agent payload/控制检查点拒绝请求/回复正文副本。
3. 事件类型/版本集中定义，seq 只为已提交事件分配；去掉 accept_seq 预留；Operation 采纳历史归自身 scope，不争用 Agent 事件位置。
4. 原子 prepare_operations 写 Agent 事件与全部 Operation/attempt；consume 只写合法 accepted 引用与去重；checkpoint 增 through_seq/reducer version/摘要，允许无 checkpoint 建立 Agent。
5. 引用验证覆盖同权威、owner/turn、已采纳 digest、版本/代际；保持已有存储准入、错误未知分类、无外部副作用及 artifact 完整性。

## 验证与错误

- 真实 SQLite/PostgreSQL 同一契约通过；并发 seq 连续且无重复，重复命令返回原响应、不同参数冲突。
- 准备/消费事务中途失败全回滚，跨 Agent/turn/伪造摘要/旧 generation 拒绝。
- 缺失或坏 checkpoint 不损害原始事件/正文读取；旧 authority open 安全拒绝且文件内容未被自动改写。
- 更新只验证旧表示的测试为新的业务不变量；保留 codec、锁等待、数据集身份、秘密和大小限制覆盖。

具体签名按父 design 中 expected_position、已提交事件/through_seq、prepared 身份、accepted 引用收敛；拒绝非法内容/引用返回安全错误，缺失依赖 blocked，提交结果未知先按 stable ID 读取。不得用 catch 后成功、扩大 timeout/wire cap、降低 lint 或删除场景断言使测试通过。

## 回退与交接

不运行真实数据破坏操作。仅对隔离新格式数据集验证；跨包中间态明确记录，不发布。交付签名、实际验证结果与未完成集成给后续子任务，涉及用户目标变化回父设计审阅；保持单次执行和旧写隔离。
