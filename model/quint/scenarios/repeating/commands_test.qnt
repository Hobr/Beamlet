// Deterministic scenarios using the shared fixture and real guarded transitions.
module repeatingCommandsTests {
  import repeatingFixtures.* from "./fixtures"
  export repeatingFixtures.*

  run commandCommitIsAtomicTest = committedExclusionInit
    .expect(authority.durable.commands == List(excludedRecord))
    .expect(authority.durable.decisions.length() == 1)
    .expect(authority.durable.history.select(a => a.kind == EvidenceReconciled).length() == 1)
    .expect(network.contains(ReconcileReply(CommandCommitted(excludedRecord))))

  run lostReplyCrashAndReplayTest = committedExclusionInit
    .then(loseMessage(ReconcileReply(CommandCommitted(excludedRecord)))).expect(commandSafety)
    .then(crashCoordinator).expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(restartCoordinator).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)
    .expect(commandReplayReached)
    .expect(network.contains(ReconcileReply(CommandCommitted(excludedRecord))))
    .expect(authority.durable.commands == List(excludedRecord))
    .expect(authority.durable.decisions.length() == 1)
    .expect(authority.durable.history.select(a => a.kind == EvidenceReconciled).length() == 1)

  run replayAfterNewEvidenceDoesNotReapplyTest = committedExclusionInit
    .then(loseMessage(ReconcileReply(CommandCommitted(excludedRecord)))).expect(commandSafety)
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(excludedRecord))))
    .expect(authority.durable.decisions.length() == 1)
    .expect(oldSuccessNeedsReconciliation(authority.durable, 2))
    .then(finishFailure(2).fail())

  run replayReturnsOriginalResultAfterLaterFailureTest = committedExclusionInit
    .then(loseMessage(ReconcileReply(CommandCommitted(excludedRecord)))).expect(commandSafety)
    .then(finishFailure(2)).expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(excludedRecord))))
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(2) }))
    .expect(authority.durable.commands.head().outcomes == List())
    .expect(authority.durable.decisions.length() == 1)

  run adoptionReplayAfterClosureAndRestartTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(adoptionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, adoptionCommand)).expect(commandSafety)
    .then(loseMessage(ReconcileReply(CommandCommitted(adoptedRecord)))).expect(commandSafety)
    .then(crashCoordinator).expect(commandSafety)
    .then(restartCoordinator).expect(commandSafety)
    .then(sendReconciliationCommand(adoptionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, adoptionCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(adoptedRecord))))
    .expect(authority.durable.commands == List(adoptedRecord))
    .expect(authority.durable.decisions.length() == 1 and authority.durable.commits.length() == 1)
    .expect(authority.durable.history.select(a => a.kind == OutcomeStored).length() == 1)

  run sameIdChangedContentIsRejectedTest = committedExclusionInit
    .then(sendReconciliationCommand({ ...adoptionCommand, id: 1 })).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, { ...adoptionCommand, id: 1 })).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIdentityConflict({ ...adoptionCommand, id: 1 }))))
    .expect(authority.durable.commands == List(excludedRecord) and authority.durable.decisions.length() == 1)
    .expect(authority.durable.outcomes == List())

  run sameIdNewReviewIsRejectedTest = committedExclusionInit
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(sendReconciliationCommand({
      id: 1, decision: proposeDecision(authority.durable, success1, ExcludeFromJudgment, Operator(1)),
    })).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, {
      id: 1, decision: proposeDecision(authority.durable, success1, ExcludeFromJudgment, Operator(1)),
    })).expect(commandSafety)
    .expect(commandIdentityConflictReached)
    .expect(authority.durable.commands == List(excludedRecord))
    .expect(authority.durable.decisions.length() == 1 and oldSuccessNeedsReconciliation(authority.durable, 2))

  run exclusionWinsSameIdCompetitionTest =
    competingCommandsInit(exclusionCommand, { ...adoptionCommand, id: 1 })
      .expect(authority.durable.commands == List(excludedRecord) and authority.durable.decisions.length() == 1)
      .expect(network.contains(ReconcileReply(CommandIdentityConflict({ ...adoptionCommand, id: 1 }))))

  run adoptionWinsSameIdCompetitionTest =
    competingCommandsInit({ ...adoptionCommand, id: 1 }, exclusionCommand)
      .expect(authority.durable.commands.length() == 1)
      .expect(authority.durable.commands.head().command == { ...adoptionCommand, id: 1 })
      .expect(network.contains(ReconcileReply(CommandIdentityConflict(exclusionCommand))))
      .expect(authority.durable.decisions.length() == 1 and authority.durable.commits.length() == 1)

  run staleManualCommandReturnsCurrentContextTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandStale({
      command: exclusionCommand, revision: 8, current: Current(2), reports: Set(success1, failure2, querySuccess), view: queryReview,
    }))))
    .expect(authority.durable.commands.length() == 0 and authority.durable.decisions.length() == 0)
    .expect(oldSuccessNeedsReconciliation(authority.durable, 2))
}
