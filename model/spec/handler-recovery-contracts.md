# 首版 Handler、回调与恢复策略契约

本文规定首版 Handler/Callback Adapter 的声明、持久快照、回调关联和停止/重试契约。
Operation 的业务语义由对应版本定义，具体网络协议、凭据配置与资源端保证须由 Adapter 验证。
关联: [Operation / Handler](operation-handler-contracts.md)、[存储命令](storage-command-contracts.md)、
[值与消息](persistent-values-and-messages.md)、[模型覆盖](../quint/coverage.md).

## 1. Handler 声明与持久快照

Handler 声明至少包括实现身份/发布号、兼容 Operation Identity 集合, 以及各能力的协议版本与条件.
Authority 从已配置受信登记读取声明, 不采用提交者或 Worker 正文任意提供的 capability 布尔值.
Handler 实现身份变化不等于 Operation 契约变化; 兼容新实现也不能静默换掉外部 account、key scope 或协议解释.

启动授权事务保存本次选择的实际 Handler 身份/声明版本、Operation、恢复协议、稳定 Intent 幂等上下文,
影响恢复的外部目标/账户作用域、幂等键映射版本及有效期依据, 以及 Pending/query/callback 必需的恢复材料引用.
凭据正文不进入 History; 保存能在受控凭据配置下找到正确账户和核验方式的稳定引用. 历史解释材料随 Intent 保留.
该快照先于外部调用, 授权回复重投返回原快照. 这些是逻辑必需材料, 不批准具体 SQL 字段列表.

首版至少提供以下可区分操作, 不要求合成一个 callback-heavy 的通用框架:

- `invoke(authorization, input, intent_context)` 返回同步完成或可恢复 Pending; 不自行授予第二个 Execution.
- 声明支持时, `query(binding)` 形成带来源/协议依据的 Report; 网络错误不构成 NotExecuted.
- 声明支持时, `verify_callback(raw, transport_context)` 核验并形成稳定 Report, 与原 Worker 生命周期独立.
- `assess_retry(original_binding, current_contract_facts)` 给出可核验的安全依据或不可重试理由, 由 Authority 重验.

没有兼容 Handler 时保持 Prepared/等待资源, 不用最新 Operation 替代, 不仅因配置缺失创建 Failed.
配置选择的资源条件必须明确参与硬约束匹配; 资源暂不可用只影响派发节奏.

## 2. 幂等与独立安全依据

安全重试依据分别为: 从未授权、可靠排除旧尝试既往及未来执行、仍有效的外部幂等协议, 或明确接受重复风险.
已知 Failure 可能留有部分效果, 因而不是单独的安全重试依据. 超时、lease 到期、NotFound 亦不是.
首版正常入口默认不接受重复风险; 不能把 `RetryOnce` 本身解释为接受重复效果.

幂等声明必须说明: 外部服务/账户/资源 scope、稳定 key 派生、同输入要求、返回旧结果规则、重复并发请求处理,
有效期起点/终点及最坏重传/延迟窗口. Intent context 持久且跨 Execution 不变, 不把 Execution ID 或 incarnation
直接用作重试新 key. Handler 映射外部 key; 多步骤派生子键要由版本化协议保持稳定, 不能因发布升级换算法.

后续尝试的替代、授权和调用分别检查仍适用的依据. 保存首次快照不意味着窗口永不失效;
换兼容 Handler 时仍须匹配原 scope/protocol/key 解释并保留能力. 不得使用新 Handler 的较长静态窗口凭空延长旧 key 保证.
条件需要资源证明或可保守校验的时间依据; 无法重验时拒绝危险重试, 保留事实.

时限保证必须覆盖请求到达并由资源原子去重的时刻. 本地调用前检查不足以覆盖无限网络延迟;
可使用资源在过期后拒绝旧键请求的协议、无期限幂等保证, 或明确有界误差/延迟且留足裕量的条件.
这些保证未成立时, 首版宁可保持 Unknown/等待, 不把 model 的抽象 contractTime 当成现实的资源时钟.

## 3. 回调关联与可信入口

回调型调用的完成关联最迟在 Start Authorization 事务提交时建立, 可以在发起前分配 opaque correlation 并传给服务.
若 provider 的 operation ID 只能在调用后取得, Handler 必须有预分配关联或受控持久 inbox/注册协议处理早到回调;
做不到就不能声明本协议的可恢复 Pending. 不用进程邮箱临时等待代替持久关联.

关联至少可恢复 collection/Intent/Execution/Operation、provider/account scope、核验方式版本及稳定报告身份映射.
correlation 不是凭据, 不复用 Worker lease token 作为第三方认证. 未知关联返回可诊断的入域拒绝,
不能猜测最近一个 Waiting Execution; 若声明早到 inbox 协议, inbox 的保存/绑定和重放单独满足认证与原子一致性.

可信 Adapter 按 provider 的版本化协议核验签名/MAC、账户/受众/端点绑定、事件身份、正文完整性和重放限制;
认证失败不得形成核心 Report. 重放窗口不能让合法晚到完成永久无法恢复: provider 必须能以可验证方式重投,
或提供经认证查询/已核验持久 inbox. 不能为了接收晚到消息而跳过验签.

Adapter 通过验证后转换为同一逻辑 Report Envelope, 重投保留 source_scope/report_id/kind/body.
核心继续验证持久关联、Operation、值域和来源资格. 网络中同事件的签名/重投时间可改变, 逻辑证据不改.
同事件正文变化按冲突保存, 不能靠去重缓存直接覆盖/丢弃. 保留用于追溯的验证版本和依据引用, 但不在日志泄露凭据.

持久回调发送方/inbox 只有取得 Durable Stored 确认后才能停止重投; 回执丢失用原 Report 重投.
若外部平台不支持重投且无查询, Handler 须自行提供可靠 inbox, 否则应披露只能保守 Unknown 的可恢复性限制.
Worker 已释放、lease 已到期、Coordinator 已重启不撤销关联; 完成可以先于 Pending. Closed/已替代时合法证据仍可保存,
但不重开 Intent、不越过当前结果资格. 关联与去重材料随 Intent 保留, 首版不做 TTL 清理.

## 4. 首版停止与重试策略

可执行模型保留两个小策略, 不建设通用调度/策略 DSL:

| 策略 | 明确确定失败后的决定 |
| --- | --- |
| StopOnFailure | 不再建立后续尝试; 满足结果守卫时同事务接受 Failed |
| RetryOnce | 最多两个已建立尝试; 首次失败且存在适用的独立安全依据时继续, 否则停止 |

第二次尝试已建立即消耗额度, 不因启动失败或未调用回收计数. 已授权未知的第二次尝试不能仅因额度耗尽变成 Failed.
第一尝试已知失败而幂等窗口后来失效时, 可以由 StopKnownFailure 在新事务内接受原错误;
不是伪造第二次失败, 也不重新写已保存报告. 报告接收时已经满足停止条件则与完成/History 一起原子终结.

Unknown、Pending、NotFound、存储/传输错误不映射为确定 Failure. 即使策略已决定停止, 仍要求明确合格错误、当前结果资格,
无未解释旧成功/冲突以及无已授权未知风险. 不能以策略预算压过这些守卫. 安全依据失效后存在未知风险时保持 Open.

首版 Failure 统一作为可评估一次重试的明确错误; 更细的业务错误可在 Operation 合法结果里表示,
不从自由文本或 HTTP 状态码猜测安全性. 不提供运行中预算/策略修改命令, 初始策略快照不可变.
退避仅安排候选的 not-before 时间, 不授予许可也不延长幂等窗口; 首版可以立即再次评估, 不承诺自动重试时限.
部署的限流/唤醒配置不改 IEO 事实, 不把“调度没及时执行”转换为 Failed.

## 5. 恢复与测试矩阵

| 触发 | 必需行为 | 抽象/工程检查 |
| --- | --- | --- |
| 启动授权回复丢失 | 原 token 取回同一 grant/Handler/关联; 不再次授权 | lostAuthorizationReplyUsesOriginalBindingTest; 真实传输重投 |
| 回调丢失/回执丢失 | 核验过的原 Report 重投, 最多保存一次同内容证据 | lostCallbackRedeliveredAfterRestartTest; provider/inbox Adapter 测试 |
| Worker 重启 | 新 incarnation 不接续旧调用许可; 旧证据仍可认证 | recoveryRestartRejectsOldGrantTest; Worker 协议测试 |
| 已知失败后安全窗口过期 | 不能重调用; 具备终结资格时提前停止 | earlyStopWhenIdempotencyExpiresTest |
| 窗口过期但结果 Unknown | 保持 Open, 不伪造确定失败 | unknownCannotStopAfterWindowExpiresTest |
| 查询不支持/认证失败/关联不匹配 | 不形成可信完成事实 | 原 Pending/query/callback 场景; 真实 Adapter 测试 |
| 两个独立 Intent | 绑定、幂等键、报告与结果不串线 | [双 Intent 完整组合](../quint/coverage.md); 另需 SQL/Adapter 并发符合性测试 |
| Tool Call 多依赖 | 按稳定身份读取每项 Outcome; 重启从原清单重建 | [调用方组合契约](multi-intent-and-tool-calls.md); 清单由调用方持久保存 |

真实 Adapter 还须覆盖 key 映射稳定性、账户/协议切换拒绝、边界时限/延迟、签名轮换、重复/矛盾内容和受限值解码.
当前 Quint 检查的是“前提被核验后”的安全关系, 没有真实第三方签名、网络时间保证或 SQL 后端结果.
多 Intent 已检查有界交错与共享 Worker; 实际派发公平性/Liveness、Authority 迁移、归档和后置治理仍按首版范围保留边界.
