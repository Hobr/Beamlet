// Deterministic defensive scenarios sharing the bound conflict fixture.
module conflictCoverageTests {
  import conflictFixtures.* from "./fixtures"
  export conflictFixtures.*

  run completeExclusionPreservesOriginalFactsTest = resolvedConflictInit
    .expect(noConflicts(authority.durable) and authority.durable.attempts.get(1).conflict)
    .expect(authority.durable.attempts.get(1).knowledge == SuccessKnown)
    .expect(judgmentKnowledge(authority.durable, 1) == FailureKnown)
    .expect(authority.durable.reports == Set(success1, failure2, disputedFailure))
    .expect(authority.durable.commands == List(exclusionRecord) and authority.durable.outcomes == List())
    .then(finishFailure(2)).expect(commandSafety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, value: 0, exec: Current(2) }))

  run completeAdoptionCommitsAtomicallyTest = queriedConflictInit
    .then(sendReconciliationCommand({ id: 1, decision: adoption })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { id: 1, decision: adoption })).expect(commandSafety)
    .expect(authority.durable.commands.length() == 1 and authority.durable.decisions.length() == 1)
    .expect(authority.durable.phase == Closed)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, value: 0, exec: Current(1) }))
    .expect(authority.durable.reports.size() == 4 and authority.durable.attempts.get(1).conflict)
    .expect(authority.durable.history.select(a => a.kind == EvidenceReconciled).length() == 1)
    .expect(authority.durable.history.select(a => a.kind == OutcomeStored).length() == 1)

  run completeFailureCommitsAtomicallyTest = conflictInit
    .then(sendReconciliationCommand({ id: 1, decision: failure })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { id: 1, decision: failure })).expect(commandSafety)
    .expect(authority.durable.phase == Closed and authority.durable.commands.length() == 1)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, value: 0, exec: Current(2) }))
    .expect(authority.durable.attempts.get(1).knowledge == SuccessKnown)
    .expect(authority.durable.reports.contains(success1) and authority.durable.attempts.get(1).conflict)

  run omittedFailureReportCannotResolveConflictTest = conflictInit
    .then(reconcileDecision(policy, { ...exclusion, evidence: Set(discardEvidence(success1)) }).fail())

  run pickOnlyFavorableQueryCannotResolveConflictTest = queriedConflictInit
    .then(reconcileDecision(policy, { ...adoption, evidence: Set(keep(querySuccess)) }).fail())

  run registeredBasisDoesNotReplaceCoverageTest = conflictInit
    .then(reconcileDecision({
      ...policy, resolutions: Set(Set(keep(success1))),
    }, conflictDecision(authority.durable, success1, AdoptSuccess, Set(keep(success1)), Operator(1))).fail())

  run completeCoverageWithoutCheckedContractCannotResolveTest = conflictInit
    .then(reconcileDecision({ ...policy, resolutions: Set() }, exclusion).fail())

  run perItemBasisIsValidatedTest = conflictInit
    .then(reconcileDecision({
      ...policy, resolutions: Set(Set(keep(disputedFailure),
        { ...discardEvidence(success1), basis: VerifiedCompletion })),
    }, { ...exclusion, evidence: Set(keep(disputedFailure),
      { ...discardEvidence(success1), basis: VerifiedCompletion }) }).fail())

  run contradictoryKeepItemsAreRejectedTest = conflictInit
    .then(reconcileDecision({
      ...policy, resolutions: Set(Set(keep(success1), keep(disputedFailure), keep(failure2))),
    }, { ...failure, evidence: Set(keep(success1), keep(disputedFailure), keep(failure2)) }).fail())

  run sameReportCannotHaveTwoTreatmentsTest = conflictInit
    .then(reconcileDecision({
      ...policy, resolutions: Set(excludeOldConflict.union(Set(keep(success1)))),
    }, { ...exclusion, evidence: excludeOldConflict.union(Set(keep(success1))) }).fail())

  run unmentionedSecondConflictBlocksCommitTest = bothConflictsInit
    .then(reconcileDecision(policy, failure).fail())

  run bothConflictGroupsCanBeResolvedTogetherTest = bothConflictsInit
    .then(reconcileDecision(policy, conflictDecision(authority.durable,
      querySuccess2, AdoptSuccess, resolveBothConflicts, Operator(1)))).expect(commandSafety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, value: 0, exec: Current(2) }))
    .expect(authority.durable.attempts.get(1).conflict and authority.durable.attempts.get(2).conflict)
    .expect(authority.durable.reports.size() == 4)

  run newEvidenceReblocksResolvedConflictTest = resolvedConflictInit
    .then(offerCheckedEvidence(querySuccess)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .expect(not(noConflicts(authority.durable)) and oldSuccessNeedsReconciliation(authority.durable, 2))
    .expect(authority.durable.decisions.length() == 1)
    .then(finishFailure(2).fail())

  run replayDoesNotResolveNewEvidenceTest = resolvedConflictInit
    .then(offerCheckedEvidence(querySuccess)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, exclusionCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(exclusionRecord))))
    .expect(not(noConflicts(authority.durable)) and authority.durable.decisions.length() == 1)
    .expect(authority.durable.outcomes == List())

  run closedAdoptionReplayAfterRestartReturnsOriginalTest = queriedConflictInit
    .then(sendReconciliationCommand({ id: 1, decision: adoption })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { id: 1, decision: adoption })).expect(commandSafety)
    .then(crashCoordinator).expect(commandSafety)
    .then(restartCoordinator).expect(commandSafety)
    .then(sendReconciliationCommand(authority.durable.commands.head().command)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, authority.durable.commands.head().command)).expect(commandSafety)
    .expect(authority.durable.commands.length() == 1 and authority.durable.decisions.length() == 1)
    .expect(commandReplayReached)

  run oldConflictApprovalBecomesStaleOnNewEvidenceTest = conflictInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(offerCheckedEvidence(querySuccess)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, exclusionCommand)).expect(commandSafety)
    .expect(authority.durable.commands.length() == 0 and authority.durable.rejections.length() == 1)
    .expect(staleCommandRejectedReached and not(noConflicts(authority.durable)))

  run unauthorizedConflictOperatorCannotCommitTest = conflictInit
    .then(reconcileDecision(policy, { ...exclusion, actor: Operator(2) }).fail())

  run registeredAutomaticConflictRuleCanCommitTest = queriedConflictInit
    .then(reconcileDecision(policy, { ...adoption, actor: AutomaticRule({ id: 4, version: 1 }) })).expect(commandSafety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, value: 0, exec: Current(1) }))
    .expect(automaticDecisionReached)

  run automaticRuleStillNeedsCheckedBasisTest = queriedConflictInit
    .then(reconcileDecision({ ...policy, resolutions: Set() },
      { ...adoption, actor: AutomaticRule({ id: 4, version: 1 }) }).fail())

  run unregisteredAutomaticConflictRuleCannotCommitTest = queriedConflictInit
    .then(reconcileDecision({ ...policy, registeredRules: Set(rule1v1, rule2v1) },
      { ...adoption, actor: AutomaticRule({ id: 4, version: 1 }) }).fail())

  run cancellationCanCloseWithUnresolvedConflictTest = conflictInit
    .then(cancelIntent).expect(commandSafety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeCancelled, value: 0, exec: NoCurrent }))
    .expect(authority.durable.reports.size() == 3 and authority.durable.attempts.get(1).conflict)

  run currentFailureCannotIgnoreAnotherUnknownAttemptTest = grantedReplacementInit
    .then(callExternal(t2)).expect(commandSafety)
    .then(completeAtResource(2, Failure)).expect(commandSafety)
    .then(publishCompletion(t2)).expect(commandSafety)
    .then(receiveReport(failure2)).expect(commandSafety)
    .then(offerCheckedEvidence(querySuccess2)).expect(commandSafety)
    .then(receiveReport(querySuccess2)).expect(commandSafety)
    .expect(authority.durable.attempts.get(1).knowledge == NoKnowledge)
    .then(reconcileDecision({
      ...policy, resolutions: Set(Set(keep(failure2), discardEvidence(querySuccess2))),
    }, conflictDecision(authority.durable, failure2, AdoptFailure,
      Set(keep(failure2), discardEvidence(querySuccess2)), Operator(1))).fail())

  run sameIdentityChangedContentCanBeExplicitlyResolvedTest = conflictInit
    .then(offerCheckedEvidence({ ...querySuccess, id: 3 })).expect(commandSafety)
    .then(receiveReport({ ...querySuccess, id: 3 })).expect(commandSafety)
    .then(reconcileDecision({
      ...policy, resolutions: Set(Set(keep(success1), discardEvidence(disputedFailure),
        keep({ ...querySuccess, id: 3 }))),
    }, conflictDecision(authority.durable, { ...querySuccess, id: 3 }, AdoptSuccess,
      Set(keep(success1), discardEvidence(disputedFailure), keep({ ...querySuccess, id: 3 })), Operator(1))))
      .expect(commandSafety)
    .expect(authority.durable.reports.size() == 4 and authority.durable.attempts.get(1).conflict)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, value: 0, exec: Current(1) }))
}
