# 模型覆盖与边界

本文集中说明当前模型检查什么、依赖什么，以及最近一次模型验收的证据。运行方式见 [Quint README](README.md)， 产品行为见
[首版范围](../spec/first-release-scope.md)。场景可达、mutation 可检出与抽样无违规各提供不同证据，均不构成穷尽证明。

## 需求与检查位置

| 契约要求 | 模型抽象 | 主要场景或性质 |
| --- | --- | --- |
| 唯一且不可变的 Outcome；Closed 当且仅当存在 Outcome | 独立提交历史、首次结果与当前账本对照 | outcomeUnique、outcomeImmutable、closedIffOutcome |
| 启动前持久授权，重启不继承许可 | Worker incarnation、Execution generation、grant 与实际调用见证 | startupsQualified、invocationsAuthorized、oneCallPerExecution |
| 到期确认后不因回拨复活 | 持久 invalidated 与独立失效历史 | expirySticky；strict 场景 |
| lease 与结果资格分开，合法迟到报告可保存 | current、授权/报告、Waiting/Unknown/Resolved | pendingSurvivesWorkerLossTest、latePendingCannotRegressTest |
| Unknown、负面查询不自动授权重试或失败 | 可信排除依据、风险判断、原始证据守卫 | replacementsSafe、commitsQualified；negativeQueryRetry、unknownFailure mutation |
| 旧成功与矛盾证据不丢失 | 原始报告、独立冲突、提交时证据见证 | failureRespectsOldSuccess、terminalConflictsResolved |
| 同身份同定义复用；异定义拒绝；Closed 返回原业务值 | 原子提交目录、不可变 Definition、opaque 业务值 | stableSubmissionReplayTest、conflictingDefinitionTest、closedSubmissionReturnsBusinessValueTest |
| 回调不依赖原 Worker 或查询能力 | 启动授权时保存 CompletionBinding，独立 ByCallback 来源 | releasedWorkerCallbackWithoutQueryTest、callbackCorrelationBeforeInvocationTest |
| Handler 兼容性与能力条件 | Operation Identity、实现/协议/能力快照 | incompatibleHandlerDisabledTest、unsupportedQueryDisabledTest、handlerLaunchesSound |
| 幂等上下文稳定，原保证不能被新声明延长 | Intent context、原/新窗口、不可回退的抽象 contractTime | retryContractsSound、retryCallsOriginalContract、newHandlerCannotExtendOriginalWindowTest |
| 合格失败与终结原子接受；停止不能掩盖不确定性 | StopOnFailure / RetryOnce、原定义和停止见证独立重算 | normalAcceptanceAtomic、policyStopsSound、unknownCannotStopAfterWindowExpiresTest |
| 持久事实读取与工作重发现 | 一致快照与 Prepared/Waiting/Unknown 候选投影 | factReadsSound、preparedWorkRediscoveredTest |
| 崩溃、丢包、重投与上述能力组合 | recoveryStep 组合正常与故障动作 | lostCallbackRedeliveredAfterRestartTest、recoveryRestartRejectsOldGrantTest |
| 独立执行与无处置参考行为一致 | 测试专用账本嵌入和守卫/更新投影 | projectionEquivalent、projectionSafety |
| 多 Agent 独立提交，跨 Intent 不串写 | 两个完整账本、带 scope 的消息、独立 before/after 见证 | directoryScoped、scopeIsolation、multiExecutionSafety |
| 一个 Worker 会话故障影响全部 Intent 槽 | 共享 alive/incarnation，各 Intent 的易失 local slot | sharedSessionsSafe、transportScoped |
| Tool Call 收齐原依赖后汇总，重启恢复关联 | 调用方持久 manifest/aggregate、易失 refs/results | callerFactsScoped、toolRoundsSound；multi 场景 |
| 后置协调、命令重投、取代、规则退役与撤销 | 完整参考账本、判断版本、原命令结果和显式作用范围 | repeating/conflicts 场景及 properties/reconciliation、commands、withdrawal |

确定场景位于 [scenarios/](scenarios/)，反例目标见 [mutation 索引](counterexamples.md)。
首版执行、正常、恢复和多 Intent 入口不包含治理类型。完整参考仍保留执行/协调/治理组合检查，
命令与治理账本内部尚未进一步拆分。

## 状态与有界参数

原核心/独立执行入口有五组状态：Authority 持久账本及在线状态、Worker 易失会话、无序消息集合、外部资源事实、Authority
墙钟。 正常/恢复入口增加 `usage`，保存提交目录、Handler/回调绑定和观察。正常入口最多保存两个目录项，但仅完整展开首个
Intent。

多 Intent 入口同时展开两个完整执行账本，状态为：

| 状态 | 含义 |
| --- | --- |
| multiStore | 权威提交目录、各 Intent 的 ledger/use、共享可用性及契约时间 |
| sharedWorkers | 每个 Worker 的 alive/incarnation，以及各 Intent 的易失槽；崩溃同时清空该进程全部槽 |
| multiNetwork | 带 Intent 作用域的 grant/report/receipt 与带 Agent 路由的提交请求/回复 |
| resources | 各 Intent 独立的外部事实；完成不直接改变权威 Outcome |
| multiClock | 可前跳/回拨的 lease 墙钟 |
| callerRounds | 调用方持久依赖清单、owner 和汇总结果 |
| agentLocals | 重启时丢失、可重新解析/读取的引用与结果缓存 |
| scopeObservation | 仅用于隔离检查的真实转换前后快照 |

并发界限为两个 Intent、两个 Agent、两个 Tool Call、两个共享 Worker；每 Intent 最多两个 Execution。
单 Intent 模型同样最多两个 Worker/Execution。时钟 0..6、TTL=2、incarnation≤2、每 Execution generation≤3、
Report/协调 Command ID 域为 1..4。达到身份边界后禁用新动作，不重用旧身份。
账本和审计列表仍可增长，因此这是参与者/身份域有界、轨迹长度受限的模型。

Report/Outcome 的整数业务值只表达相等与冲突。并发模型故意复用相同局部 Execution/report/token 数字来检查 scope；
回调关联的算术表示只在本有界域内单射，不规定产品编码。
`registered`、`scopeObservation`、首次结果、提交/授权/替代快照等是验证见证，不规定公开字段或 SQL schema。

## 外部保证与抽象收窄

- Worker 合规，遵守持久授权协议；不模拟 Byzantine 伪造。消息可延迟、乱序、重复和丢失；已提交权威事务不回滚。
  不假定最终投递、人工最终响应或公平调度。
- 外部真实调用/完成与 Runtime 知识分开。旧实例获许可后可能在 lease
  到期或取消后才调用外部；拒绝其控制请求不能证明外部停止。
- `ALLOW_REPEAT=true` 表示明确接受重复风险。fenced 实例的可信资源协议能永久排除旧尝试未来执行且确认尚未发生，
  强于一般单调 token；仅递增 generation 不提供这项外部保证。
- 正常入口把 Handler 能力、回调核验、外部协议和幂等窗口作为已核验事实。`verified` 不证明真实验签；correlation
  不充当凭证。 contractTime 是不可回退的资源时间抽象，lease 墙钟回拨不延长保证。真实网络延迟和资源时限必须另行验证。
- RetryOnce 表示最多两个已建立尝试；已知失败且无法安全继续时可提前停止。Unknown、冲突和旧成功仍阻止不合格 Failed。
  当前只表达最小停止/继续策略，不建生产预算和退避算法。
- 读取是已提交一致快照，发现只返回候选。模型没有分页、索引、容量、通知实现或调度公平性。
  Claim 与得知 token 合并；领取响应丢失后的原分配恢复由存储契约规定，尚未在模型中展开。
- 多 Intent 的外部资源事实彼此独立，不模拟同一业务对象竞争。调用方持久 manifest/aggregate 是前提；
  Pending/Unknown 不满足依赖，示例等待全部 Succeeded/Failed/Cancelled，不隐式取消兄弟或跨 Intent 回滚。
  汇总完成不保证随后 Agent 副作用只执行一次。
- 投影检查仅对照无协调处置的普通守卫和转换，不外推为所有治理行为或参数的等价证明。

## 后置扩展的模型选择

协调/冲突模型保留已确认语义，但下列抽象不是产品最终协议：

- 主体、规则、权限、逐项采用/排除和撤销依据均由可信输入给出，不验证真实 ACL、规则源码或外部依据。
  防御性冲突前缀允许已核验来源给出矛盾报告，用于检查规则；不声称正常资源生成器会产生这些事实。
- 判断版本只用于检测新决定的审查过期，版本相同仍须核验具体条件。模型的相关变化投影是保守选择；
  已接受处置不因自己的版本递增立即失效，新证据/资格变化仍需重新判断。
- 冲突处置保守要求覆盖每个历史冲突尝试的全部已存报告及主报告，不规定产品必须将无关材料纳入。
  全部排除后结果仍未知；原始 Knowledge、报告与历史冲突不被覆盖。
- 决定身份用不可删除列表位置抽象。重新处置已判断报告须显式引用当前历史绑定；当前绑定先按取代/撤销关系折叠，
  再核验适用范围。这不要求产品以事件重放恢复状态。
- 自动规则以明确 id/version 和接受时定义解释；登记输入可多版本并存，普通退役只阻止新提交，不撤销历史处置或推进判断版本。
  退役仅有独立观察，不模拟真实注册表部署或全局审计存储。
- 范围撤销仅移除指定当前绑定，不恢复更早处置、不生成 Outcome 或重试许可。模型保守限定新撤销于 Open
  且当前仍适用的非空范围； Closed 的历史纠正协议尚未确定。撤销与协调共用命令身份域，重投不转向后来处置。
- 新命令和原结果读取分别验证当前权限；成功与明确领域拒绝共用身份域，后续条件变化不重执行原请求。
  格式错误、未提交数据库异常及清理协议没有被当作领域命令结果建模。

Q78 的撤销专属授权区别尚未补入 Quint 场景；现有扩展检查不能作为该项授权要求已经验证的证据。

## 最近一次模型验收

以下为文档整理前已完成的模型验收结果，文档整理不改变执行规则或安全性质：

| 检查 | 结果 |
| --- | --- |
| 类型 | 19 个入口通过 |
| 确定场景 | 281 个通过：strict 23、fenced 2、repeating 79、conflicts 81、normal 49、projection 5、multi 42 |
| 预期反例 | 76 条均产生实际不变量违规和非空 ITF；包含 8 条并发错误 |
| 并发采样 | 20,000 条、最多 100 步、Rust 后端，未观察到所检查 Safety 违规 |
| 工具与结构 | 12 个 Mix 测试通过；121 个 Quint 文件无循环导入且各不超过 200 行 |

并发采样使用 seed=42 的 15,000 条及 seed=123 的 5,000 条，四线程/进程，最多三个并行任务。
前者独立 Agent 主组 10,000 条、五个定向组各 1,000；后者五个定向组各 1,000。
没有重新运行全部历史单 Intent 采样组，不能把当前默认 69,000 条预算作为本次已经执行的数量。

| 并发起点 | step | 检查侧重 |
| --- | --- | --- |
| independentInit | healthyStep | 两个 Agent 独立提交、完整执行并收集各自结果 |
| joinedInit | healthyStep | 单 Agent 双依赖，回复/完成乱序与按身份汇总 |
| releasedPairInit | step | 两次真实调用与 Pending 已建立，共享 Worker 释放后的完成/恢复 |
| unknownPairInit | healthyStep | A 合法 Unknown 时 B 独立推进 |
| retryPairInit | step | A 已合法替代并收到新 grant，B 已运行，重试与故障交错 |
| emptyInit | step | 从空目录和空调用方清单开始的提交/执行/故障组合 |

这些前缀均由真实命令建立。healthyStep 排除故障/主动取消；step 包含故障。
恢复入口另保留 init、callbackRunningInit、callbackReleasedInit、retryPendingInit、retryAuthorizedInit；
正常入口保留四组正常前缀，投影使用 normalInit、callbackReleasedInit、retryPendingInit。

独立 Agent 的 10,000 条观察到双方均汇总 9,835 条、两 Intent 均调用 9,997 条、同一 Worker 执行双方 5,056 条。
定向 seed=123 每组 1,000 条的关键见证为：

| 起点 | 双依赖汇总 | owner 重启后汇总 | 执行双方的 Worker 释放后双方明确完成 | Unknown 与另一 Closed 并存 |
| --- | ---: | ---: | ---: | ---: |
| joinedInit | 976 | 0 | 0 | 0 |
| releasedPairInit | 174 | 153 | 221 | 0 |
| unknownPairInit | 1,000 | 0 | 0 | 768 |
| retryPairInit | 130 | 120 | 21 | 193 |
| emptyInit | 114 | 114 | 0 | 12 |

计数可重叠，前缀已成立的调用不算新进展。Closed 可包括 Cancelled；明确完成列只计 Succeeded/Failed。
emptyInit 故障组仅 4 条观察到双调用，因此保留正常组和合法深前缀；浅路径无违规不能代替完成覆盖。
这些数字是覆盖见证，不是完成概率或 Liveness 保证。

## 工程验收边界

仍需实际实现验证：SQL 锁/隔离/持久性与响应丢失、codec 和值域预算、可信路由与签名/ACL、外部键无碰撞、
provider 的幂等/时限真实性、同一业务资源竞争、Worker 容量及扫描机制。
任意数量参与者、调度公平性、最终完成、完整 Authority 迁移、归档清理、Byzantine 和外部 exactly-once 均未获得证明。
当前没有 Runtime、真实 SQL 后端或第三方 Adapter 的测试结果。
