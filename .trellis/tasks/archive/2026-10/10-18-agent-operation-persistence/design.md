# 持久化任务树设计

状态：planning。仅创建规划；用户尚未授权激活或实施，不运行 `task.py start`，不安装依赖、不修改应用代码。

## 设计依据

- [主设计](../../../docs/architecture/agent-operation-persistence.md)
- [实施与验收计划](../../../docs/architecture/persistence-delivery.md)
- [术语](../../../GLOSSARY.md)

以上文档是契约来源；本文只收敛本任务范围，不另建相互竞争的设计。代码兼容性核对基线为 `a078aa3`，开工前重新核对后续变化。

## 架构与职责

- Authority 只拥有一份业务事实源；Agent/Runtime 共用权威 Repo。Storage 提供具体事务函数，Runtime 管派发/证据/终态，Agent 管上下文/消费/恢复/fork。
- ExecutorJournalRepo 保存 start_intent、停止原因/终止观察和 receipt，不改权威 Result；本地组合角色也走相同协议。
- 使用事务状态 + 不可变历史 + 自足检查点，不重放旧 handler。Result 接受与 Agent 消费各自原子，彼此用稳定身份关联。
- Display/Observation 仅派生当前观察；日志从业务转换写入。存储准入由实际提交保证，不信任注册 ready 或过期 report。
- fork 复制有效上下文到新 Agent；来源字段仅 provenance，不形成父历史加载依赖。

## 分解与接口交接

A 交付 codec/Repo/具体事务与数据契约 → B 持久 Runtime/日志 → C 检查点/paused 恢复 → D 只读历史/导出 → E fork/决定 → F 宿主与运维端到端。

D 只依赖 C，用合法继承数据 fixture 验证来源格式；真实 fork 出现在 E，再由 E/F 验证导出，避免 D/E 循环依赖。F 依赖所有前序验收。任何子任务修改交接契约须先更新主设计与受影响规划，不以增加新实体绕开原子性或安全要求。

## 必须保留的安全边界

prepare/claim/send、本地 start_intent/terminal、终态接受/消费之间的每个窗口都单独测试。send_claimed 后不自动重发；日志 missing/not_found 不证明未执行；deadline/cancel 请求不证明 worker 已停。首个停止原因与真实终态分开记录，正常返回不因取消请求被改写。

旧代写入以版本/代次拒绝，但还须退役本地发送者；该机制不是跨分区 fencing。部署仍要求单 authority 独占数据集。secret/profile/environment 依赖缺失时阻塞，不做替代环境执行。

## 兼容与回退

保持显式临时模式；不能在持久提交失败后悄悄降级。各阶段未完成前不宣称生产可用 durable。可关闭新持久创建停止扩大上线，但已经写入的数据不能让旧内存实现接管；迁移以 expand/兼容读取/一致性备份回退，不直接 DROP 历史表。

## 开工前需锁定的细节

A 锁定 adapter 兼容版本、具体函数/错误及 codec/事务上限；B 锁定证据查询身份与提交队列上限；C 锁定 continuation/secret 迁移接口；D/E 锁定导出/复制上限；F 锁定宿主配置、CI 和运维命令。这些属于各子任务的设计评审，不是已批准安装或实施的动作。
