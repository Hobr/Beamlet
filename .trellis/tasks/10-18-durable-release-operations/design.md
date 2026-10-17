# 持久化发布与运维验收设计

状态：planning。仅创建规划；用户尚未授权激活或实施，不运行 `task.py start`，不安装依赖、不修改应用代码。

## 设计依据

- [主设计](../../../docs/architecture/agent-operation-persistence.md)
- [实施与验收计划](../../../docs/architecture/persistence-delivery.md)
- [术语](../../../GLOSSARY.md)

以上文档是契约来源；本文只收敛本任务范围，不另建相互竞争的设计。代码兼容性核对基线为 `a078aa3`，开工前重新核对后续变化。

## 归属与方案

主设计第 3.1、10–12 节及交付计划 F。Node 保持受宿主显式监督的组合库，daemon/CLI 负责启动配置与运维入口；不引入宿主隐式自启数据库。authority/journal 分离迁移，storage schema 与业务版本兼容检查。若展示存储状态，使用单独 durable 准入字段及安全原因，不改 Node services ready 的注册语义，也不把 observation 当授权。

## Interface 与交接

具体配置键、迁移命令、释放包依赖、存储目录/权限、大小/时间上限在本阶段设计评审中锁定；不预先假设根 mix.exs 已包含 Ecto、SQL Sandbox 或双库 CI。备份只用数据库一致性流程，不直接复制运行中的单个 SQLite db 文件。

## 依赖与兼容

先决：[持久数据契约与存储基础](../10-18-durable-storage/prd.md)、[Runtime 权威记录与执行日志](../10-18-durable-runtime/prd.md)、[Agent 历史、检查点与暂停恢复](../10-18-durable-agent/prd.md)、[持久历史查询与轨迹导出](../10-18-durable-history-export/prd.md)、[安全 fork 与恢复决定](../10-18-durable-fork-resolution/prd.md) 验收通过后才能实施。

遵循[父设计](../10-18-agent-operation-persistence/design.md)的跨阶段契约、单权威部署与回退限制。具体源码位置开工前重新核对；这里只记录 seam 和职责，不以基线函数签名冻结未来实现细节。现有临时模式不能被持久失败静默接管。

## 验证边界

本阶段以自身 PRD 验收及交付计划对应阶段为准；保存实际测试命令、适配器/SQLite 引擎版本、故障切点和证据路径。未执行的故障模型必须明示，不能把相邻阶段或内存测试当作本阶段证据。
