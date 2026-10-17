# 安全 fork 与恢复决定设计

状态：planning。仅创建规划；用户尚未授权激活或实施，不运行 `task.py start`，不安装依赖、不修改应用代码。

## 设计依据

- [主设计](../../../docs/architecture/agent-operation-persistence.md)
- [实施与验收计划](../../../docs/architecture/persistence-delivery.md)
- [术语](../../../GLOSSARY.md)

以上文档是契约来源；本文只收敛本任务范围，不另建相互竞争的设计。代码兼容性核对基线为 `a078aa3`，开工前重新核对后续变化。

## 归属与方案

主设计第 6.4、9–10 节及交付计划 E。不建 Branch 表/active branch/父前缀解析。原子事务生成新 Agent、继承消息新 ID/来源映射、初始 checkpoint 和 command 响应；artifact 同库共享。forked_from_* 只为 provenance。回撤源先冻结并退役本地发送者，再请求取消/查询；远端停止不由本地 DOWN 推断。新实例从 await_input 开始，不复制源 continuation。

## Interface 与交接

Agent.fork(locator, checkpoint_id, expected_version, command_id) 返回新 locator；恢复决定复用 continue，不建独立 Resolver。retry_of 只关联显式新 Operation，不让原 attempt 再执行。配置/secret 重新解析，provider session 和展示身份重新建立。

## 依赖与兼容

先决：[Agent 历史、检查点与暂停恢复](../10-18-durable-agent/prd.md)、[持久历史查询与轨迹导出](../10-18-durable-history-export/prd.md) 验收通过后才能实施。

遵循[父设计](../10-18-agent-operation-persistence/design.md)的跨阶段契约、单权威部署与回退限制。具体源码位置开工前重新核对；这里只记录 seam 和职责，不以基线函数签名冻结未来实现细节。现有临时模式不能被持久失败静默接管。

## 验证边界

本阶段以自身 PRD 验收及交付计划对应阶段为准；保存实际测试命令、适配器/SQLite 引擎版本、故障切点和证据路径。未执行的故障模型必须明示，不能把相邻阶段或内存测试当作本阶段证据。
