# SPEC: Operation / Handler 与恢复契约

本文规定不可变操作定义, Handler 能力, 资源绑定, 幂等条件, 回调关联与停止/重试规则.
状态与终结守卫见 [核心状态机](core-state-machines.md), 身份和值域见 [持久值与消息](persistent-values-and-messages.md),
提交边界见 [原子存储命令](storage-command-contracts.md), 设计理由见 [RFC 0001](../rfc/0001-core-boundaries.md).

## 1. Operation Identity

- Operation Identity 是含兼容契约版本的稳定身份, 例如 llm.generate.v1.
- 契约包含输入, 结果与操作语义, 不等于 Handler 发布版本.
- 保持契约的修复可以不改变 Identity; 不兼容变化使用新 Identity.
- 旧 Intent 只能由兼容 Handler 解释, 不得隐式套用最新版本.
- 第一阶段不要求通用 Schema Registry 或以 Schema Hash 代替版本.
- 数据库 schema 和 Runtime 协议的迁移不是 Operation Identity 自动提供的能力.

## 2. Intent 定义与提交身份

- 不可变定义包含 Operation Identity, 输入, 必要硬执行约束和初始策略快照.
- 当前预算, 调度节奏等控制数据另行维护, 调整需要明确受控命令与历史, 不用相同 key 的重新提交覆盖定义.
- 调整不偷偷改变操作输入, 目标或放宽副作用安全条件. 具体可调字段与权限待定.
- 同一个权威数据集合内, namespace + key 唯一定位 Intent, 不使用 Worker / 进程 / 设备身份定义作用域.
- 相同提交身份与相同原始不可变定义定位已有 Intent; 冲突定义拒绝, 不比较运行中已改变的控制状态.
- 提交确认丢失或上层重启时可重用该身份; 计划迁移保持身份. 无 key 的请求创建新逻辑操作.
- namespace 不是权限证明. Runtime 不自动识别业务等价, 上层必须保存或重建稳定提交身份.

首版定义相等, 文本精确比较, 持续身份保留和权威集合身份见 [提交消息契约](persistent-values-and-messages.md),
查找/建立的并发处理见 [存储命令](storage-command-contracts.md). 首版不提供运行中控制修改命令;
具体字段/wire codec, 部署路由及后置控制 revision 仍须实现或后续设计.

输入, 结果, 策略与等待材料使用 [受限值 v1](persistent-values-and-messages.md), 不包含 PID/Reference/Function/Port.
Handler 内部可以使用运行时对象, 但不能依赖它们重启后仍有意义.
特殊数值, 时间和产物引用由版本化 Operation 定义, 不采用全局隐式解码; 产物须有明确保留条件.

## 3. Handler 声明, 能力与启动快照

Handler 声明至少包括实现身份/发布号, 兼容 Operation Identity 集合, 以及各能力的协议版本与条件.
Authority 从已配置受信登记读取声明, 不采用提交者或 Worker 正文任意提供的 capability 布尔值.
Handler 实现身份变化不等于 Operation 契约变化; 兼容新实现也不能静默换掉外部 account, key scope 或协议解释.

启动授权事务保存本次选择的实际 Handler 身份/声明版本, Operation, 恢复协议, 稳定 Intent 幂等上下文,
影响恢复的外部目标/账户作用域, 幂等键映射版本及有效期依据, 以及 Pending/query/callback 必需的恢复材料引用.
凭据正文不进入 History; 保存能在受控凭据配置下找到正确账户和核验方式的稳定引用. 历史解释材料随 Intent 保留.
该快照先于外部调用, 授权回复重投返回原快照. 具体 SQL 表示由 Storage 实现选择.

Handler 接口需要区分以下操作:

- `invoke(authorization, input, intent_context)` 返回同步完成或可恢复 Pending; 不自行授予第二个 Execution.
- 声明支持时, `query(binding)` 形成带来源/协议依据的 Report; 网络错误不构成 NotExecuted.
- 声明支持时, `verify_callback(raw, transport_context)` 核验并形成稳定 Report, 与原 Worker 生命周期独立.
- `assess_retry(original_binding, current_contract_facts)` 给出可核验的安全依据或不可重试理由, 由 Authority 重验.

没有兼容 Handler 时保持 Prepared/等待资源, 不用最新 Operation 替代, 不仅因配置缺失创建 Failed.
配置选择的资源条件必须明确参与硬约束匹配; 资源暂不可用只影响派发节奏.

能力未声明时按不支持处理; 名称或静态布尔值不能替代对条件的核验:

| 能力 | 需要明确的语义 |
| --- | --- |
| Pending | 能否建立重启后可解释的等待及关联 |
| 查询 | 可查什么, 什么证据可以确认结果或未执行 |
| 取消 | 尽力请求停止, 还是能取得确认停止的证据 |
| 幂等 | 外部去重作用域, 有效期, 输入一致性与其他前提 |
| 安全重复 | 为什么重复可接受, 或由谁明确接受重复风险 |

快照保留原解释, 不使能力条件永久成立. 协调, 规则退役与处置撤销属于后置能力,
遵守 [证据协调规则](core-state-machines.md), 不混入 Handler 的能力声明.

## 4. 幂等与独立安全依据

安全重试依据分别为: 从未授权, 可靠排除旧尝试既往及未来执行, 仍有效的外部幂等协议, 或明确接受重复风险.
已知 Failure 可能留有部分效果, 因而不是单独的安全重试依据. 超时, lease 到期, NotFound 亦不是.
首版正常入口默认不接受重复风险; 不能把 `RetryOnce` 本身解释为接受重复效果.

幂等声明必须说明: 外部服务/账户/资源 scope, 稳定 key 派生, 同输入要求, 返回旧结果规则, 重复并发请求处理,
有效期起点/终点及最坏重传/延迟窗口. Intent context 持久且跨 Execution 不变, 不把 Execution ID 或 incarnation
直接用作重试新 key. Handler 映射外部 key; 多步骤派生子键要由版本化协议保持稳定, 不能因发布升级换算法.

后续尝试的替代, 授权和调用分别检查仍适用的依据. 保存首次快照不意味着窗口永不失效;
换兼容 Handler 时仍须匹配原 scope/protocol/key 解释并保留能力. 不得使用新 Handler 的较长静态窗口凭空延长旧 key 保证.
条件需要资源证明或可保守校验的时间依据; 无法重验时拒绝危险重试, 保留事实.

时限保证必须覆盖请求到达并由资源原子去重的时刻. 本地调用前检查不足以覆盖无限网络延迟;
可使用资源在过期后拒绝旧键请求的协议, 无期限幂等保证, 或明确有界误差/延迟且留足裕量的条件.
这些保证未成立时, 首版宁可保持 Unknown/等待, 不把 model 的抽象 contractTime 当成现实的资源时钟.

## 5. 回调关联与可信入口

回调型调用的完成关联最迟在 Start Authorization 事务提交时建立, 可以在发起前分配 opaque correlation 并传给服务.
若 provider 的 operation ID 只能在调用后取得, Handler 必须有预分配关联或受控持久 inbox/注册协议处理早到回调;
做不到就不能声明本协议的可恢复 Pending. 不用进程邮箱临时等待代替持久关联.

关联至少可恢复 collection/Intent/Execution/Operation, provider/account scope, 核验方式版本及稳定报告身份映射.
correlation 不是凭据, 不复用 Worker lease token 作为第三方认证. 未知关联返回可诊断的入域拒绝,
不能猜测最近一个 Waiting Execution; 若声明早到 inbox 协议, inbox 的保存/绑定和重放单独满足认证与原子一致性.

可信 Adapter 按 provider 的版本化协议核验签名/MAC, 账户/受众/端点绑定, 事件身份, 正文完整性和重放限制;
认证失败不得形成核心 Report. 重放窗口不能让合法晚到完成永久无法恢复: provider 必须能以可验证方式重投,
或提供经认证查询/已核验持久 inbox. 不能为了接收晚到消息而跳过验签.

Adapter 通过验证后转换为同一逻辑 Report Envelope, 重投保留 source_scope/report_id/kind/body.
核心继续验证持久关联, Operation, 值域和来源资格. 网络中同事件的签名/重投时间可改变, 逻辑证据不改.
同事件正文变化按冲突保存, 不能靠去重缓存直接覆盖/丢弃. 保留用于追溯的验证版本和依据引用, 但不在日志泄露凭据.

持久回调发送方/inbox 只有取得 Durable Stored 确认后才能停止重投; 回执丢失用原 Report 重投.
若外部平台不支持重投且无查询, Handler 须自行提供可靠 inbox, 否则应披露只能保守 Unknown 的可恢复性限制.
Worker 已释放, lease 已到期, Coordinator 已重启不撤销关联; 完成可以先于 Pending. Closed/已替代时合法证据仍可保存,
但不重开 Intent, 不越过当前结果资格. 关联与去重材料随 Intent 保留, 首版不做 TTL 清理.

迟到 Pending 不将已解决尝试回退到 Waiting. 不假定所有外部平台都支持回调, 重投或查询.
Report 的稳定身份, 内容相等, 冲突保留和 Stored 确认遵守 [消息契约](persistent-values-and-messages.md):
发送方不因本地接收时间改变而生成新身份, 内容 hash 不替代报告身份, 持久化确认不等于 Outcome 接受.

## 6. 资源身份与执行环境

资源约束必须明确参与授权与调用. 不同外部系统的恢复, 取消和重试能力分别由 Operation 协议定义.

不可变定义须能解释操作的逻辑目标和硬约束; 启动快照保存本次具体资源绑定及协议解释.
逻辑目标不应仅是对执行设备有歧义的裸路径, 进程 PID 或易失浏览器 tab ID.
Operation 定义如何解析稳定资源引用, 明确身份, 账户/设备/存储域, 必要版本, 凭据引用及重启可恢复性.
资源绑定随尝试保存, 但不能借新尝试把同一逻辑目标换成另一个设备上的同名对象.

调度可以使用偏好和能力提示筛选候选; 安全要求必须作为硬约束被权威启动路径重验.
授权前由可信资源登记/Adapter 核验 Worker 的环境, 权限和目标匹配; 合规 Worker 调用前核验实际资源仍匹配快照.
匹配失败不调用, 配置/资源暂缺保持 Prepared 或已有事实, 不仅凭调度超时制造 Failed.
调用前核验无法锁定外部世界, 真正的资源版本检查, 条件写或幂等必须由资源协议提供.

跨设备分配允许两类情况: 资源本来可由多个设备等价访问, 或操作显式绑定某设备并只在其合格 Worker 上执行.
复制文件, 重建浏览器会话或切换账户不作为 Runtime 默认恢复步骤; 如 Operation 声明支持, 须有独立的版本化协议与验收.
两个独立 Intent 修改同一外部资源时, 使用资源侧版本竞争/锁/业务协议解决冲突, 不以各自 Intent key 实现全局业务去重.

## 7. 首版停止与重试策略

首版使用两个最小停止/重试策略:

| 策略 | 明确确定失败后的决定 |
| --- | --- |
| StopOnFailure | 不再建立后续尝试; 满足结果守卫时同事务接受 Failed |
| RetryOnce | 最多两个已建立尝试; 首次失败且存在适用的独立安全依据时继续, 否则停止 |

第二次尝试已建立即消耗额度, 不因启动失败或未调用回收计数. 已授权未知的第二次尝试不能仅因额度耗尽变成 Failed.
第一尝试已知失败而幂等窗口后来失效时, 可以由 StopKnownFailure 在新事务内接受原错误;
不是伪造第二次失败, 也不重新写已保存报告. 报告接收时已经满足停止条件则与完成/History 一起原子终结.

Unknown, Pending, NotFound, 存储/传输错误不映射为确定 Failure. 即使策略已决定停止, 仍要求明确合格错误, 当前结果资格,
无未解释旧成功/冲突以及无已授权未知风险. 不能以策略预算压过这些守卫. 安全依据失效后存在未知风险时保持 Open.

首版 Failure 统一作为可评估一次重试的明确错误; 更细的业务错误可在 Operation 合法结果里表示,
不从自由文本或 HTTP 状态码猜测安全性. 不提供运行中预算/策略修改命令, 初始策略快照不可变.
退避仅安排候选的 not-before 时间, 不授予许可也不延长幂等窗口; 首版可以立即再次评估, 不承诺自动重试时限.
部署的限流/唤醒配置不改 IEO 事实, 不把"调度没及时执行"转换为 Failed.

## 8. 代表性 Operation 协议样例

以下 Identity 展示不同外部协议如何共用 IEO 核心, 不代表已有内置驱动.
字段使用受限值, 资源/凭据为稳定引用, 不保存函数, PID 或凭据正文.
每个样例仍遵守授权先于调用, 可信 Report, 独立结果资格与唯一 Outcome, 不引入额外 IEO 状态.

### 8.1 `api.request.v1`: LLM / API 请求

- 不可变输入: provider/account/endpoint 引用, 请求参数, 结果解释版本; 不从当前默认账户补齐旧 Intent.
- 启动绑定: 原目标, Handler/协议版本, 外部 key 的 scope/派生与有效期; provider 请求 ID 后取得时另有早到关联协议.
- Success: 契约合法响应, 必要 provider 请求关联与正文/产物引用. LLM 正文是已完成事实, 复用不等于重生成同一文本.
- Failure: provider/Handler 明确确认的契约错误. 客户端超时, 连接中断或 HTTP 状态码本身不证明未执行.
- Pending/query/callback/idempotency 逐项按实际 provider 声明. 不支持去重或查询时, 完成与报告之间中断可能保持 Unknown.
- 验收: 同 Intent 原 key 重投, 不同 Intent key 分离, 原账户/窗口不被升级改变, 响应丢失后不盲目再收费.

### 8.2 `human.approval.v1`: 持久审批

- 不可变输入: 审批主题/材料版本, 响应者权限域和目标审批服务; 一次审批的业务身份不由在线进程生成.
- 启动前保存 correlation 与核验协议. 首次建立外部审批后形成 Pending; 外部创建与绑定不能原子时,
  服务须接受预分配关联, 或 Adapter 提供满足原子保存/重放要求的 inbox, 不能先创建再仅记在邮箱.
- 结果为 `{decision: "approved" | "denied", approval_ref: ..., decision_ref: ...}` 的逻辑对象,
  两种选择均为 Success; 对响应者无权, 缺少原审批或正文格式错误, 不形成可信完成.
- 原审批的合格决定须由服务协议提供稳定身份与不可覆盖的查询/回调证据. 两份合法矛盾决定保留冲突,
  不按最新消息或最高接收时间选定. UI 已展示, 已点击或通知已送达均不等于 Outcome.
- 所有进程退出后查询/回调仍定位原审批; 创建响应丢失不能无条件再开一份审批.
  Runtime 等待超时不等于 denied; 若业务需要过期结果, 另行定义服务证明与 Operation 语义.
- 验收: 拒绝为正常结果, 完成先于 Pending, 原 Worker 丢失后完成, 无权响应拒绝, 矛盾事件不覆盖.

### 8.3 `file.replace_if_version.v1`: 条件替换文件对象

- 不可变输入: 设备/volume/object 稳定引用, expected_version, 新内容的稳定引用与完整性摘要.
  裸路径仅能在该资源域内解析, 不能把另一设备同名路径当成原对象.
- 声明支持的资源协议须原子检查对象版本并完成条件修改. 结果可为
  `{applied: true, object_ref: ..., version: ..., digest: ...}` 或契约定义的
  `{applied: false, reason: "version_mismatch"}`; 二者是本样例的正常 Success 数据, 不把业务条件未满足猜成基础设施
  Failure.
- 若宣称完成后可恢复, 资源协议须保留与原操作 key 绑定的 receipt/查询依据,
  或提供其他可证明结果的机制. 本地 rename, mtime, 当前内容相同均不自动提供此依据.
- 不默认文件系统具有版本 CAS, receipt 与业务写入原子保存, 跨 volume 原子性或持久幂等.
  缺少声明条件时不能提供本样例的强协议; 可另定义较弱 Operation 并披露 Unknown 风险.
- 验收: 错设备/对象不调用, 两个 Intent 竞争同一版本按资源协议处理,
  写入后报告前崩溃按 receipt 恢复或保持 Unknown, 不借重试覆盖他人新版本.

### 8.4 `device.command.v1`: Browser / Device 动作

- 不可变输入: 稳定设备/账户/会话引用, 目标对象, 动作及前置条件; 临时 tab ID 不能是唯一恢复材料.
- 绑定到合格环境并在调用前重验. 会话不能重建则保持资源不可用/既有事实, 不换到默认浏览器继续动作.
- Success 必须有契约合格的动作完成证据及必要结果. 页面状态符合期望可能由其他操作造成,
  不能仅凭它证明原付款/点击/设备命令已经完成; 若目标状态本身就是目标, 应另定义该语义的 Operation.
- 无外部 key/receipt/query 保证的不可逆动作, 连接中断后保持 Unknown, 不以 UI 自动化的可重放脚本推导安全重试.
- 验收: 会话丢失, 错账户/设备拒绝, 相同页面不替代原证据, 已获许可旧会话可能仍运行,
  取消只终结 Intent, 不伪造资源已停止.

## 9. 验收场景

| 触发                                    | 必需行为                                                           | 抽象/工程检查                                                                      |
| --------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| 启动授权回复丢失                        | 原 token 取回同一 grant/Handler/关联; 不再次授权                   | lostAuthorizationReplyUsesOriginalBindingTest; 真实传输重投                        |
| 回调丢失/回执丢失                       | 核验过的原 Report 重投, 最多保存一次同内容证据                     | lostCallbackRedeliveredAfterRestartTest; provider/inbox Adapter 测试               |
| Worker 重启                             | 新 incarnation 不接续旧调用许可; 旧证据仍可认证                    | recoveryRestartRejectsOldGrantTest; Worker 协议测试                                |
| 已知失败后安全窗口过期                  | 不能重调用; 具备终结资格时提前停止                                 | earlyStopWhenIdempotencyExpiresTest                                                |
| 窗口过期但结果 Unknown                  | 保持 Open, 不伪造确定失败                                          | unknownCannotStopAfterWindowExpiresTest                                            |
| 查询不支持/认证失败/关联不匹配          | 不形成可信完成事实                                                 | 原 Pending/query/callback 场景; 真实 Adapter 测试                                  |
| 两个独立 Intent                         | 绑定, 幂等键, 报告与结果不串线                                     | [双 Intent 模型](../quint/beamletMultiIntent.qnt); 另需 SQL/Adapter 并发符合性测试 |
| Tool Call 多依赖                        | 按稳定身份读取每项 Outcome; 重启从原清单重建                       | [调用方组合契约](multi-intent-and-tool-calls.md); 清单由调用方持久保存             |
| 无兼容 Handler 或能力不支持             | 保持 Prepared/等待, 不套用新语义或因缺配置制造 Failed              | Handler 兼容/能力场景; 真实登记与配置测试                                          |
| 同名路径不同对象, 或调度后资源/权限变化 | 授权及调用重验, 不静默换设备/账户/对象; 合格换 Worker 仍访问原目标 | 资源匹配场景; 真实 ACL/环境测试                                                    |
| 旧 Handler 协议升级                     | 原账户, key 映射, 窗口与等待关联保持解释                           | 快照与原幂等窗口场景; 旧数据/Adapter 兼容测试                                      |
| 审批或设备会话中断                      | 按原审批关联恢复; 丢失临时 tab 或当前 UI 相同不证明原操作完成      | Pending/回调抽象场景; 具体服务/设备协议测试                                        |
| 输入含运行时对象或受限值边界越界        | 在持久化与调用前拒绝; 两后端往返保持逻辑值                         | codec/真实后端测试                                                                 |

真实 Adapter 还须验证原 key 映射, 账户/协议切换, 边界时限与网络延迟, 签名轮换, 重复/矛盾内容和受限值解码.
外部完成到 Report 提交之间中断时, 有可靠查询/重投则按原证据恢复, 否则保留 Unknown.
[资源匹配模型](../quint/beamletResource.qnt) 检查有界环境/绑定关系,
[共享资源模型](../quint/beamletSharedResource.qnt) 检查原子 CAS + receipt 条件下的版本竞争;
这些前提不自动适用于普通文件系统或 Browser.

抽象检查的范围与运行方式见 [Quint 检查指南](../quint/README.md).
真实资源 ACL, 签名, 外部保留期, 持久性与 SQL 后端仍需独立工程验收.
