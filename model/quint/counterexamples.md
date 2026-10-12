# 故意错误规则索引

76 条 mutation 用来确认指定安全检查能检出典型错误，不表示正常模型存在这些违规，也不代表所有错误均已覆盖。
每条从真实转换构造的合法前缀开始，最后执行一条故意错误转换；正常 step 不导入这些动作。
模型覆盖与假设见 [覆盖文档](coverage.md)。

## 执行与组合参考：60 条

前十条检查执行安全，其余检查后置协调/治理及其与执行的组合。模块名保留，便于直接复现。

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

## 正常使用：8 条

入口为 [beamletNormalUse_mutations_test.qnt](beamletNormalUse_mutations_test.qnt)。

| 模块 | 主要检查目标 | 故意错误 |
| --- | --- | --- |
| normalWrongResultValue | outcomeValuesEvidenced | 报告值为 1，却将 Outcome 与提交快照同时伪造为 9 |
| normalDefinitionOverwritten | submissionIdentitySound | 覆盖同提交身份的原始定义 |
| normalCallbackBindingLost | handlerLaunchesSound | 调用后丢弃启动前持久完成关联 |
| normalExpiredIdempotencyRetry | retryContractsSound | 幂等保证过期后仍替代尝试 |
| normalSuccessNotAtomic | normalAcceptanceAtomic | 合格成功报告保存后漏提交 Outcome/Closed |
| normalContextChanged | handlerLaunchesSound | 改变 Intent 的稳定幂等上下文 |
| normalFailureNotAtomic | normalAcceptanceAtomic | 已具备停止资格却只存失败报告，伪造 stop=false 掩盖漏终结 |
| normalExtendedIdempotencyWindow | retryCallsOriginalContract | 用新 Handler 的较长窗口绕过原幂等保证 |

最后一条独立回查实际调用时间与原 binding：原窗口到 3、新声明到 6、contractTime=4，错误调用仍须被检出。
正常规则在替代、授权及调用时验证相应条件；新声明不能延长原外部保证。
错误结果和停止反例同时伪造摘要/快照，检验性质能独立核对证据与原定义。

## 多 Intent 与调用方：8 条

入口为 [beamletMultiIntent_mutations_test.qnt](beamletMultiIntent_mutations_test.qnt)。

| 模块 | 主要检查目标 | 故意错误 |
| --- | --- | --- |
| multiCrossIntentReport | 报告对应本 Intent 的独立发送事实 | A 的报告写入相同局部 token 的 B |
| multiCrossIntentGrant | sharedSessionsSafe | A 的许可进入 B 的 Worker 槽 |
| multiSharedIdempotencyContext | multiExecutionSafety | B 调用时使用 A 的幂等上下文 |
| multiSiblingHistoryErased | scopeIsolation | 操作 A 时清除 B 的 History |
| multiPrematureToolJoin | toolRoundsSound | 仅一个依赖有结果就完成双依赖汇总 |
| multiJoinByNotificationCount | toolRoundsSound | 两条真实结果都关联 slot 1，按条数误判收齐 |
| multiCallbackCorrelationCollision | multiExecutionSafety | B 保存 A 的回调关联 |
| multiLostDependencyManifest | toolRoundsSound | Agent 崩溃后遗漏原依赖清单中的 B |

跨报告反例中，B 的资源仍未完成且没有发出报告，却被 A 的 Success 终结。
按通知数量汇总的反例确有两个终态结果，但 slot 集合只有 `{1}`，缺少 slot 2。
这些错误分别由指定子性质检出，不依赖无关观察快照的不一致。

## 复现与判定

全部反例：

```sh
mix beamlet.check --phase mutations --log-dir /tmp/beamlet-counterexamples
```

单条反例，使用相应入口和模块名：

```sh
quint run model/quint/beamletNormalUse_mutations_test.qnt --main normalExtendedIdempotencyWindow \
  --init mutantInit --step mutantStep --invariant mutantInvariant \
  --max-samples 1 --max-steps 1 --seed 42 --backend rust --n-threads 1 \
  --out-itf /tmp/normal-extended-window.itf.json
```

预期退出码 1、实际 `Invariant violated` 和非空 ITF。解析、类型或运行错误不算检出。
ITF 包含合法初始化前缀与违规转换，状态数量可大于两条。
[检查器](../../tools/beamlet/quint_checks.ex) 管理每条 mutation 的入口和输出；检查前清除对应旧 ITF，
避免旧文件造成误报。详细前后状态保留在运行产物中。
