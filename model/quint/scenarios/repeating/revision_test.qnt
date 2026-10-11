// Deterministic scenarios using the shared fixture and real guarded transitions.
module repeatingRevisionTests {
  import repeatingFixtures.* from "./fixtures"
  export repeatingFixtures.*

  run judgmentChangesWithoutNewReportsInvalidateQueuedApprovalTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(adoptionCommand)).expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)
    .expect(authority.durable.revision == 8 and authority.durable.reports == Set(success1, failure2))
    .then(receiveReconciliationCommand(reconciliationPolicy, adoptionCommand)).expect(commandSafety)
    .expect(authority.durable.commands == List(excludedRecord) and authority.durable.revision == 8)
    .expect(authority.durable.outcomes == List() and authority.durable.decisions.length() == 1)
    .expect(authority.durable.rejections.head().result == ReviewStale({
      revision: 8, current: Current(2), reports: Set(success1, failure2),
      view: {
        base: { ...queryReview.base, reports: Set(success1, failure2) },
        decisions: List(exclusionCommand.decision),
      },
    }))

  run freshApprovalAfterOtherDispositionCanCommitTest = committedExclusionInit
    .then(sendReconciliationCommand({
      ...adoptionCommand, decision: { ...adoptionCommand.decision, reviewedRevision: 8,
        supersedes: Set({ decisionIndex: 0, reports: Set(success1) }) },
    })).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, {
      ...adoptionCommand, decision: { ...adoptionCommand.decision, reviewedRevision: 8,
        supersedes: Set({ decisionIndex: 0, reports: Set(success1) }) },
    })).expect(commandSafety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, exec: Current(1) }))
    .expect(authority.durable.revision == 10 and authority.durable.commands.length() == 2)

  run pureRejectionAuditDoesNotInvalidateOtherApprovalTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(sendReconciliationCommand(adoptionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...reconciliationPolicy, excludable: Set() }, exclusionCommand))
      .expect(commandSafety)
    .expect(authority.durable.revision == 7 and authority.durable.rejections.length() == 1)
    .then(receiveReconciliationCommand(reconciliationPolicy, adoptionCommand)).expect(commandSafety)
    .expect(authority.durable.commands == List(adoptedRecord) and authority.durable.revision == 9)

  run ownRevisionIncrementPreservesDispositionScopeTest = committedExclusionInit
    .expect(authority.durable.revision == 8)
    .expect(not(decisionScopeCurrent(authority.durable, exclusionCommand.decision)))
    .expect(not(oldSuccessNeedsReconciliation(authority.durable, 2)))
    .then(finishFailure(2)).expect(commandSafety)
    .expect(authority.durable.revision == 9)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(2) }))

  run replayAndReadDenialDoNotChangeJudgmentRevisionTest = committedExclusionInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, noAccess)).expect(commandSafety)
    .expect(authority.durable.revision == 8)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, readonlyAccess)).expect(commandSafety)
    .expect(authority.durable.revision == 8 and authority.durable.commands == List(excludedRecord))

  run duplicateReportAndHeartbeatPreserveJudgmentRevisionTest = oldSuccessCurrentFailureInit
    .then(moveClockTo(3)).expect(commandSafety)
    .then(renewLease(t2)).expect(commandSafety)
    .expect(authority.durable.revision == 7)
    .then(loseMessage(StoredReceipt(success1))).expect(commandSafety)
    .then(acknowledgeDuplicate(success1)).expect(commandSafety)
    .expect(authority.durable.revision == 7)

  run clockRollbackAndCoordinatorRestartPreserveJudgmentRevisionTest = committedExclusionInit
    .then(moveClockTo(0)).expect(commandSafety)
    .then(crashCoordinator).expect(commandSafety)
    .then(restartCoordinator).expect(commandSafety)
    .expect(authority.durable.revision == 8)
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .expect(authority.durable.revision == 9 and oldSuccessNeedsReconciliation(authority.durable, 2))

  run judgmentProjectionTracksCreationGrantExpiryReplacementAndClosureTest = init.expect(commandSafety)
    .then(createExecution(1)).expect(commandSafety)
    .expect(authority.durable.revision == 1)
    .then(claimExecution(1, 1)).expect(commandSafety)
    .expect(authority.durable.revision == 1)
    .then(requestStart(t1)).expect(commandSafety)
    .then(authorizeStart(t1)).expect(commandSafety)
    .expect(authority.durable.revision == 2)
    .then(moveClockTo(2)).expect(commandSafety)
    .then(expireLease(1)).expect(commandSafety)
    .expect(authority.durable.revision == 3)
    .then(replaceExecution(1, 2)).expect(commandSafety)
    .expect(authority.durable.revision == 4)
    .then(cancelIntent).expect(commandSafety)
    .expect(authority.durable.revision == 5)
}
