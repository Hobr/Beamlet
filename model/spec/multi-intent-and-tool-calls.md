# 多 Intent 并发与 Tool Call 依赖契约

状态: 首版并发组合与调用方使用契约草案. 覆盖多个 Agent 独立创建 Intent, 以及一个 Agent 的一轮 Tool Call
等待多个 Intent 的结果. [组合模型](../quint/beamletMultiIntent.qnt) 完整展开两个 Intent;
[验证记录](../quint/multi-intent-coverage.md) 区分场景、有界采样和实际工程边界.
没有新增 Runtime、Agent SDK 或通用 Workflow 引擎.

## 1. 责任边界

Beamlet 接受独立 Intent, 持久维护各自的定义、尝试、授权、证据与唯一 Outcome.
不同 Intent 可以由同一 Worker 或不同 Worker 推进; 同一 Intent 的安全相关写入经过权威存储串行化.
Worker 的存活和 incarnation 属于整个进程会话, 不是每个 Intent 独立重启的开关.
共享 Worker 崩溃会一起丢失它持有的所有 Intent 的易失许可/报告; 已提交绑定、事实及外部执行继续保留.

Agent/Tool Call 的调用方负责依赖清单、依赖到 Intent 的关联和结果汇总. Beamlet 不恢复 Agent 调用栈,
也不替调用方存储等待集合. 模型中的 `callerRounds` 表示调用方已有的持久存储前提;
`registered` 和 `scopeObservation` 是独立检查见证, 不规定产品 SQL 字段.
如果调用方只在内存保存依赖清单, 崩溃后不能仅靠 Beamlet 自动推断本轮还应等待哪些 Intent.

## 2. 多个 Agent 独立提交

提交身份仍为 `(authority_collection, namespace, submission_key)`, 不自动加入 Agent ID 或 Tool Call ID.
希望独立创建的逻辑操作必须使用不同身份; 两个 Agent 在相同 namespace 使用相同 key、相同定义,
会复用同一个 Intent. 异定义返回冲突, 不覆盖已保存定义. 权限检查独立存在, key 或 Intent ID 不是凭据.

例如两个 Agent 都使用本地 key `1`, 可用不同稳定 namespace 表达两次独立操作. 如果业务希望共享同一次操作,
则可有意使用同一已授权提交身份. 不以收到回复的顺序或 Worker 编号判断某个 Intent 属于哪个依赖.
未指定 key 的两次提交保持独立创建; 对失去响应后的自动恢复, 调用方不能依赖 unkeyed 提交去重.

先持久提交再回复, 回复可能丢失. Agent 重启后用原身份、原定义重投, 得到原 Intent 与已有事实;
若原操作已 Closed, 读取其原 Outcome, 不再次发起外部执行.

## 3. 所有局部身份携带 Intent 作用域

Execution、lease generation、报告 ID 和 Worker 本地的 started 集合均不能仅按局部整数索引. 逻辑身份至少携带对应
collection/Intent, 再按各自协议包含 Execution、Worker/incarnation/generation 或 source_scope/report_id. 不同 Intent
可以拥有相同的局部 Execution/report/token 数值; 正确性不能依赖碰巧没有碰撞.

启动回复、报告和持久回执的可信 Envelope 与接收目标 Intent 必须一致, 然后才解释其局部 token/报告.
Envelope 的 Intent 来源由可信传输/Adapter 与持久绑定确定, 不是任意客户端可改写的路由提示.
回调关联在发起前持久建立, 并在 provider/account scope 内唯一定位 collection/Intent/Execution/Operation.
不能按“当前 Waiting 的执行”猜测关联, 也不能把另一个 Intent 的同编号 Execution 视为匹配.

Intent 幂等上下文跨该 Intent 的尝试保持不变, 不同独立 Intent 的上下文必须分离.
真实 Handler 的外部 key 派生仍须满足 [Handler 契约](handler-recovery-contracts.md) 的账户、协议、输入和窗口条件;
模型的不同整数上下文不证明真实编码没有碰撞.

## 4. 单轮 Tool Call 等待多个 Intent

本文验证一个调用方组合: 等待清单中每个依赖都有已提交终态结果后汇总.
调用方可以另行设计自己的 fail-fast/取消策略, 但不能把它隐含成 Beamlet 的跨 Intent 行为.

1. 调用方在第一次发送前保存本轮稳定身份和完整依赖清单. 每项包含稳定 slot、稳定提交身份和不可变定义.
2. 分别提交; 按原请求身份关联响应中的 Intent. 回复乱序、重投及同一 Intent 被多个 slot 有意复用都不改变清单.
3. 通知只用于唤醒. 对每个已解析依赖调用 `ReadFacts(intent)`; 仅把该 Intent 已提交的唯一 Outcome 放入对应 slot.
4. 所有 slot 都有正确结果时, 调用方持久保存汇总. 汇总包含每个 slot 的 Intent 和完整 Outcome, 不只保存数量.
5. 调用方重启后从原清单重投/查找稳定身份, 重读各 Intent 的结果并重建缓存. 已提交的汇总也可直接复用.

一次报告、一次回调、一个通知或一个外部完成不等于一个依赖已完成. 重复通知/读取不能填充另一个 slot.
同一 Intent 有意占用两个不同 slot 时, 两项都必须明确关联该 Intent; 这与错误地把两份通知当两个依赖不同.
每个 Outcome 不可变, 因而可以分次读取不同 Intent 的终态结果; 不需要对它们做跨 Intent 的瞬时联合快照.
读取 Open 的全部中间状态则没有这种跨 Intent 一致快照保证.

## 5. 失败、取消与 Unknown

| 一个依赖的状态 | 本文验证的汇总行为 | 对其他 Intent 的影响 |
| --- | --- | --- |
| Succeeded | 保存对应 slot 的结果值 | 继续独立推进 |
| Failed | 保存对应 slot 的明确错误, 等待其他依赖 | 不自动取消或回滚其他 Intent |
| Cancelled | 保存对应 slot 的逻辑取消结果 | 不表示外部停止, 不隐含取消其他 Intent |
| Prepared/Pending/Waiting/Unknown/冲突阻塞 | 保持该 slot 未完成 | 已完成依赖的结果保留, 其他 Intent 仍可推进 |
| 存储/传输错误或等待超时 | 恢复读取/重投或由调用方返回自己的等待状态 | 不制造 Failed Outcome |

有一个 Intent Unknown 时, 整轮可能持续等待, 即使其他依赖已经成功. 后续合法证据仍能使该 Intent 终结;
没有足够证据时, 不通过等待预算、消息数或另一个 Intent 的结果推断它失败.
调用方若明确决定取消, 须分别通过各 Intent 的取消权限与原子守卫. 本文不提供全成全败、跨 Intent 回滚、Saga 或组事务.
调用方保存汇总不承诺 Agent 后续 Tool Call 副作用只发生一次; 那需要调用方自己的恢复与幂等协议.

## 6. 存储和外部资源并发

PostgreSQL 可分别保护各 Intent 行; SQLite 可以串行化短写事务, 同时允许事务外的外部执行并发.
独立 Intent 不要求全系统单个 GenServer 串行处理. 声明逻辑并发不等于证明数据库写并行、吞吐量或公平性.
两个 Intent 修改同一外部订单/资源时, 仍由 Operation/Handler/资源协议定义版本竞争、锁、业务去重或冲突处理.
Intent 幂等不自动合并两次独立业务操作. 当前组合模型把两个 Intent 的外部资源事实分开, 不验证共享业务对象竞争.

## 7. 工程验收

真实 Adapter/Agent 集成需补验: 跨 Agent 同/异身份竞争、乱序回复与丢响应重投, 局部 ID 相同的消息错路由,
共享 Worker 重启清空所有局部作用域, 两个回调绑定及签名/account 作用域, 真实 key 编码无碰撞,
调用方在提交后/读到部分结果后/保存汇总前后的崩溃恢复, 以及 PostgreSQL/SQLite 的并发写入.

[Quint 检查](../quint/multi-intent-coverage.md) 验证的是有界参与者、原子存储和可信消息前提下的安全关系;
不证明真实 SQL、认证、provider 幂等、任意数量参与者、最终完成、公平调度或外部 exactly-once.
