// Deterministic scenarios using the shared fixture and real guarded transitions.
module repeatingReconciliationTests {
  import repeatingFixtures.* from "./fixtures"
  export repeatingFixtures.*

  run automaticExclusionUsesRegisteredRuleTest = oldSuccessCurrentFailureInit
    .then(reconcileDecision(reconciliationPolicy,
      { ...manualExclusion, actor: AutomaticRule({ id: 2, version: 1 }) })).expect(safety)
    .expect(automaticDecisionReached and exclusionDecisionReached)
    .then(finishFailure(2)).expect(safety)
    .expect(failedReached)

  run automaticAdoptionUsesVerifiedQueryTest = oldSuccessCurrentFailureInit
    .then(queryExternal(1, 3)).expect(safety)
    .then(receiveReport({ id: 3, exec: 1, kind: Success, value: 0, origin: ByQuery })).expect(safety)
    .then(reconcileDecision(reconciliationPolicy,
      proposeDecision(authority.durable, { id: 3, exec: 1, kind: Success, value: 0, origin: ByQuery },
        AdoptSuccess, AutomaticRule({ id: 1, version: 1 })))).expect(safety)
    .expect(automaticDecisionReached and adoptionDecisionReached)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, value: 0, exec: Current(1) }))

  run unauthorizedManualDecisionIsDisabledTest = oldSuccessCurrentFailureInit
    .then(reconcileDecision(reconciliationPolicy,
      { ...manualExclusion, actor: Operator(2) }).fail())

  run unregisteredAutomaticRuleIsDisabledTest = oldSuccessCurrentFailureInit
    .then(reconcileDecision(reconciliationPolicy,
      { ...manualExclusion, actor: AutomaticRule({ id: 3, version: 1 }) }).fail())

  run registeredButWrongConditionIsDisabledTest = oldSuccessCurrentFailureInit
    // Rule 1 is only for trusted query completion, not a Worker completion.
    .then(reconcileDecision(reconciliationPolicy,
      { ...manualAdoption, actor: AutomaticRule({ id: 1, version: 1 }) }).fail())

  run noContractBasisIsDisabledTest = oldSuccessCurrentFailureInit
    .then(reconcileDecision({ ...reconciliationPolicy, excludable: Set() },
      manualExclusion).fail())

  run noAutomaticRulesDoesNotBlockManualTest = oldSuccessCurrentFailureInit
    .expect(not(canReconcile(authority.durable,
      { ...reconciliationPolicy, registeredRules: Set() },
      { ...manualExclusion, actor: AutomaticRule({ id: 2, version: 1 }) })))
    .then(reconcileDecision({ ...reconciliationPolicy, registeredRules: Set() },
      manualExclusion)).expect(safety)
    .expect(manualDecisionReached and not(automaticDecisionReached))

  run newEvidenceRequiresFreshReviewTest = oldSuccessCurrentFailureInit
    .then(reconcileDecision(reconciliationPolicy, manualExclusion)).expect(safety)
    .expect(not(oldSuccessNeedsReconciliation(authority.durable, 2)))
    .then(queryExternal(1, 3)).expect(safety)
    .then(receiveReport({ id: 3, exec: 1, kind: Success, value: 0, origin: ByQuery })).expect(safety)
    .expect(oldSuccessNeedsReconciliation(authority.durable, 2))
    .expect(authority.durable.decisions.length() == 1 and authority.durable.reports.size() == 3)
    .then(finishFailure(2).fail())

  run staleDecisionIsDisabledTest = oldSuccessCurrentFailureInit
    .then(queryExternal(1, 3)).expect(safety)
    .then(receiveReport({ id: 3, exec: 1, kind: Success, value: 0, origin: ByQuery })).expect(safety)
    // Proposal predates the new query report, so its reviewedRevision is stale.
    .then(reconcileDecision(reconciliationPolicy,
      { ...manualExclusion, reviewedRevision: 7 }).fail())

  run cancelledIntentCannotBeReconciledTest = oldSuccessCurrentFailureInit
    .then(cancelIntent).expect(safety)
    .then(reconcileDecision(reconciliationPolicy, manualAdoption).fail())

  run adoptionWinsCancellationRaceTest = oldSuccessCurrentFailureInit
    .then(reconcileDecision(reconciliationPolicy, manualAdoption)).expect(safety)
    .then(cancelIntent.fail())

  run duplicateDecisionIsDisabledTest = oldSuccessCurrentFailureInit
    .then(reconcileDecision(reconciliationPolicy, manualExclusion)).expect(safety)
    .then(reconcileDecision(reconciliationPolicy, manualExclusion).fail())

  run manualExclusionAllowsFailureTest = oldSuccessCurrentFailureInit
    .then(reconcileDecision(reconciliationPolicy, manualExclusion)).expect(safety)
    .expect(exclusionDecisionReached and manualDecisionReached)
    .expect(authority.durable.attempts.get(1).knowledge == SuccessKnown)
    .expect(authority.durable.reports.contains(success1))
    .then(finishFailure(2)).expect(safety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, value: 0, exec: Current(2) }))

  run manualAdoptionClosesWithOldSuccessTest = oldSuccessCurrentFailureInit
    .then(reconcileDecision(reconciliationPolicy, manualAdoption)).expect(safety)
    .expect(adoptionDecisionReached and manualDecisionReached)
    .expect(authority.durable.current == Current(2))
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, value: 0, exec: Current(1) }))
    .expect(authority.durable.reports.contains(success1))
    .expect(authority.durable.history.select(a => a.kind == EvidenceReconciled).length() == 1)
    .expect(authority.durable.history.select(a => a.kind == OutcomeStored).length() == 1)
}
