// No rollback to old conclusions, partial scope preservation and independent renewed judgment.
module conflictWithdrawalTests {
  import conflictWithdrawalFixtures.* from "./withdrawal_fixtures"
  export conflictWithdrawalFixtures.*

  run withdrawalDoesNotRestoreEarlierDispositionTest = withdrawnInit
    .expect(authority.durable.phase == Open and authority.durable.outcomes == List())
    .expect(authority.durable.revision == 11 and authority.durable.decisions.length() == 3)
    .expect(historicalBindings(authority.durable.decisions).size() == 1)
    .expect(applicableBindings(authority.durable) == Set({ decisionIndex: 0, item: discardEvidence(failure2) }))
    .expect(not(excludedForJudgment(authority.durable, success1)))
    .expect(not(noConflicts(authority.durable)) and oldSuccessNeedsReconciliation(authority.durable, 2))
    .expect(authority.durable.commands.nth(2) == withdrawalRecord)
    .expect(authority.durable.reports == Set(success1, disputedFailure, failure2))
    .then(finishFailure(2)).fail()

  run partialWithdrawalPreservesUnmentionedBindingsTest = partiallyWithdrawnInit
    .expect(applicableBindings(authority.durable).size() == 2)
    .expect(applicableBindings(authority.durable).contains({ decisionIndex: 1, item: keep(disputedFailure) }))
    .expect(applicableBindings(authority.durable).contains({ decisionIndex: 0, item: discardEvidence(failure2) }))
    .expect(not(excludedForJudgment(authority.durable, success1)) and not(noConflicts(authority.durable)))
    .expect(authority.durable.outcomes == List() and authority.durable.revision == 11)

  run withdrawingKeepDoesNotRestoreOldExclusionTest = partiallySupersededInit
    .then(sendReconciliationCommand(keepWithdrawalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, keepWithdrawalCommand)).expect(commandSafety)
    .expect(not(excludedForJudgment(authority.durable, disputedFailure)))
    .expect(excludedForJudgment(authority.durable, success1))
    .expect(not(applicableBindings(authority.durable).exists(b => b.item.report == disputedFailure)))
    .expect(not(noConflicts(authority.durable)) and authority.durable.revision == 11)

  run freshDecisionCanReestablishOldConclusionTest = withdrawnInit
    .then(sendReconciliationCommand(renewedAllExclusion)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, renewedAllExclusion)).expect(commandSafety)
    .expect(authority.durable.commands.nth(3).command.id == 4)
    .expect(authority.durable.decisions.nth(3).decision.supersedes == Set({ decisionIndex: 0, reports: Set(failure2) }))
    .expect(applicableBindings(authority.durable).size() == 3)
    .expect(applicableBindings(authority.durable).forall(b => b.decisionIndex == 3))
    .expect(noConflicts(authority.durable) and judgmentKnowledge(authority.durable, 1) == NoKnowledge)
    .expect(authority.durable.revision == 12 and authority.durable.outcomes == List())

  run withdrawnOriginalCommandReplaysWithoutReestablishingTreatmentTest = withdrawnInit
    .then(sendReconciliationCommand(wideExclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, wideExclusionCommand)).expect(commandSafety)
    .expect(authority.durable.commands.length() == 3 and authority.durable.revision == 11)
    .expect(applicableBindings(authority.durable).size() == 1 and not(noConflicts(authority.durable)))

  run withdrawalReplayIsOriginalAndDoesNotChangeRevisionTest = withdrawnInit
    .then(sendReconciliationCommand(withdrawalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(withdrawalRecord))))
    .expect(authority.durable.commands.length() == 3 and authority.durable.revision == 11)
    .expect(applicableBindings(authority.durable).size() == 1)

  run withdrawalReplayAfterClosurePreservesOutcomeTest = withdrawnInit
    .then(cancelIntent).expect(commandSafety)
    .then(sendReconciliationCommand(withdrawalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(withdrawalRecord))))
    .expect(authority.durable.outcomes == List({ kind: OutcomeCancelled, exec: NoCurrent }))
    .expect(authority.durable.commands.nth(2).outcomes == List())

  run withdrawalNeedsCheckedGroundsTest = withdrawalPendingInit
    .then(receiveReconciliationCommand(policy, withdrawalCommand)).expect(commandSafety)
    .expect(authority.durable.rejections.head().result == DecisionIneligible)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.revision == 10)
    .expect(applicableBindings(authority.durable).size() == 3)

  run withdrawalWithObsoleteTargetRejectedTest = partiallySupersededInit
    .then(sendReconciliationCommand({ ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, supersedes: withdrawD0 } })).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, { ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, supersedes: withdrawD0 } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.rejections.length() == 1)
    .expect(authority.durable.revision == 10)

  run newEvidenceBeforeWithdrawalRequiresFreshReviewTest = withdrawalPendingInit
    .then(offerCheckedEvidence(querySuccess)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
    .expect(authority.durable.rejections.head().command == withdrawalCommand)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.outcomes == List())

  run withdrawalCannotCarryReplacementTreatmentTest = withdrawalPendingInit
    .then(sendReconciliationCommand({ ...withdrawalCommand, id: 4, decision: {
      ...withdrawalCommand.decision, evidence: Set(discardEvidence(success1)) } })).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, { ...withdrawalCommand, id: 4, decision: {
      ...withdrawalCommand.decision, evidence: Set(discardEvidence(success1)) } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.rejections.length() == 1)

  run newWithdrawalAfterClosureDoesNotChangeOutcomeTest = withdrawalPendingInit
    .then(cancelIntent).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 2)
    .expect(authority.durable.outcomes == List({ kind: OutcomeCancelled, exec: NoCurrent }))

  run withdrawalReplayStillRequiresReadPermissionTest = withdrawnInit
    .then(sendReconciliationCommand(withdrawalCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(withdrawalPolicy, withdrawalCommand,
      { maySubmit: true, mayRead: false })).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandForbidden(withdrawalCommand))))
    .expect(authority.durable.commands.nth(2) == withdrawalRecord and authority.durable.revision == 11)

  run withdrawalTwoOwnersRemovesOnlyTheirCurrentBindingsTest = partiallySupersededInit
    .then(sendReconciliationCommand({ ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, supersedes: withdrawBothOwners } })).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, { ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, supersedes: withdrawBothOwners } })).expect(commandSafety)
    .expect(historicalBindings(authority.durable.decisions) == Set())
    .expect(authority.durable.outcomes == List() and authority.durable.revision == 11)
    .expect(not(noConflicts(authority.durable)))

  run concurrentWithdrawalRejectsStaleSecondRequestTest = withdrawalPendingInit
    .then(sendReconciliationCommand({ ...partialWithdrawalCommand, id: 4 })).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, { ...partialWithdrawalCommand, id: 4 })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 3 and authority.durable.rejections.length() == 1)
    .expect(authority.durable.revision == 11)

  run missingWithdrawalReferencesRejectedTest = partiallySupersededInit
    .then(sendReconciliationCommand({ ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, supersedes: Set() } })).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...withdrawalPolicy, withdrawals: Set(Set()) },
      { ...withdrawalCommand, decision: { ...withdrawalCommand.decision, supersedes: Set() } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.revision == 10)

  run nonexistentWithdrawalTargetRejectedTest = partiallySupersededInit
    .then(sendReconciliationCommand({ ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, supersedes: Set({ decisionIndex: 7, reports: Set(success1) }) } })).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...withdrawalPolicy,
      withdrawals: Set(Set({ decisionIndex: 7, reports: Set(success1) })) },
      { ...withdrawalCommand, decision: { ...withdrawalCommand.decision,
        supersedes: Set({ decisionIndex: 7, reports: Set(success1) }) } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.rejections.length() == 1)

  run selfWithdrawalReferenceRejectedTest = partiallySupersededInit
    .then(sendReconciliationCommand({ ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, supersedes: Set({ decisionIndex: 2, reports: Set(success1) }) } })).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...withdrawalPolicy,
      withdrawals: Set(Set({ decisionIndex: 2, reports: Set(success1) })) },
      { ...withdrawalCommand, decision: { ...withdrawalCommand.decision,
        supersedes: Set({ decisionIndex: 2, reports: Set(success1) }) } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.rejections.length() == 1)

  run alreadyWithdrawnRangeCannotBeWithdrawnAgainTest = withdrawnInit
    .then(sendReconciliationCommand({ ...withdrawalCommand, id: 4, decision: {
      ...withdrawalCommand.decision, reviewedRevision: 11 } })).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, { ...withdrawalCommand, id: 4, decision: {
      ...withdrawalCommand.decision, reviewedRevision: 11 } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 3 and authority.durable.rejections.length() == 1)
    .expect(authority.durable.revision == 11)

  run sameWithdrawalIdChangedScopeConflictsTest = withdrawnInit
    .then(sendReconciliationCommand(partialWithdrawalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, partialWithdrawalCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIdentityConflict(partialWithdrawalCommand))))
    .expect(authority.durable.decisions.length() == 3 and authority.durable.revision == 11)

  run withdrawalDeniedBeforeDomainDoesNotReserveCommandIdTest = withdrawalPendingInit
    .then(receiveCommandWithAccess(withdrawalPolicy, withdrawalCommand,
      { maySubmit: false, mayRead: true })).expect(commandSafety)
    .expect(authority.durable.commands.length() == 2 and authority.durable.rejections == List())
    .expect(authority.durable.revision == 10)

  run withdrawalAfterRestartPreservesOriginalHistoryTest = withdrawnInit
    .then(crashCoordinator).expect(commandSafety)
    .then(restartCoordinator).expect(commandSafety)
    .expect(authority.durable.decisionSnapshots == List(wideExclusionCommand.decision,
      { ...exclusionCommand.decision, reviewedRevision: 9,
        supersedes: Set({ decisionIndex: 0, reports: Set(success1, disputedFailure) }) }, withdrawalCommand.decision))
    .expect(not(noConflicts(authority.durable)) and authority.durable.revision == 11)
}
