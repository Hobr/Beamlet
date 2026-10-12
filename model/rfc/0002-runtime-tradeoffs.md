# RFC 0002: 方案对照与恢复边界

状态: 对既有决策的研究依据与替代方案评估, 不选择新的项目依赖. 产品边界仍以 [RFC 0001](0001-core-boundaries.md) 和
[首版范围](../spec/first-release-scope.md) 为准. 外部机制来自一手资料; 对 Beamlet 的取舍是本项目判断,
不作为外部项目结论. 资料为滚动文档, 正式选型必须锁定项目/SDK/驱动版本并验证实际行为.

## 1. 恢复什么, 比采用什么框架更重要

Beamlet 当前恢复独立 Effect 的事实和权威结果, 由调用方恢复计算上下文.
另一种路线是记录计算的执行历史, 在故障后重放程序以恢复控制流. 两者都可以复用已保存结果,
但控制流重放还需要处理非确定性, 代码兼容, 历史增长和等待原语.

| 方案 | 一手资料描述的机制 | Beamlet 可以借鉴 | 不应默认继承 |
| --- | --- | --- | --- |
| Temporal | Workflow 根据 Event History 重放, 校验生成的 Commands; 外部操作放入 Activity | 逻辑操作与尝试分开, 已记录结果复用, 稳定幂等键 | 完整 Workflow 控制流重放及其确定性/历史兼容义务 |
| Restate | Handler 使用 execution journal 恢复; 非确定性操作经 `ctx.run` 保存结果 | 持久结果, 非确定性边界, 跨尝试稳定身份 | 外部 HTTP/DB 无条件只执行一次, 或自动恢复 Beamlet 的调用方栈 |
| Elixir Skuld 候选 | EffectLogger 保存 JSON log; cold resume 重放以重建 closure/变量绑定 | 操作描述与 Handler 分离, 显式挂起/恢复材料 | 仅凭序列化便证明 crash-consistency, 分布式授权或外部幂等 |
| Beamlet | IEO, Report, 持久授权及原子接受; 调用方从事实重建业务进度 | 优先保持小型执行协议和可解释不确定性 | 隐式持久依赖图, 任意控制流恢复或外部 exactly-once |

Temporal 官方说明 Workflow 通过 [replay](https://docs.temporal.io/workflow-execution#replays) 恢复,
并要求 [确定性与代码兼容](https://docs.temporal.io/workflow-definition#deterministic-constraints).
已完成并记录的 Activity 不随 replay 再执行, 但外部调用完成而未上报时仍可能 retry;
[Activity 文档](https://docs.temporal.io/activity-definition#idempotency) 明确建议幂等, 去重由目标服务执行.
因此这里复用的是操作/尝试/结果分离和恢复机制, 不是照搬所有超时重试策略.

Restate 的 [durable steps](https://docs.restate.dev/develop/ts/durable-steps) 说明 `ctx.run` journal 与重试边界,
并提供确定性时间/UUID. [外部数据库指南](https://docs.restate.dev/guides/databases) 展示条件版本更新和去重 token
与业务修改同事务提交. 这种外部保证仍有作用域, 保留期与原子性前提; journal 不能撤销已经发出的外部请求.
Restate 的 [服务语义](https://docs.restate.dev/concepts/services) 中 Workflow invocation 的 exactly-once 范围,
不能泛化为每个外部请求物理执行一次.

`prompt.md` 未提供 Skuld 地址. 与 Elixir/effects 相符的候选是
[mccraigmccraig/skuld](https://github.com/mccraigmccraig/skuld). 其
[durable package](https://raw.githubusercontent.com/mccraigmccraig/skuld/main/apps/skuld_durable/README.md) 和
[durable computation recipe](https://raw.githubusercontent.com/mccraigmccraig/skuld/main/apps/skuld/docs/recipes/durable-computation.md)
明确区分 cold replay 与内存 hot resume, 示例由调用方保存 log. 该机制说明计算恢复的便利性, 不证明外部调用与 log
落盘原子化. 本次未审计其生产故障协议或成熟度. 另有 [Factual/skuld](https://github.com/Factual/skuld) 同名 Clojure task
queue, 不能混用它与 Elixir 项目的证据. 正式引用 Skuld 作为依赖前须确认目标项目和版本.

## 2. 理论与工程机制的区别

[Plotkin / Pretnar, Handling Algebraic Effects](https://arxiv.org/abs/1312.1399) 给出 operations 与 handlers 的计算语义.
操作与解释分离值得借鉴, 但它不直接提供数据库持久性, 权威提交或安全重试协议. Beamlet 的 Effect 是持久领域数据,
当前不是一个语言级 algebraic-effects calculus, 不需要为此引入新 DSL 或 continuation 序列化.

OTP 是可复用的进程基础设施: [监督树](https://www.erlang.org/doc/system/sup_princ.html) 按策略重启子进程,
[Distributed Erlang](https://www.erlang.org/doc/system/distributed.html) 提供节点连接, remote spawn 和监控.
这些机制帮助组织 Actor/消息处理, 但进程重启不恢复原内存, 断连/nodedown 不证明旧节点永远停止或外部操作未发生.
持久身份, 事实恢复和数据库并发边界仍由 Beamlet 协议负责; 不需要把进程地址当成 Intent 或授权身份.

[Ecto.Multi](https://hexdocs.pm/ecto/Ecto.Multi.html) 组合一个数据库事务内的 Repo 操作, 也允许 `run` 执行任意函数.
SQL rollback 不能自动撤销函数已产生的文件/HTTP 副作用. 因此可用 Multi 或普通 Repo 事务组织领域写入,
但 Handler, 网络和回调发送保持在事务外; Ecto 不替代领域守卫或驱动隔离验证.

[Hewitt / Bishop / Steiger 的 ACTOR 原论文](https://www.ijcai.org/Proceedings/73/Papers/027B.pdf)
从消息交互描述行为与并行组织. 这启发角色隔离和显式协议, 不替代 Beamlet 所需的持久身份与权威并发约束;
Actor/GenServer 不是必须与一个 Intent 一一对应的持久实体.

[Fowler 的 Event Sourcing 模式草稿](https://martinfowler.com/eaaDev/EventSourcing.html) 区分保留历史与由事件驱动变化,
并讨论完整重建, 重放时的外部更新和历史查询响应. Beamlet 只要求当前事实与重要审计同提交,
不要求 History 完整描述所有修改并可重放重建. 若未来改为事件源, 还须定义覆盖范围, 版本解释和禁止重放副作用的边界.

[Quint 官方说明](https://raw.githubusercontent.com/informalsystems/quint/main/quint/README.md)
明确基于 TLA, 支持非确定性状态转换, 类型检查, 模拟与 Apalache 验证. 本项目用显式命令和交错描述组合状态机,
而不是把 Intent/Execution 父子归属等同于进程嵌套或强制共享状态阶段.
Quint 中的原子转换是本项目选择的存储抽象, 不是 SQL 实现证据.
当前实际执行的是场景, mutation 与有限模拟, 未运行 Apalache 符号验证, 更不构成无界穷尽证明;
调度公平性和最终完成还需要额外假设,
不从工具能力, 进程监督或采样无反例自动推导 Liveness.

## 3. 数据与状态表达的替代方案

| 问题 | 可选方案 | 当前取舍及代价 |
| --- | --- | --- |
| 状态机表达 | 通用 `transition` 引擎 vs 明确领域命令 | 明确 IEO/授权/报告/终结守卫, 纯规则可测; 不为减少函数数而隐藏领域资格 |
| 存储实体 | 四类 IEO/transition vs 五类 IEO/report/history vs 两张通用状态机表 | 独立 Report 承载多份, 迟到及矛盾证据; History 解释处理; 增加逻辑实体但避免覆盖 result |
| 恢复来源 | 当前状态与证据 vs 完整 Event Sourcing | 当前事实权威, History 审计; 减少重放依赖, 代价是必须严格验证同事务一致性 |
| 唤醒与派发 | 持久扫描 vs 强制 Outbox | 首版扫描补偿丢唤醒, 少一套发布状态; 不提供逐历史事件的可靠订阅 |
| Authority | 单进程写者 vs 同库多 Coordinator vs 多份独立库合并 | 同库原子命令, 避免进程成为唯一保证; 权威库不可用时牺牲提交可用性, 不做分区双写 |
| 重复识别 | 输入 hash vs 显式稳定身份 | namespace/key 区分业务同一性, 代价是调用方必须保存身份; hash 仅辅助内容比较 |
| 长等待 | 常驻 Worker vs 持久关联与回调/查询 | 可释放进程, 代价是 provider/Adapter 必须提供可恢复材料和可信完成入口 |
| 版本管理 | 最新实现/Schema Hash vs 版本化 Operation 与历史快照 | 不兼容语义换 Identity, 保留原协议; 仍需 codec/schema/消息各自的兼容演进 |
| ETS | 第三种权威 Adapter vs 非权威缓存 | 首版只支持两类 SQL, 测试用快照/真实后端; 不承诺易失存储与 Durable 具有相同语义 |

这些是项目需求下的选择, 不证明五表, 扫描或单 Authority 是所有系统的最优方案.
通用状态机表可以物理容纳记录, 但仍必须表达 current, 许可, 证据和唯一 Outcome 约束;
减少表数不能作为削弱这些约束的理由.

## 4. 尚未由研究消除的风险

- 已持久授权与外部调用之间不原子, 外部完成与 Report 提交之间也不原子. 未知结果不能仅靠 retry policy 解决.
- 文件, Browser/Device 的资源不能默认跨节点互换; 一套 IEO 不提供设备迁移或资源一致性.
- 权威切换, 备份恢复和共享资源竞争需要独立协议, 不能借用框架名称宣称已解决.
- OTP/Ecto 的成熟度不等于本项目的组合正确性; Skuld 候选尤其尚未做版本锁定和故障评估.
- 当前资料支持架构判断, 不构成性能比较, 依赖选型或真实后端验收. 源码/官方文档与本项目推断须继续分开.

因此后续从小型执行闭环取得真实后端与 Adapter 证据, 再按需求增加计算组合或迁移能力.
接口和阶段验收见 [整体架构](../spec/runtime-architecture.md) 与 [实现路线](../spec/implementation-roadmap.md).
