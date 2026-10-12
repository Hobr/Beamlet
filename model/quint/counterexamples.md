# 故意错误规则索引

97 条 mutation 用来确认指定安全检查能检出典型错误, 不表示正常模型存在这些违规, 也不代表所有错误均已覆盖.
每条从真实转换构造的合法前缀开始, 最后执行一条故意错误转换; 正常 step 不导入这些动作.
模型覆盖与假设见 [覆盖文档](coverage.md).

## 执行与组合参考: 60 条

前十条检查执行安全, 其余检查后置协调/治理及其与执行的组合. 模块名保留, 便于直接复现.

| 模块 | 主要检查目标 |
| --- | --- |
| duplicateOutcome | outcomeUnique |
| overwriteOutcome | outcomeImmutable |
| reviveExpiredLease | expirySticky |
| negativeQueryRetry | replacementsSafe |
| incarnationInheritance | invocationsAuthorized |
| grantAfterClosure | startupsQualified |
| pendingRegression | resolvedKnowledgeCoherent |
| unknownFailure | commitsQualified |
| earlyReceipt | receiptsOnlyForStored |
| oldSuccessFailure | failureRespectsOldSuccess |
| unauthorizedReconciliation | reconciliationQualified |
| unregisteredReconciliation | reconciliationQualified |
| staleReconciliation | reconciliationQualified |
| permanentReconciliation | failureRespectsOldSuccess |
| silentlyRefreshedCommand | commandExecutionMatchesRequest |
| replayExecutedAgain | commandRecordsUnique |
| overwrittenCommand | commandRecordsImmutable |
| replayWithLatestResult | commandRepliesSound |
| earlyCommandReply | commandRepliesSound |
| replayRejectedAsStale | commandHandlingSound |
| rejectedCommandExecutedAgain | commandRecordsUnique |
| rejectionContextOverwritten | rejectedCommandsImmutable |
| resultReadPermissionIgnored | commandReadAuthorized |
| cachedResultRequiresSubmitPermission | commandHandlingSound |
| permissionDenialStoredAsDomainRejection | rejectionQualified |
| rejectionReplyBeforeStorage | commandRepliesSound |
| dispositionWithoutRevision | judgmentRevisionSound |
| heartbeatBumpsJudgmentRevision | judgmentRevisionSound |
| evidenceWithoutRevision | judgmentRevisionSound |
| judgmentRevisionReset | judgmentRevisionSound |
| incompleteConflictCoverage | conflictCoverageSound |
| uncheckedConflictBasis | conflictCoverageSound |
| erasedConflictHistory | conflictHistoryPreserved |
| terminalBeforeConflictResolution | terminalConflictsResolved |
| permanentConflictDisposition | terminalConflictsResolved |
| earlyConflictReply | commandRepliesSound |
| deletedConflictReport | reconciledEvidencePreserved |
| excludedAllUsesCachedKnowledge | commitsQualified |
| excludedAllCreatesOutcome | allExcludedCommitSound |
| implicitSupersession | supersessionLinksSound |
| wrongSupersessionTarget | supersessionLinksSound |
| overbroadSupersession | supersessionLinksSound |
| supersessionRewritesOldDecision | decisionsImmutable |
| supersessionLinksNotCommitted | commandExecutionMatchesRequest |
| ruleVersionIgnored | automaticRuleVersionsSound |
| ruleConditionsFromOtherVersion | automaticRuleVersionsSound |
| automaticRequestVersionRefreshed | commandExecutionMatchesRequest |
| historicalRuleReinterpreted | automaticRuleVersionsSound |
| replayBlockedByRuleRetirement | commandHandlingSound |
| retirementClearsDisposition | ordinaryRuleRetirementSound |
| retirementBumpsJudgmentRevision | ordinaryRuleRetirementSound |
| withdrawalResurrectsOldTreatment | withdrawalScopeSound |
| withdrawalOverstepsScope | commandExecutionMatchesRequest |
| withdrawalWithoutRevision | judgmentRevisionSound |
| uncheckedWithdrawalBasis | withdrawalScopeSound |
| withdrawalCreatesOutcome | withdrawalCommandsNonterminal |
| withdrawalDeletesEvidence | reconciledEvidencePreserved |
| withdrawalReplayRetargetsNewDisposition | commandHandlingSound |
| commandIdentitySplitByOperationKind | commandRecordsUnique |
| withdrawalReplyBeforeCommit | commandRepliesSound |

## 正常使用: 8 条

入口为 [beamletNormalUse_mutations_test.qnt](beamletNormalUse_mutations_test.qnt).

| 模块 | 主要检查目标 | 故意错误 |
| --- | --- | --- |
| normalWrongResultValue | outcomeValuesEvidenced | 报告值为 1, 却将 Outcome 与提交快照同时伪造为 9 |
| normalDefinitionOverwritten | submissionIdentitySound | 覆盖同提交身份的原始定义 |
| normalCallbackBindingLost | handlerLaunchesSound | 调用后丢弃启动前持久完成关联 |
| normalExpiredIdempotencyRetry | retryContractsSound | 幂等保证过期后仍替代尝试 |
| normalSuccessNotAtomic | normalAcceptanceAtomic | 合格成功报告保存后漏提交 Outcome/Closed |
| normalContextChanged | handlerLaunchesSound | 改变 Intent 的稳定幂等上下文 |
| normalFailureNotAtomic | normalAcceptanceAtomic | 已具备停止资格却只存失败报告, 伪造 stop=false 掩盖漏终结 |
| normalExtendedIdempotencyWindow | retryCallsOriginalContract | 用新 Handler 的较长窗口绕过原幂等保证 |

最后一条独立回查实际调用时间与原 binding: 原窗口到 3, 新声明到 6, contractTime=4, 错误调用仍须被检出.
正常规则在替代, 授权及调用时验证相应条件; 新声明不能延长原外部保证.
错误结果和停止反例同时伪造摘要/快照, 检验性质能独立核对证据与原定义.

## 多 Intent 与调用方: 8 条

入口为 [beamletMultiIntent_mutations_test.qnt](beamletMultiIntent_mutations_test.qnt).

| 模块 | 主要检查目标 | 故意错误 |
| --- | --- | --- |
| multiCrossIntentReport | 报告对应本 Intent 的独立发送事实 | A 的报告写入相同局部 token 的 B |
| multiCrossIntentGrant | sharedSessionsSafe | A 的许可进入 B 的 Worker 槽 |
| multiSharedIdempotencyContext | multiExecutionSafety | B 调用时使用 A 的幂等上下文 |
| multiSiblingHistoryErased | scopeIsolation | 操作 A 时清除 B 的 History |
| multiPrematureToolJoin | toolRoundsSound | 仅一个依赖有结果就完成双依赖汇总 |
| multiJoinByNotificationCount | toolRoundsSound | 两条真实结果都关联 slot 1, 按条数误判收齐 |
| multiCallbackCorrelationCollision | multiExecutionSafety | B 保存 A 的回调关联 |
| multiLostDependencyManifest | toolRoundsSound | Agent 崩溃后遗漏原依赖清单中的 B |

跨报告反例中, B 的资源仍未完成且没有发出报告, 却被 A 的 Success 终结.
按通知数量汇总的反例确有两个终态结果, 但 slot 集合只有 `{1}`, 缺少 slot 2.
这些错误分别由指定子性质检出, 不依赖无关观察快照的不一致.

## 部分结果推进: 6 条

入口为 [beamletContinuation_mutations_test.qnt](beamletContinuation_mutations_test.qnt).

| 模块 | 独立检查目标 | 故意错误 |
| --- | --- | --- |
| continuationSendBeforeCommit | dispatchOrdering | 无持久决定/后续清单就发送 C |
| continuationReplayChangesKey | dispatchOrdering | 重启后用另一个 key 发送, 原决定仍保留 |
| continuationLostDecision | decisionStable | Agent 退出时丢弃已提交决定, 独立提交见证保留 |
| continuationConsumesWrongIntent | decisionSourcesSound | 将 A 的 Outcome 标成尚未完成的 B 并提交决定 |
| continuationLaterResultReplacesDecision | decisionStable | 后来的 B 成功覆盖已提交的 A 决定 |
| continuationReplayChangesDefinition | dispatchOrdering | 原 key 重投却换用新输入, 原决定不变 |

前缀首先满足完整 continuationSafety, 再仅以目标子性质判定违规.
换 key/定义检查实际发出的请求, 来源检查回查真实 Outcome, 不依赖无关 History/作用域观察的破坏.

## 五项独立补验: 15 条

统一入口为 [beamletContract_mutations_test.qnt](beamletContract_mutations_test.qnt), 每项三个 BUG, 原 mutation
名称和编号保留. 各前缀先满足相应完整 Safety, 错误转换仅以指定子性质判定, 不把解析/运行错误当作反例.

| 模块 | 独立检查目标 | 故意错误 |
| --- | --- | --- |
| claimReplayAllocatesNewGeneration | allocationSound | 原请求重投又领取新 generation |
| claimReplyChangesOwner | claimDeliverySound | 回复把已提交 token 换为另一 Worker |
| claimOldSessionReceivesToken | claimSessionsSound | 重启的新 incarnation 接受旧会话 token |
| resourceUsesChangedDefaultAccount | resourceCallsSound | 授权后改用当前默认账户调用 |
| resourceAuthorizesWrongDevice | resourceBindingsSound | 启动绑定错误设备/对象 |
| resourceRewritesSavedTarget | resourceBindingsSound | 改写原授权绑定, 独立 saved 仍保留原值 |
| historyStateWithoutCommitGroup | historyStateAtomic | 保存报告/终结状态却没有对应提交组 |
| historyReusesCommittedSequence | historyGroupsSound | 两份已提交组复用 sequence |
| historyDuplicateReportCreatesGroup | historyCommandsSound | 已入账相同报告重投产生空事件组 |
| tripleRestartLosesThirdSlot | tripleManifestSound | 重启时从持久 manifest 丢第三项 |
| tripleTwoResultsCompleteRound | tripleCompletionSound | 两项结果就标记三项汇总完成 |
| tripleRestartChangesSubmissionKey | tripleManifestSound | 重建时改原 slot 的 submission key |
| sharedBothWritesSameVersion | objectWritesSound | 同初始版本的两个请求均产生实际写入 |
| sharedBorrowsOtherReceipt | objectEvidenceSound | B 用 A 的 applied 回执覆盖自己的 mismatch |
| sharedCurrentContentProvesCompletion | objectEvidenceSound | B 没有原请求 receipt, 仅凭当前内容提交 Success |

History 的序号/重复组反例同时更新 committed 观察, 避免仅靠独立快照不一致判错.
共享资源的后两项检查真实资源 receipt 与已接受报告/Outcome 的关联; 不把当前对象值当作独立操作完成证据.

## 复现与判定

全部反例:

```sh
mix quint mutations --log-dir /tmp/beamlet-counterexamples
```

单条反例, 使用相应入口和模块名:

```sh
quint run model/quint/beamletNormalUse_mutations_test.qnt --main normalExtendedIdempotencyWindow \
  --init mutantInit --step mutantStep --invariant mutantInvariant \
  --max-samples 1 --max-steps 1 --seed 42 --backend rust --n-threads 1 \
  --out-itf /tmp/normal-extended-window.itf.json
```

预期退出码 1, 实际 `Invariant violated` 和非空 ITF.解析, 类型或运行错误不算检出.
ITF 包含合法初始化前缀与违规转换, 状态数量可大于两条.
[检查器](../../lib/mix/quint_checks.ex) 管理每条 mutation 的入口和输出; 检查前清除对应旧 ITF,
避免旧文件造成误报. 详细前后状态保留在运行产物中.
