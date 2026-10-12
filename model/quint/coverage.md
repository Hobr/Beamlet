# 模型覆盖与边界

本文集中说明当前模型检查什么, 依赖什么, 以及最近一次模型验收的证据. 运行方式见 [Quint README](README.md), 产品行为见
[首版范围](../spec/first-release-scope.md).场景可达, mutation 可检出与抽样无违规各提供不同证据, 均不构成穷尽证明.

## 需求与检查位置

| 契约要求 | 模型抽象 | 主要场景或性质 |
| --- | --- | --- |
| 唯一且不可变的 Outcome; Closed 当且仅当存在 Outcome | 独立提交历史, 首次结果与当前账本对照 | outcomeUnique, outcomeImmutable, closedIffOutcome |
| 启动前持久授权, 重启不继承许可 | Worker incarnation, Execution generation, grant 与实际调用见证 | startupsQualified, invocationsAuthorized, oneCallPerExecution |
| 到期确认后不因回拨复活 | 持久 invalidated 与独立失效历史 | expirySticky; strict 场景 |
| lease 与结果资格分开, 合法迟到报告可保存 | current, 授权/报告, Waiting/Unknown/Resolved | pendingSurvivesWorkerLossTest, latePendingCannotRegressTest |
| Unknown, 负面查询不自动授权重试或失败 | 可信排除依据, 风险判断, 原始证据守卫 | replacementsSafe, commitsQualified; negativeQueryRetry, unknownFailure mutation |
| 旧成功与矛盾证据不丢失 | 原始报告, 独立冲突, 提交时证据见证 | failureRespectsOldSuccess, terminalConflictsResolved |
| 同身份同定义复用; 异定义拒绝; Closed 返回原业务值 | 原子提交目录, 不可变 Definition, opaque 业务值 | stableSubmissionReplayTest, conflictingDefinitionTest, closedSubmissionReturnsBusinessValueTest |
| 回调不依赖原 Worker 或查询能力 | 启动授权时保存 CompletionBinding, 独立 ByCallback 来源 | releasedWorkerCallbackWithoutQueryTest, callbackCorrelationBeforeInvocationTest |
| Handler 兼容性与能力条件 | Operation Identity, 实现/协议/能力快照 | incompatibleHandlerDisabledTest, unsupportedQueryDisabledTest, handlerLaunchesSound |
| 幂等上下文稳定, 原保证不能被新声明延长 | Intent context, 原/新窗口, 不可回退的抽象 contractTime | retryContractsSound, retryCallsOriginalContract, newHandlerCannotExtendOriginalWindowTest |
| 合格失败与终结原子接受; 停止不能掩盖不确定性 | StopOnFailure / RetryOnce, 原定义和停止见证独立重算 | normalAcceptanceAtomic, policyStopsSound, unknownCannotStopAfterWindowExpiresTest |
| 持久事实读取与工作重发现 | 一致快照与 Prepared/Waiting/Unknown 候选投影 | factReadsSound, preparedWorkRediscoveredTest |
| 崩溃, 丢包, 重投与上述能力组合 | recoveryStep 组合正常与故障动作 | lostCallbackRedeliveredAfterRestartTest, recoveryRestartRejectsOldGrantTest |
| 独立执行与无处置参考行为一致 | 测试专用账本嵌入和守卫/更新投影 | projectionEquivalent, projectionSafety |
| 多 Agent 独立提交, 跨 Intent 不串写 | 两个完整账本, 带 scope 的消息, 独立 before/after 见证 | directoryScoped, scopeIsolation, multiExecutionSafety |
| 一个 Worker 会话故障影响全部 Intent 槽 | 共享 alive/incarnation, 各 Intent 的易失 local slot | sharedSessionsSafe, transportScoped |
| Tool Call 收齐原依赖后汇总, 重启恢复关联 | 调用方持久 manifest/aggregate, 易失 refs/results | callerFactsScoped, toolRoundsSound; multi 场景 |
| 单步部分 Success 驱动下一 Intent, 决策先于发送且恢复不改身份 | 三个完整账本, 调用方持久 ProgressRecord 与易失结果缓存 | decisionSourcesSound, decisionStable, nextManifestSound, dispatchOrdering; continuation 场景 |
| Claim 持久分配与回复送达分离 | 请求/回复集合, 不可变分配关联, Worker 仅持有已收 token | allocationSound, claimDeliverySound, claimSessionsSound |
| 设备/账户/对象匹配与绑定稳定 | 原正常账本 + 实际环境/授权绑定/调用观察 | resourceBindingsSound, resourceCallsSound |
| 同事务 History 提交关联 | 两 Coordinator 草稿, 提交组/组内事件位置, 原账本前后快照 | historyGroupsSound, historyStateAtomic, historyCommandsSound |
| 三并发原依赖完成两项后重启 | 单轮三 slot, 易失引用/读取清空后按原身份重建 | tripleManifestSound, tripleCompletionSound, triple 场景 |
| 两 Intent 竞争同一外部版本 | 独立账本 + 共享对象 CAS/receipt, 资源写入与 Outcome 分开 | objectWritesSound, objectEvidenceSound |
| 后置协调, 命令重投, 取代, 规则退役与撤销 | 完整参考账本, 判断版本, 原命令结果和显式作用范围 | repeating/conflicts 场景及 properties/reconciliation, commands, withdrawal |

确定场景位于 [scenarios/](scenarios/), 反例目标见 [mutation 索引](counterexamples.md).
首版执行, 正常, 恢复, 多 Intent, 部分推进与五项补验入口不包含治理类型.
部分推进的调用方决定不等于 Beamlet 的后置协调/治理决定. 完整参考仍保留执行/协调/治理组合检查,
命令与治理账本内部尚未进一步拆分.

## prompt 的 12 个故障场景

本表对照 [prompt.md](../../prompt.md) 的分布式恢复清单. "直接场景"指可执行抽象场景,
不是 SQL/网络/具体 provider 验收. 五项补验的实际检查与新增数量见下文.

| # | prompt 场景 | 当前证据与结论 | 剩余边界 |
| --- | --- | --- | --- |
| 1 | Intent 持久化, 尚未派发时 Coordinator 崩溃 | submittedIntentBeforeExecutionSurvivesCoordinatorRestartTest 直接检查已提交 Intent 在尚无 Execution 时恢复推进; preparedWorkRediscoveredTest 检查 Prepared 重发现 | 真实扫描/通知全丢验收仍待实现 |
| 2 | Execution 已创建, Worker 未收到任务 | executionBeforeDispatchSurvivesCoordinatorRestartTest, lostReplyReplaysOriginalAllocationTest 与原授权丢回复场景 | Claim 分配/响应已独立补验; 真实 Transport 与 SQL 提交确认仍待实现 |
| 3 | Worker 收到任务, 执行前崩溃 | restartedWorkerCannotInheritGrantTest, recoveryRestartRejectsOldGrantTest; 新 incarnation 不继承旧 grant | 不由崩溃推断旧调用一定未发生; 自动继续仍依赖原尝试的安全条件 |
| 4 | 外部完成, Outcome 未提交 | lostReportAndLostAckTest, lostCallbackRedeliveredAfterRestartTest; 重投/回调按原关联提交 | 没有回执/查询或可重投来源时可能 Unknown, 不以完成后的当前资源状态冒充原证据 |
| 5 | Outcome 提交, Agent 未获通知 | closedSubmissionReturnsBusinessValueTest, closedSuccessorReusedWithoutNewInvocationTest; 读取/重投复用原结果 | 通知不是可靠队列; 本表不证明逐事件通知投递 |
| 6 | A 超时, B 接管后 A 返回 | preparedReassignmentTest, expiryAndClockRollbackTest 及 fenced/repeating 场景检查旧代控制失效与迟到证据 | 未授权 Prepared 的重领与已授权尝试的新 Execution 必须分开; 无安全依据不能接管重做 |
| 7 | 两个 Execution 同时完成, 竞争 Outcome | outcomeUnique/outcomeImmutable 与 strict/repeating 终结及旧成功场景检查原子接受与两种先后顺序 | 原子存储将竞争线性化为提交交错; 不证明 SQL 锁与隔离实现 |
| 8 | Human Approval 等待期间全部 Runtime 退出 | pendingSurvivesWorkerLossTest, releasedWorkerCallbackWithoutQueryTest 检查原 Worker/Coordinator 丢失后的持久等待/完成 | 这是 Pending/回调共性, 尚非真实审批服务的完整验收; 审批身份, 权限, 外部保留与 inbox 仍是契约前提 |
| 9 | Agent 重启后再次产生相同语义请求 | stableSubmissionReplayTest, lostSubmissionReplyThenAgentCrashReusesOriginalIntentTest; 原稳定身份/定义复用 | 输入相同不自动判同一业务操作; 无 key 重投可以新建, 调用方必须保留逻辑身份 |
| 10 | 三并发 Tool Call 完成两项后 Agent 崩溃 | triple 的 restartPreservesAllThreeDependenciesTest, thirdCompletesAfterCallerRecoveryTest 等直接检查原三并发依赖 | 调用方持久 manifest 是前提; 不恢复原栈, 不保证最后一项最终完成 |
| 11 | Worker 与 Coordinator 网络分区 | recovery/multi fault step 用消息丢失, 延迟, 重投与可用性变化抽象; 原授权与结果资格分离 | 未获许可不新调用; 既有外部执行可继续, 无最终投递/重连保证; 真实 Transport 未验收 |
| 12 | Coordinator 设备永久离线, Worker 仍可用 | SPEC 明确 Authority 不可用时不能接受新的权威提交, 已授予调用/外部等待不等于权威已恢复 | 不承诺自动双写/强制接管; 完整 Authority Transfer 后置, 需要一致切点, 旧方撤权与新方激活 |

等待 Unknown, 外部永久不响应或 Authority 永久不可用是合法边界, 不是可以通过制造 Failed 消除的测试缺口.
场景 10, Claim 响应, 资源匹配, History 提交关联与共享资源条件写均为独立有界补验,
不据此声称所有资源协议或完整产品审计 schema 已验证.

## 状态与有界参数

原核心/独立执行入口有五组状态: Authority 持久账本及在线状态, Worker 易失会话, 无序消息集合, 外部资源事实, Authority
墙钟. 正常/恢复入口增加 `usage`, 保存提交目录, Handler/回调绑定和观察. 正常入口最多保存两个目录项, 但仅完整展开首个
Intent.

多 Intent 入口同时展开两个完整执行账本, 状态为:

| 状态 | 含义 |
| --- | --- |
| multiStore | 权威提交目录, 各 Intent 的 ledger/use, 共享可用性及契约时间 |
| sharedWorkers | 每个 Worker 的 alive/incarnation, 以及各 Intent 的易失槽; 崩溃同时清空该进程全部槽 |
| multiNetwork | 带 Intent 作用域的 grant/report/receipt 与带 Agent 路由的提交请求/回复 |
| resources | 各 Intent 独立的外部事实; 完成不直接改变权威 Outcome |
| multiClock | 可前跳/回拨的 lease 墙钟 |
| callerRounds | 调用方持久依赖清单, owner 和汇总结果 |
| agentLocals | 重启时丢失, 可重新解析/读取的引用与结果缓存 |
| scopeObservation | 仅用于隔离检查的真实转换前后快照 |

原并发实例的界限为两个 Intent, 两个 Agent, 两个 Tool Call, 两个共享 Worker; 每 Intent 最多两个 Execution.
单 Intent 模型同样最多两个 Worker/Execution.时钟 0..6, TTL=2, incarnation≤2, 每 Execution generation≤3,
Report/协调 Command ID 域为 1..4.达到身份边界后禁用新动作, 不重用旧身份.
账本和审计列表仍可增长, 因此这是参与者/身份域有界, 轨迹长度受限的模型.

Report/Outcome 的整数业务值只表达相等与冲突. 并发模型故意复用相同局部 Execution/report/token 数字来检查 scope;
回调关联的算术表示只在本有界域内单射, 不规定产品编码.
`registered`, `scopeObservation`, 首次结果, 提交/授权/替代快照等是验证见证, 不规定公开字段或 SQL schema.

部分推进入口将 Intent 域扩为 1..3, 保留两轮/两个 Agent, 但固定由 Agent 1 拥有一个持久决策槽.
增加 `progress`: 决策记录保存步骤/规则版本, 原轮次/消费 slot/Intent/完整 Outcome 与下一轮请求定义/key.
`commits` 独立保存最初提交见证; 注册/汇总时的 restart 次数与重启后的读取只检查覆盖, 不参与授权.
Agent 崩溃只清空易失局部信息, 持久决定和两轮清单仍保留; 此处假定调用方存储有原子提交与持久性.
`i*10+execution` 在 Intent=1..3, execution=1..2 范围仍单射, 不证明真实 correlation 编码安全.

### 五项补验的独立状态

这些入口复用现有纯规则和账本, 保留旧实例. 五个模型分别运行, 没有检查五项扩展的全状态积.

| 入口 | 新增/复用状态与界限 | 抽象收窄 |
| --- | --- | --- |
| beamletClaim | 一个 Intent, 两 Worker/Execution, generation 至多 3; claimJournal 保存原分配, claimWire 保存请求/回复和送达观察 | 不可用/过期/竞争失败不分配第二 token; 旧回复接收不是当前权限, 收件检查 incarnation, 启动仍原子重验 |
| beamletResource | 原正常账本, 一个逻辑目标, 两设备/账户/对象/协议值; 环境最多变化 4 次, 每 Execution 保存 binding | 环境是受信输入, 固定目标为有界例子; 授权及实际调用检查确切目标, 不证明实际 ACL 或远端检查与调用原子性 |
| beamletHistory | 一个 Intent, 两 Coordinator 草稿, 至多 6 个提交组; group 保存 actor/时间/版本/命令/前后账本与增量 Audit | 选择创建/领取/授权/报告/终结与重复报告; 组序号和事件列表位置表达逻辑次序, 完整快照/committed 是检查材料, 非物理 schema |
| beamletTriple | 三个完整 Intent, 两 Worker/Execution, 一 Agent/一轮三 slot, 复用 multi 状态 | 三项均由原 manifest 提交; 前缀两项已成功后重启, 无新决定槽或通用依赖图 |
| beamletSharedResource | 两完整 Intent, 两 Worker/Execution, 一个对象和初始版本 0, scope/key 绑定 receipt | 外部原子 CAS + receipt 是前提; 业务值 1/2 分别抽象 applied/version_mismatch, 两者均 Success; A 的 RetryOnce 仍受恢复理由/原窗口约束 |

History 草稿只在本地可见, commit 时对原快照/守卫/时间重新检查; 状态和事件同一步公开, 回滚只丢草稿.
比较草稿时间与提交时间相等是本例的保守收窄, 真实实现按取得事务保护后的时间重验, 不要求两次时钟采样必相等.
Clock 回拨的确定场景检查组次序而非 timestamp 仲裁; 不能把 actor 整数或固定 version=1 当真实认证/升级证明.
共享资源的 executeObject 在已有合法调用后执行资源事务并产生外部结果, Report/Outcome 在另一步提交.
原 key replayObject 检查已保存 receipt 的资源协议重放, 不创建新尝试; 另有真实新 Execution 重试复用 receipt 的确定场景.
目标支持这种协议才可用本例, 普通 rename, 当前文件内容或 Browser 页面状态都不是原操作 receipt.

## 外部保证与抽象收窄

- Worker 合规, 遵守持久授权协议; 不模拟 Byzantine 伪造. 消息可延迟, 乱序, 重复和丢失; 已提交权威事务不回滚.
  不假定最终投递, 人工最终响应或公平调度.
- 外部真实调用/完成与 Runtime 知识分开. 旧实例获许可后可能在 lease
  到期或取消后才调用外部; 拒绝其控制请求不能证明外部停止.
- `ALLOW_REPEAT=true` 表示明确接受重复风险. fenced 实例的可信资源协议能永久排除旧尝试未来执行且确认尚未发生,
  强于一般单调 token; 仅递增 generation 不提供这项外部保证.
- 正常入口把 Handler 能力, 回调核验, 外部协议和幂等窗口作为已核验事实.`verified` 不证明真实验签; correlation
  不充当凭证. contractTime 是不可回退的资源时间抽象, lease 墙钟回拨不延长保证. 真实网络延迟和资源时限必须另行验证.
- RetryOnce 表示最多两个已建立尝试; 已知失败且无法安全继续时可提前停止. Unknown, 冲突和旧成功仍阻止不合格 Failed.
  当前只表达最小停止/继续策略, 不建生产预算和退避算法.
- 读取是已提交一致快照, 发现只返回候选. 模型没有分页, 索引, 容量, 通知实现或调度公平性.
  原单 Intent/multi 实例仍合并 Claim 与得知 token; 独立 claim 实例展开原分配与回复恢复, 不扩大原实例的交错覆盖.
- 原多 Intent 的外部资源事实彼此独立; shared 实例另检查声明 CAS/receipt 条件下的同对象竞争. 调用方持久
  manifest/aggregate 是前提; Pending/Unknown 不满足依赖, 示例等待全部 Succeeded/Failed/Cancelled, 不隐式取消兄弟或跨
  Intent 回滚. 部分推进另检查从原轮次某一已读 Succeeded 驱动 C; 不将 A/B 误判收齐, 不取消兄弟. 决策提交, 后续清单,
  Beamlet 提交是三个可恢复步骤, 没有跨存储共同事务. 仅检查单步/单 owner 的固定规则与一个结果消费; 不验证随机/LLM
  决策重算或多实例并发决策. 汇总完成不保证随后 Agent 副作用只执行一次.
- 投影检查仅对照无协调处置的普通守卫和转换, 不外推为所有治理行为或参数的等价证明.

## 后置扩展的模型选择

协调/冲突模型保留已确认语义, 但下列抽象不是产品最终协议:

- 主体, 规则, 权限, 逐项采用/排除和撤销依据均由可信输入给出, 不验证真实 ACL, 规则源码或外部依据.
  防御性冲突前缀允许已核验来源给出矛盾报告, 用于检查规则; 不声称正常资源生成器会产生这些事实.
- 判断版本只用于检测新决定的审查过期, 版本相同仍须核验具体条件. 模型的相关变化投影是保守选择;
  已接受处置不因自己的版本递增立即失效, 新证据/资格变化仍需重新判断.
- 冲突处置保守要求覆盖每个历史冲突尝试的全部已存报告及主报告, 不规定产品必须将无关材料纳入.
  全部排除后结果仍未知; 原始 Knowledge, 报告与历史冲突不被覆盖.
- 决定身份用不可删除列表位置抽象. 重新处置已判断报告须显式引用当前历史绑定; 当前绑定先按取代/撤销关系折叠,
  再核验适用范围. 这不要求产品以事件重放恢复状态.
- 自动规则以明确 id/version 和接受时定义解释; 登记输入可多版本并存, 普通退役只阻止新提交, 不撤销历史处置或推进判断版本.
  退役仅有独立观察, 不模拟真实注册表部署或全局审计存储.
- 范围撤销仅移除指定当前绑定, 不恢复更早处置, 不生成 Outcome 或重试许可. 模型保守限定新撤销于 Open
  且当前仍适用的非空范围; Closed 的历史纠正协议尚未确定. 撤销与协调共用命令身份域, 重投不转向后来处置.
- 新命令和原结果读取分别验证当前权限; 成功与明确领域拒绝共用身份域, 后续条件变化不重执行原请求.
  格式错误, 未提交数据库异常及清理协议没有被当作领域命令结果建模.

Q78 的撤销专属授权区别尚未补入 Quint 场景; 现有扩展检查不能作为该项授权要求已经验证的证据.

## 最近一次模型验收

本次五项补验后重新执行全部类型入口, 正常场景与 mutation, 原执行/并发/部分推进回归保留.
下表将本次五项补验与此前部分推进/并发采样分开:

| 检查 | 结果 |
| --- | --- |
| 类型 | 33 个入口通过; History 调度修正后相关入口另复验 |
| 确定场景 | 360 个通过: strict 23, fenced 2, repeating 79, conflicts 81, normal 49, projection 5, multi 42, continuation 25, claim 12, resource 11, history 11, triple 10, shared 10 |
| 预期反例 | 97 条均产生实际不变量违规和非空 ITF; 新增 15 条五项独立反例, 原名称/BUG 编号保留 |
| 本次五项补验采样 | 13,000 条, 13 组各 1,000, seed=42, 最多 100 步, Rust 后端, 未观察到所检查 Safety 违规 |
| 检查器实跑 | 全部 67 个模拟组以每组 1 条实跑通过; 仅验证入口/参数/后端连接, 不代替有效采样预算 |
| 历史部分推进采样 | 14,000 条, seed=42, 最多 100 步, Rust 后端, 未观察到所检查 Safety 违规 |
| 历史双 Intent 采样 | 20,000 条, 最多 100 步, Rust 后端, 未观察到所检查 Safety 违规 |
| 工具与结构 | 13 个 Mix 测试通过; 162 个 Quint 文件无循环导入且各不超过 200 行 |

并发采样使用 seed=42 的 15,000 条及 seed=123 的 5,000 条, 四线程/进程, 最多三个并行任务.
前者独立 Agent 主组 10,000 条, 五个定向组各 1,000; 后者五个定向组各 1,000.
这些双 Intent 采样为历史证据, 本次未重新运行全部历史采样组.
当前默认全量模拟预算为 67 组/91,000 条, 不是本次已经执行的数量. 本次未全量重跑历史采样.

| 并发起点 | step | 检查侧重 |
| --- | --- | --- |
| independentInit | healthyStep | 两个 Agent 独立提交, 完整执行并收集各自结果 |
| joinedInit | healthyStep | 单 Agent 双依赖, 回复/完成乱序与按身份汇总 |
| releasedPairInit | step | 两次真实调用与 Pending 已建立, 共享 Worker 释放后的完成/恢复 |
| unknownPairInit | healthyStep | A 合法 Unknown 时 B 独立推进 |
| retryPairInit | step | A 已合法替代并收到新 grant, B 已运行, 重试与故障交错 |
| emptyInit | step | 从空目录和空调用方清单开始的提交/执行/故障组合 |

这些前缀均由真实命令建立. healthyStep 排除故障/主动取消; step 包含故障.
恢复入口另保留 init, callbackRunningInit, callbackReleasedInit, retryPendingInit, retryAuthorizedInit;
正常入口保留四组正常前缀, 投影使用 normalInit, callbackReleasedInit, retryPendingInit.

独立 Agent 的 10,000 条观察到双方均汇总 9,835 条, 两 Intent 均调用 9,997 条, 同一 Worker 执行双方 5,056 条.
定向 seed=123 每组 1,000 条的关键见证为:

| 起点 | 双依赖汇总 | owner 重启后汇总 | 执行双方的 Worker 释放后双方明确完成 | Unknown 与另一 Closed 并存 |
| --- | ---: | ---: | ---: | ---: |
| joinedInit | 976 | 0 | 0 | 0 |
| releasedPairInit | 174 | 153 | 221 | 0 |
| unknownPairInit | 1,000 | 0 | 0 | 768 |
| retryPairInit | 130 | 120 | 21 | 193 |
| emptyInit | 114 | 114 | 0 | 12 |

计数可重叠, 前缀已成立的调用不算新进展. Closed 可包括 Cancelled; 明确完成列只计 Succeeded/Failed.
emptyInit 故障组仅 4 条观察到双调用, 因此保留正常组和合法深前缀; 浅路径无违规不能代替完成覆盖.
这些数字是覆盖见证, 不是完成概率或 Liveness 保证.

### 历史部分推进采样

五组均检查 continuationSafety, 配置四线程/进程, 最多两个并行任务.
正常主组从原轮次开始, 不是注入已完成的 C; 定向前缀均由真实提交, 启动, 报告与决策动作构成.

| 起点 | step | 轨迹 | 有原依赖 Open 时提交 C | 重启后建立后续清单 | 重启后读取 C | 重启后汇总 C | C 轮汇总 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| init | healthyStep | 10,000 | 2,883 | 0 | 0 | 0 | 3,727 |
| partialInit | healthyStep | 1,000 | 449 | 0 | 0 | 0 | 839 |
| decidedInit | step | 1,000 | 150 | 144 | 221 | 187 | 232 |
| submittedInit | step | 1,000 | 1,000 | 0 | 291 | 191 | 378 |
| closedInit | step | 1,000 | 1,000 | 0 | 273 | 173 | 484 |

主组观察到持久决定 7,474 条, 后续清单 7,464 条, C 提交 7,394 条.
partialInit 中 A 已 Success/B 仍 Open 且尚无决定; 三组故障前缀分别从决定已提交, C 已提交, C 已 Success 开始.
submittedInit/closedInit 的提交见证在前缀已成立, 不算新发送或重放覆盖;
回复丢失后原身份复用另有确定场景与换 key/定义反例.
C 汇总可以包含 Succeeded/Failed/Cancelled, 不是外部副作用成功次数.
恢复列记录重启后实际发生的注册, 读取与首次汇总动作, 不由当前 restart 次数和旧完成状态推断.
决定在前缀已提交的组不重记新决定; 正常组不含故障, 恢复见证为零符合该 profile.
以上计数可重叠, 只说明这些路径被观察到, 不给出完成概率, 公平性或 Liveness 保证.

全部类型/场景/反例日志与 ITF 位于 `/tmp/beamlet-continuation-regression`,
五组采样日志和预算摘要位于 `/tmp/beamlet-continuation-sampling`; 不把产物写入源码树.

### 本次五项补验采样

13 组各 1,000 条, seed=42, 最多 100 步, 两线程/进程, 最多两个并行采样任务.
每组检查对应完整 Safety, 下列计数来自实际日志, 可重叠, 不是完成概率.

| 模型/起点 | step | 正见证计数 |
| --- | --- | --- |
| Claim/init | healthyStep | 分配 1,000; 送达 1,000; 调用 1,000 |
| Claim/lostInit | healthyStep | 原回复丢失后的重放 1,000; 送达 1,000; 调用 999 |
| Claim/lostInit | step | 重放 348; 送达 292; 调用 61 |
| Resource/init | healthyStep | 绑定/调用/终结各 465 |
| Resource/alternateInit | healthyStep | Worker 2 按同一目标调用/终结各 1,000 |
| Resource/boundInit | step | 调用 467; 环境变化 1,000; 终结 250 |
| History/init | healthyStep | 已提交组/Outcome/报告去重各 1,000 |
| History/runningInit | step | Outcome 923; 丢弃草稿 842; 报告去重 905 |
| Triple/init | healthyStep | 三项实际调用 921; 恰两项 Closed 时未汇总 943; 三项汇总 547 |
| Triple/restartedInit | healthyStep | 重启后重新读取至少两份结果 1,000; 三项汇总 998 |
| Triple/restartedInit | step | 重启后重新读取至少两份结果 31; 三项汇总 3 |
| Shared/runningInit | healthyStep | 实际写入/mismatch/原 key 重放/receipt 查询/两项终结各 1,000 |
| Shared/appliedInit | step | mismatch/原 key 重放/receipt 查询各 1,000; 两项终结 987 |

Claim/lostInit 的分配已在前缀成立, 重放/送达/调用均在后续动作观察; token 送达不代替启动授权.
Resource/alternateInit 通过真实命令让 Worker 2 访问原目标; healthy init 可以先被错环境 Worker 领取而保持 Prepared,
因此 465 是覆盖见证, 不据此断言最终能重新分配. 环境匹配/访问能力是前提, 不是实际网络探测结果.
History/runningInit 的前三组提交已在前缀成立, Outcome/回滚/重复报告观察来自后续动作.
Triple/restartedInit 的 A/B 原 Outcome 与第三项调用已在前缀成立, 新读取由重启清空的缓存重新保存,
三项汇总须在后续完成; Closed/汇总可包含 Succeeded/Failed/Cancelled, 不全是成功.
Shared/appliedInit 的第一次写入已成立; 查询见证记录原 receipt 读取, 不必先有进程崩溃,
真实 Worker/Authority 丢失后按 receipt 恢复和新 Execution 复用原 receipt 另有确定场景.

History 初始采样曾因未领取 lease 的 worker=0 被传给 Worker 动作而产生运行错误, 此次失败不计入有效采样.
修正调度候选后增加 healthySchedulerHandlesUnclaimedLeaseTest, 重新运行两个 History 采样组和相关类型/场景/反例.
正常协议与独立不变量未因运行异常被放宽.

全量类型/场景/97 条反例日志与 ITF 在 `/tmp/beamlet-contract-regression`;
History 修正后的相关复验在 `/tmp/beamlet-contract-history-final`;
13 组有效采样日志与摘要在 `/tmp/beamlet-contract-sampling`; 检查器 67 组实跑日志在
`/tmp/beamlet-contract-runner-smoke`. 原错误复现日志单独保存在
`/tmp/beamlet-history-scheduler-red.log`, 不作为反例或通过证据.

## 工程验收边界

仍需实际实现验证: SQL 锁/隔离/持久性与响应丢失, codec 和值域预算, 可信路由与签名/ACL, 外部键无碰撞, provider
的幂等/时限真实性, 同一业务资源竞争, Worker 容量及扫描机制. 任意数量参与者, 调度公平性, 最终完成, 完整 Authority 迁移,
归档清理, Byzantine 和外部 exactly-once 均未获得证明. 当前没有 Runtime, 真实 SQL 后端或第三方 Adapter 的测试结果.
[整体架构](../spec/runtime-architecture.md), [History 契约](../spec/core-state-machines.md) 与
[执行环境契约](../spec/handler-recovery-contracts.md) 补充了工程要求. 资源匹配与 History 提交关联已有独立例子,
完整审计编码, 真实资源协议和部署协议仍未验证. 部分结果推进新增了单步有界例子, 仍不能作为任意 await_any/quorum,
无限步骤或调用方数据库实现的通用验证证据. 后续验收依赖见 [实现路线](../spec/implementation-roadmap.md);
[部分推进契约](../spec/multi-intent-and-tool-calls.md) 与本次例子相对应.
[Operation 样例](../spec/operation-handler-contracts.md) 的真实服务前提与失败窗口仍需独立工程验收;
[研究确认清单](../spec/implementation-roadmap.md) 中已确认的有界状态形状不授权依赖选型, 生产迁移或新平台框架.
