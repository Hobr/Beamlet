# 首版原子存储命令契约

状态: 首版实现契约草案. 将已确认的 IEO, lease, 报告与 History 规则细化为可测试的逻辑 Interface; 不新增 Runtime, Ecto
schema 或通用 transition 引擎. 支持目标仍为 Ecto SQLite/PostgreSQL. 关联:
[核心状态机](core-state-machines.md), [lease](leases-and-permissions.md), [值与消息](persistent-values-and-messages.md),
[Handler 与恢复](handler-recovery-contracts.md), [多 Intent 与调用方组合](multi-intent-and-tool-calls.md).
Coordinator/Domain/Storage 与 Ecto Schema/Repo 的职责见 [整体架构](runtime-architecture.md);
完整审计材料与提交关联见 [核心状态机的 History 契约](core-state-machines.md).

## 1. 命令处理公共协议

入域前验证消息格式, 值域, 来源及当前操作权限. 领域纯逻辑接收显式的当前持久事实, 可信身份/条件和 Authority 时间;
SQL Adapter 在以下原子边界中读取并重验, 不接收客户端提供的"已合格"布尔值.

1. 开启短事务, 取得同一 Intent 的串行化保护. 提交首次查找/建立使用独立唯一提交身份保护.
2. 在保护内加载所有相关事实; 临时权限命令在保护取得后采样 Authority 时间.
3. 校验完整守卫, 计算领域修改和 History; 保存相关状态, 报告/Outcome, 关联及必要身份记录.
4. 提交成功后才形成 Durable 确认. 外部 Handler, 查询, 回调发送和通知均在事务外.

结果分为 `Committed`, `Rejected(reason)` 和 `Indeterminate`/可重试存储异常. 失去提交响应不等于回滚成功,
调用方使用稳定身份查找/重投; 对无 key 创建不能承诺去重. 不把数据库超时, busy 或断连转换为 Failed Outcome.
存储重试重做事务内读取和守卫, 不自动重做外部调用. 唯一约束是最后防线, 约束异常本身不是已完成的领域处理.

核心控制请求不套用协调命令的全量拒绝结果缓存. 下面逐项指定重投语义; 明确拒绝可返回最新事实,
不得假装为 Q66/Q67 的原处理结果协议. 权限失败不占用领域身份.

### 1.1 最小 Interface 的材料与错误草案

公开签名与 wire 字段名尚待确认, 但调用者与 Adapter 不能省略以下区分:

| 操作类 | 输入义务 | 返回义务 |
| --- | --- | --- |
| Submit | 可信 collection 路由, 当前 principal, 可选稳定提交身份, 完整不可变定义 | created/existing 或 DefinitionConflict; 有读取权限时返回原身份/当前事实, 不只返回入队成功 |
| 执行控制命令 | 完整 Intent/Execution 作用域, 对应 token/expected generation 或新尝试身份 | 已提交变化或当前拒绝; 授权/领取按下节原身份重投规则恢复 |
| RecordReport | 可信来源域, 完整关联, 稳定报告身份和逻辑正文 | Stored/DuplicateStored/ConflictStored 与独立 Outcome/待协调事实; 确认不早于 commit |
| ReadFacts | 稳定 Intent 身份, 当前读取权限, 必要有界读取参数 | 已提交一致事实; 无读取权限不泄露定义, 凭据或 Outcome 正文 |
| DiscoverWork | collection, 有界分页/筛选参数 | 候选与重新扫描依据; 不是领取或授权, 也不是可靠订阅 |

入域格式/认证失败, 明确领域拒绝, 明确未提交的存储故障和无法判断提交结果的响应分别表达.
`Indeterminate` 不是业务错误, 也不能直接由调用方便利层重发外部请求; 先按该命令身份查询/重投.
`Rejected` 可以伴随已提交的到期屏障, 因而结果须能区分是否存在已确认持久变化;
无法确认该屏障提交时仍返回存储不确定性, 不返回假的 durable 拒绝.
存储重试次数耗尽不会变成 Failed Outcome. 传输必须无损保留这些区分, 不统一折成 boolean/异常文本.
Report/事实返回按当前权限裁剪; 领域错误码与解释版本稳定, 调试异常不得成为长期结果比较材料.

调用方便利层可以提供 submit/read/wait 的统一入口, 但同步等待只是本次调用的等待方式,
不改变 Effect 可独立提交和恢复的语义. 等待超时返回仍在等待或读取不确定性, 不能生成 Cancelled/Failed;
取消必须发出独立获授权命令并观察其提交结果. 进程内 wait handle 不是持久身份, 重启使用原 Intent/提交身份读取.
`await_all`/部分推进所需的完整 manifest, 已消费结果和决定由调用方保存, Storage 不隐式新增依赖图.

固定的 Interface 义务是稳定身份, 完整守卫, 持久确认, 独立 Outcome 以及上述错误区分;
函数参数名, Behaviour 签名, 传输编码和分页格式仍是实现前选择. 不能让这些未定形式放宽已确认的语义.

## 2. 最小命令集合

| 命令 | 原子读取/守卫 | 同事务修改和 History | 重投/竞争结果 |
| --- | --- | --- | --- |
| Submit | collection/namespace/key, 原定义及当前权限 | 首次建立 Intent, 不可变定义, Intent 幂等上下文与建立历史 | 同 key 同定义返回已有事实; 异定义冲突; 无 key 每次创建 |
| CreateExecution | Open, 无当前尝试, 新 Execution 身份 | Prepared, current 与 Created 历史 | 相同已建立尝试可查询; 不重新建立或把旧 ID 用作新尝试 |
| ClaimPrepared | Open/current, Prepared, 无 grant, 旧 lease 已失效/到期 | 新 generation/token, lease; 必要旧代失效和 Claimed 历史 | 同一旧 generation 上两次竞争最多一次成功; 不给重投分配第二个 generation |
| RenewLease | Open/current, 完整 token, 未失效且 now < expiry | 更新 expiry; 普通续租不追加领域 History | 不承诺原 expiry 重放; 重投须重验当前 token/时间 |
| ExpireLease | 原代已领取, 未持久失效且 now >= expiry | 失效事实, 必要 Unknown, Expired/失联理由 | 已失效返回当前事实, 不追加第二次 Expired |
| AuthorizeStart | Open/current, Prepared, 完整有效 token, Handler/重试条件 | 唯一 grant, Handler/完成关联快照, StartAuthorized 与 Authorized 历史 | 相同 token 返回原 grant/快照; 不再次授权或换 Handler |
| RecordReport | 合法来源/绑定, Operation, 报告身份/内容, 当前事实 | 新证据, Execution 投影, 冲突历史; 合格完成另原子保存 Outcome/Closed/终结历史 | 同内容补确认; 异内容保留冲突; 迟到报告不改既有 Outcome |
| ReplaceExecution | Open/current, 新尝试身份, 恢复理由, 独立安全依据 | 旧 lease 失效, 新 Prepared/current, 原依据和替代历史 | 条件竞争失败不建立孤立尝试; 保留旧 grant/报告/绑定 |
| StopKnownFailure | 策略已停止, 合格当前错误, 无未知风险/未解释旧成功/冲突 | OutcomeFailed, Closed 与来源/停止理由历史 | 已 Closed 读取已有结果; 不重复终结 |
| CancelIntent | 当前取消权限, Open, 无 Outcome | 唯一 Cancelled, Closed 与控制面历史 | 与完成先提交者赢; 不承诺停止外部调用 |

Claim 请求携带调用者观察的 expected generation, 新 token 响应丢失后用
`(execution, worker, incarnation, expected generation)` 识别原领取, 在相同领取仍有效时返回已分配 token.
不从同一过期请求分配下一代; 要重新领取须读取当前 generation 后提出新请求. 原执行实例仍把 Claim 与得知 token 合并;
[独立领取模型](../quint/beamletClaim.qnt) 另展开分配提交与回复丢失/送达, 检查原请求重投不重新分配.
该逻辑关联可由原 lease/身份事实实现, 不自动要求新增 SQL 表; 实际后端仍须通过下述符合性场景.

AuthorizeStart 的身份由 `(execution, worker, incarnation, generation)` 确定. 已保存相同 grant 的重投返回原内容,
即使现时 lease 到期/Intent 已关闭; 回复不表示新许可, 不能携带新 Handler/上下文. 来源与读取权限仍需验证.
不同 token 的重复授权拒绝. Worker 只接受其当前 incarnation 的原 grant; 单 Execution 最多调用一次.
Worker 在本地无法确定是否已经调用时, 必须进入恢复流程, 不能把进程重启当作可再次调用的依据.

## 3. 到期拒绝与持久屏障

- 在 Renew/Authorize/Claim 的事务内发现所引用的当前代已到期时, 可先提交该代失效和必要 Unknown/History,
  再返回 `LeaseExpired` 拒绝. 返回拒绝不代表 durable 一定没改变; 这个分支不可用整体 rollback 吃掉失效屏障.
- 同一失效事实只记录一次. 旧 token, 格式/权限错误不制造对当前代的失效事实.
- 已过期 Prepared 的合法重新领取, 在同事务保存旧代失效和新代; 之后回拨不使旧代恢复.
- 库存条件冲突/事务失败不能发送持久失效确认. 下一次必须从已提交状态重新判断.
- Waiting 的合法登记与回调绑定保留; 只因 lease 到期不改为 Unknown, 不撤销既有 grant 或正常结果资格.

## 4. 时间和计数

首版持久 lease 时间使用 UTC Unix epoch 的整数毫秒, TTL 为正整数毫秒, 溢出拒绝. 规则为 `now < expires_at`;
相等即到期. 领域函数不自行读系统时间, Worker 时间只用于本地提示.

PostgreSQL 在取得 Intent 保护后使用数据库 `clock_timestamp()` 采样, 向下量化为毫秒;
不使用事务开始时间 `now()` 代替锁等待后的验证时间. SQLite 在写事务/保护内通过同一 SQL statement 的 `now`
从当前 VFS 采样, 组合 epoch seconds 与 `%f` 的毫秒部分, 避免应用主机先验取时和 Julian-day 浮点误差.
具体查询和驱动版本必须通过下述符合性测试; SQL 时间不默认具有不可回退性质.

generation 使用非回绕的正 64-bit 计数, 耗尽时拒绝新领取并保留事实, 不清零. incarnation 是新 Worker 会话的稳定身份,
重启必须新建且不复用; 其实际编码属于消息 codec. Coordinator 普通重启不自动换掉远端有效 lease.

幂等契约时间不是 lease 墙钟. 没有可信资源有效期或保守时钟误差依据时, Handler 的时限幂等不能授权危险重试;
详见 [Handler 契约](handler-recovery-contracts.md). 不能仅靠对本地墙钟取历史最大值宣称知道真实资源时间.

## 5. 两个 SQL Adapter 的符合性要求

PostgreSQL 可使用 Intent 行锁和唯一约束; SQLite 可用 `BEGIN IMMEDIATE`/等效写入序列化及条件写入.
这是允许的实现策略, 实际 Ecto 驱动必须证明采用的事务形式. SQLite 写锁可以串行化独立 Intent 的写入,
不因此宣称物理写并行; 逻辑上独立 Intent 的 Worker/外部执行仍可并发.

两者均必须保证: 无同 Intent 写偏斜, 完整守卫在事务内重验, 一份唯一 Outcome, 报告冲突材料不覆盖,
状态与 History 同提交, durable 提交后才能确认. 不要求靠重放 History 重建每次续租.
SQLite 必须启用外键及满足持久性目标的 journal/synchronous 配置; PostgreSQL 不允许以异步提交冒充同步 durable 确认.
磁盘, 文件系统, 复制及故障转移保证作为部署前提单独记录, 不声称任意硬件掉电零丢失.

后端错误只做有界事务重试并暴露诊断; 重试耗尽返回存储异常, 不改变操作结果. 每次重试重新采样时间.
不得持锁等待网络, 也不依赖单个 GenServer 作为唯一的并发保护.

## 6. 一致读取和候选发现

`ReadFacts(intent)` 返回一个已提交一致快照: 原定义, 当前 Execution 与 lease/授权, 等待关联, 原始报告/冲突, Outcome
和必要 History. 可以分页 History/报告, 但必须携带稳定快照/游标语义; 首版可先用受限完整读取, 不能拼接互相矛盾的瞬时快照.
当前读取权限独立于提交权限, namespace/Intent ID 不是授权凭证.

`DiscoverWork(cursor, limit)` 从持久事实投影 Open 的 Prepared, Waiting, Unknown 候选, 不返回启动许可.
重复发现可接受, 遗漏通知不丢工作; 领取/查询/重试必须再次过当前守卫. 扫描可用稳定身份游标和周期重扫,
不能单靠易失队列或递增游标承诺可变候选永不遗漏. 不要求全局公平性或跨 Intent 顺序.
首版通知是尽力唤醒; 发送失败由重扫弥补. 若以后承诺可靠通知, 另行设计 Outbox, 不扩大现有原子事务到外部服务.

## 7. 后端验收清单

以下场景各在真实 SQLite/PostgreSQL Adapter 运行, 不是用内存假实现代替 SQL 的检查:

1. 两个 Coordinator 同 key 同/异定义提交; 两个不同 key 保持身份与读写隔离.
2. 双 Worker 竞争领取, 领取响应丢失重投, 旧 expected generation 不分配新代.
3. 续租与到期, 授权与取消, 报告与替代, 两个终结候选竞争; 检查提交前后完整事实与 History.
4. 持锁延迟跨越 expiry, 数据库时间恰等 expiry, 失效提交后回拨; 旧代不复活.
5. 授权提交后回复丢失, Coordinator 重启, Worker 新 incarnation; 原 grant/Handler/关联保持, 不重复调用.
6. 报告/Outcome/History 写入的各故障点整体回滚; commit 后响应丢失能查到原事实并安全重投.
7. 同身份不同报告值竞争保留两份证据; Closed 迟到报告不改结果, 持久回执不早于 commit.
8. SQL busy/deadlock/serialization failure 有界重试, 不外部重调用; 故障后未提交记录不可见.
9. 同一 Intent 的一致读取与跨 Intent 隔离; 通知全丢, 重启后重扫能重新发现候选.
10. 记录驱动/数据库/存储配置并检查进程终止后的事务恢复; 真实掉电保证另行验收.
11. 两个 Agent 的相同局部 key 在不同 namespace 独立, 同身份同定义复用; 回复丢失/重启后取回 Closed 结果.
12. 两个 Intent 的局部 Execution/report/token 编号相同, 验证 grant, 报告, 回执及回调的可信 Intent 作用域;
    错路由拒绝, 共享 Worker 重启不继承任何 Intent 的旧许可, 不修改另一 Intent 的结果/History.

当前只完成可执行抽象及这份工程验收规格, 尚无真实后端测试结果. 不将 Quint 的原子转换当作上述 SQL 事务实现已经通过.
