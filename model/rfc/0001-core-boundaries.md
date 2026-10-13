# RFC 0001: 核心边界与设计理由

本文说明核心设计取舍及其代价. 交付边界见 [首版范围](../spec/first-release-scope.md),
行为细节见 [SPEC](../README.md), 组件与部署见 [整体架构](../spec/runtime-architecture.md),
成熟机制与替代方案见 [RFC 0002](0002-runtime-tradeoffs.md).

## 产品命名与层次

按 [README](../../README.md) 的命名约定, **Beamlet** 是 Effect Engine 的名称, 涵盖核心 Effect 系统及其运行时;
**Beamlet!!!!!** 是基于 Beamlet 的 Agent 框架及其系列产品的名称, 五个感叹号是名称的一部分.
Beamlet-Agent, Beamlet-CLI, Beamlet-TUI, Beamlet-Web 和 Beamlet-Mobile 是 Beamlet!!!!! 系列中规划的组件名称.
本文中的 Beamlet 指引擎层; 上层 Agent 框架的命名不改变下述核心职责与恢复边界.

## 1. 独立 Effect 与调用方恢复

Beamlet 负责独立 Effect 的持久提交, 执行尝试管理, 权威结果接受和查询. Agent
上下文, 业务依赖清单, 等待集合与计算恢复由上层维护; Runtime 承担已接受 Intent 的最小派发, lease 检查和必要执行恢复.
这让调用方可以组合多个 Effect, 而不使核心隐式承担完整 Workflow Engine 的状态与控制流.

核心采用统一异步提交语义: 先持久接受 Intent, 再处理, 最后读取或等待 Outcome. 同步等待是调用侧便利接口,
等待进程退出不改变身份与生命周期, 长等待不要求 Worker 常驻. 不同 Intent 可以并发; 同一 Intent 首版不做主动 hedging,
默认仅有一个当前授权候选, 但仍保留多个 Execution 的独立记录.

通知降低延迟, 持久事实提供恢复依据. 默认通过数据库状态与必要调度数据重新发现工作, 不强制 Transactional Outbox.
若未来需要向消费者可靠发布每个历史事件, 可另加 Outbox; 其原子入队仍不保证消息不重复或外部执行恰好一次.

## 2. 权威边界与持久存储

每个 Intent 只有一个逻辑 Authority 裁决 Outcome 和关键生命周期. 这不要求全系统单中心, 单 Coordinator 进程,
也不要求不同 Intent 共享 Authority. 不可达时不能自动在另一份数据库建立独立权威并事后合并; 代价是缺少安全迁移协议时,
权威不可用会影响提交可用性.

领域决策是纯规则: 快照, 命令, 显式时间, 权限, 策略与证据产生拒绝理由或待提交变化, 不直接访问数据库或网络.
Storage Interface 围绕完整原子领域命令, Coordinator/Storage 在保护内加载, 重验并提交, 防止并发状态使决定失效.
同 Intent 的建立/替代, 启动, 证据接收, 资格和终结共用原子并发边界; 不同 Intent 不要求全局串行.

Durable 一致性由真实事务与数据库约束保障, 不能只依赖一个 GenServer. 多个 Coordinator 处理同 Intent 时仍须保持唯一
Outcome 和完整组合状态. 正式后端为 Ecto SQLite/PostgreSQL, 不增加独立 Memory/ETS Storage; 纯领域测试使用普通快照,
存储符合性使用真实 SQL. ETS 若用于缓存, 不承担权威存储职责.

首选 intents / executions / outcomes / reports / history 五类逻辑实体. Report 保存收到的不可覆盖证据, History
解释如何处理, Outcome 保存最终接受的结果; 不能用 Execution 的单一可覆盖 result 承载迟到或矛盾报告.
这不规定物理表数或通用 Transition 框架, 也不引入 Event Sourcing.

## 3. Intent, Execution 与 Outcome

采用 [IEO 领域语言](../../GLOSSARY.md): Intent 表达逻辑操作, Execution 表达一次尝试, Outcome 表达不可变权威结果. 建立
Execution 不表示外部已开始, 报告也不等于结果已接受. 每 Intent 至多一个 Outcome, 这是 Safety
要求, 不保证最终产生结果.

Intent 只有 Open/Closed: Open 表示尚无 Outcome, Closed 当且仅当已有 Outcome, 之后不再新建尝试或授权.
Succeeded/Failed/Cancelled 由 Outcome 表达, Intent 不重复保存一套结果分类. Open 本身不足以指导调度,
等待, 重试和阻塞依据仍需持久保存或可推导.

Execution 使用 Prepared / StartAuthorized / Waiting / Unknown / Resolved, 表达 Runtime 掌握的协议事实.
Dispatched 是审计事实, Succeeded/Failed 是尝试结果数据. 进展, 直接结果资格和证据冲突是独立维度,
撤权不伪造外部已结束, 也不停止接收后续真实结果.

Intent 的可空 current_execution_id 表达正常候选的一部分资格. 替代时原子建立新 Execution 并切换 current;
普通完成还须满足
Open, 来源, 证据和风险守卫. 旧尝试失去直接提交资格, 报告继续保存, 未来可经明确协调验证使用.

Outcome 分类为 Succeeded / Failed / Cancelled. Succeeded 表示操作契约的正常完成, 审批拒绝可以是正常业务结果;
Failed 表示明确错误或合格终结依据; Cancelled 表示逻辑停止继续处理. Outcome 属于 Intent: 普通完成保留 Execution 关联,
控制面终结无需伪造尝试, 协调结果须保留理由和证据来源.

## 4. 不确定性, 失败与取消

Unknown 是尚未解决的知识状态, 不产生终态 Outcome, 可由迟到报告, 查询或后续协调补充事实.
超时, lease 到期, Worker 失联和预算耗尽均不能把未知变成确定失败.

一次 Execution 失败不自动终结 Intent. Failed
至少需要合格错误/终结依据, 明确停止策略, 以及不存在仍可能改变逻辑结果的未解决风险. 已知失败可以伴随部分副作用, Failed
不证明外部什么都没发生.

危险重试需要可靠外部幂等, 能排除旧尝试既往及未来执行的协议证据, 或调用方明确接受重复风险.
not_found, 尚未开始或暂无结果默认只构成证据: 查询时没发现, 不能排除已获授权的旧 Worker 稍后发送请求.

取消是逻辑终结, 可尽力请求 Handler 停止, 但不证明外部停止或回滚. 取消与合格完成竞争时,
第一个通过全部守卫并完成权威事务提交的终结决定获胜, 不按请求时间或 Worker 墙钟追溯改写.

## 5. 派发, 领取与启动授权

外部调用前必须取得已持久化的 Start Authorization. 授权不等于真实开始; 授权后缺少报告仍须考虑操作可能发生,
授权与外部调用不跨系统原子化.

启动许可绑定可序列化的 Worker incarnation, 重启产生新 incarnation, 不继承旧许可调用.
派发, 授权回复或报告的传输重投保留原 Execution 身份, 不创建新尝试或重复外部调用.

Prepared 且权威记录确认从未授权时, 旧领取失效后可换 Worker 领取同一 Execution.
已经授权则不能依据 Worker 声称未收到许可或未执行而无条件接续; 再次执行必须经过独立安全条件的新尝试.

lease 管理临时领取, 启动申请, 续租和相应控制权限, 结果资格独立验证. 到期不自动撤销当前尝试结果资格,
Waiting 继续等待; 已授权且缺少可靠结果/等待登记时可进入 Unknown, 保留迟到结果入口, 不立即替代.

## 6. 时间, 代次与重启

到期由 Authority 时间裁决, 不使用 Worker 时间戳或跨实例裸 monotonic expiry.
PostgreSQL 在原子保护内取得验证当刻的数据库时间, 不用长事务起点 now; SQLite 使用权威操作路径当前 VFS 时间.
领域接收显式时间, 事务保持短小, 数据库墙钟跳变不能证明旧操作停止.

Authority 为领取分配持久 generation 并绑定 incarnation, 重新领取增加 generation, 续租不更换, 不重置复用.
旧代不能续租或申请启动, 但旧报告按独立来源/结果资格验证. generation 不能隔离另一份独立数据库, 也不自动提供外部
fencing.

只有 now < expires_at 才有效, 相等即到期. 确认到期/撤销后持久保存失效事实, 回拨不能复活该代;
回拨发生在确认前仍可能延迟检测. 新领取需要新代, 不表示同一尝试可第二次启动.

普通 Coordinator 重启重新读取已提交事实, 不默认使所有远端 lease 失效.
Authority 迁移则在新权威激活前使旧临时权限失效, 保留 Execution, 启动事实, 结果资格, 幂等上下文与完成关联,
不把已授权尝试重置 Prepared.

迁移方向选择旧 Authority 可配合的计划手动交接, 需要一致数据切点, 旧权威撤权和新权威激活.
备份一致或目标 epoch 增加不能独自完成撤权. 完整流程后置, 不承诺旧权威不可达时强制接管或无停机迁移.

## 7. 报告, 证据与原子接受

Report 使用来源作用域内稳定身份, 重投保持身份与逻辑内容. 同身份同内容去重, 同身份不同内容保留冲突材料;
不同身份同内容可以是独立观察, 不以内容 hash 代替报告身份.

持久化确认与 Outcome 接受分别表达. 证据提交后发送方可停止重投, 不要求该报告赢得 Outcome;
未落盘不能确认已持久化. Worker 未获确认就崩溃且没有保存报告仍可能留下 Unknown.

普通合格完成默认同事务保存报告, Execution, Outcome, Closed 和 History.
已撤权, 冲突或待查询报告可以只保存证据; 竞争失败或迟到事实不产生第二个 Outcome.

重要的迟到报告, 拒绝和冲突即使不改变生命周期也须可审计. History 保留领取/代次变化, 权威失效, 启动, Unknown,
替代及安全依据; 普通心跳/续租不逐条写领域历史, 但更新仍经过原子验证. History 不承担重放全部心跳的职责.

矛盾报告不能覆盖或按最后写入决定结果. 冲突独立于生命周期, 保留最近有依据的投影, 例如 Resolved 后发现矛盾仍为 Resolved,
同时保留争议. 尚无 Outcome 时冲突阻止未经协调的自动终结; 已有 Outcome 不改写, 但迟到冲突继续保存.

失去直接资格的旧成功仍可能改变逻辑结论, 不能因 current 切换就忽略它并普通提交 Failed.
采用或排除需要明确契约依据; 首版无法处理时保持 Open 并提供事实读取, 显式取消仍遵守自身守卫.

## 8. Operation, 值与 Handler 协议

Operation Identity 包含兼容契约版本, 例如 llm.generate.v1.不兼容变化使用新身份, 保持契约的修复可复用身份; 旧 Intent
只能由兼容 Handler 解释. 代码发布版本, 数据库迁移与 Operation 契约版本分别处理, 不要求通用 Schema Registry.

输入, 结果, 策略和等待材料使用受限, 运行时无关的纯数据值. 可编码不等于可恢复, 不持久化 PID/Reference/Function/Port.
逻辑合法性, 相等性, 预算与 codec 分开定义, 任意 term 或任意 JSON 均不能默认接受. 首版细节见
[持久值与消息](../spec/persistent-values-and-messages.md).

Pending, 查询, 取消, 幂等, 安全重复必须显式声明条件, 未声明按不支持处理.
静态能力名称不证明有效期, 作用域或当前前提成立; 启动时保存实际 Handler 和影响恢复/重试的能力协议快照,
后续兼容实现不能静默改变外部账户, 键或协议解释.

可靠幂等可用时, Intent 保存稳定 Idempotency Context, 不同 Execution 复用, 迁移保留. Handler
按外部协议映射键与作用域, 多步骤可派生稳定子键; 它不同于 Submission Key, 也不能给不支持幂等的目标增加保证.

Pending 协议保存可恢复等待材料后可释放 Worker, 通过回调或查询继续, 不因重启重新创建外部请求.
回调 Adapter 负责验证第三方来源, 解析后形成 Report; 核心检查关联, 身份, 资格和契约, 不直接采用未经验证正文.
完成关联最迟在启动授权提交时持久建立, 先于外部调用; 完成可先于 Pending, 迟到 Pending 不回退已解决状态.
关联不充当认证凭证, 合法完成不依赖原 lease 存活.

## 9. 提交身份与不可变定义

调用方显式提供权威集合内的 namespace + key, 原子 create-or-get 定位 Intent.
相同身份同定义复用, 异定义拒绝, 无 key 每次成功提交表示新操作.
不按输入 hash 推断业务同一性, 也不以设备, Worker 或进程定义作用域; namespace 不是权限证明.

不可变定义包含 Operation Identity, 输入, 必要硬约束和初始策略快照.
重复提交比较原定义, 不比较当前次数, 预算或调度状态. 未来受控调整须有明确命令, 权限与历史,
不能借同 key 重提交覆盖输入, 目标或安全条件; 首版不提供运行中控制修改.

## 10. 后置协调与治理的约束

协调通过显式原子命令引用具体报告, Operation 依据, 理由与主体, 明确采用/排除的范围.
自动规则必须明确登记且条件可核验, 人工决定须获授权; 证据不足时等待, 不能任意覆盖状态或 Outcome.

新决定携带判断版本, Authority 原子比较后重验具体证据, 契约和权限.
相关证据, 资格及处置变化推进版本, 心跳, 重投和纯拒绝审计不推进.
过期人工决定拒绝并要求重新审查, 自动规则可对新上下文提出新决定; 已接受处置不因自己的版本变化立即失效.

协调与撤销共用 Intent 内稳定命令身份. 同身份同内容返回原成功或明确领域拒绝结果, 不重执行;
同身份不同内容拒绝. 入域前权限/格式失败不占身份, 未提交数据库异常可重投.
已处理身份先于新请求资格检查, 即使后来有新证据, Closed 或规则变化, 原结果仍不改写.
新提交和原结果读取分别验证当前权限, 记录随保留的 Intent 持续保留, 不默认 TTL 清除.

冲突协调覆盖完整相关报告并逐项说明依据, 保存原始报告与冲突历史; 新证据重新判断.
全部排除可以完成审查而仍未知, Open, 不证明未执行, 不生成 Outcome 或危险重试许可.

改变旧处置须明确引用被取代决定和范围, 原子保存关系与审计, 仅影响明确范围.
旧决定, 原命令结果与范围外处置保留. 自动决定绑定确切规则语义版本, 不默认为最新版本或迁移旧请求;
普通退役只阻止新提交, 不自动撤销历史处置或推进判断版本.

撤销仅移除指定当前处置, 不恢复更早被取代结论; 按原始证据重新判断必要阻塞.
撤销不生成 Outcome 或危险重试许可, 重投不转向后来处置. 普通协调权限不自动包含撤销权限,
首次接受独立验证具体目标/范围的撤销授权; 原结果读取只按当前读取权限.

这些能力后置, 引入时仍须遵守上述安全约束. 具体权限策略, 决定/关系表示, 规则登记与历史材料保留,
条件核验和清理协议须另行细化.

## 11. 模型与实现证据

采用 plain Quint, 以原子 Authority, Worker 会话, 无序消息, 独立外部事实和可跳变时钟表达协议.
各实例分别检查单 Intent 执行, 故障恢复, 多 Intent 并发及调用方组合.
Worker 可崩溃重启, 消息可丢失/乱序/重复, 已提交权威事务保留; 不假定最终投递, 公平调度或人工最终响应.

独立记录启动, 替代, 首次结果和终结提交见证, 避免唯一性退化为类型恒真. 验证见证与有界整数不是产品物理字段.
场景和随机模拟不证明真实 SQL, 认证, 外部资源保证或最终完成.
抽象模型的运行方式与验证边界见 [Quint 检查指南](../quint/README.md).

## 研究依据

- [Erlang 序列化 API](https://www.erlang.org/doc/apps/erts/erlang.html) 与
  [ETF](https://www.erlang.org/doc/apps/erts/erl_ext_dist.html): safe 不替代应用验证, deterministic 不保证跨 OTP major
  字节稳定, 可编码运行时对象不等于可恢复.
- [Ecto map 类型](https://hexdocs.pm/ecto/Ecto.Schema.html#module-the-map-type),
  [SQLite Adapter](https://hexdocs.pm/ecto_sqlite3/Ecto.Adapters.SQLite3.html),
  [PostgreSQL JSON](https://www.postgresql.org/docs/current/datatype-json.html): 逻辑值须在所选驱动与 codec 上无损往返.
- [Erlang 时间](https://www.erlang.org/doc/apps/erts/time_correction.html),
  [PostgreSQL 时间函数](https://www.postgresql.org/docs/current/functions-datetime.html#FUNCTIONS-DATETIME-CURRENT),
  [SQLite 时间](https://www.sqlite.org/lang_datefunc.html) 与 [VFS](https://www.sqlite.org/vfs.html):
  实例内 monotonic, 数据库事务起点和验证当刻的墙钟有不同语义.

这些是设计依据, 实际依赖版本, 驱动配置和部署保证仍需实现验证.
