// Retirement alone preserves accepted treatment; evidence/supersession still affect applicability.
module repeatingRetirementTests {
  import repeatingRetirementFixtures.* from "./retirement_fixtures"
  export repeatingRetirementFixtures.*

  run ordinaryRetirementPreservesOpenDispositionTest = ordinaryRetirementInit
    .expect(retiredV1Policy == upgradedRulePolicy)
    .expect(authority.durable.phase == Open and authority.durable.revision == 8)
    .expect(excludedForJudgment(authority.durable, success1))
    .expect(not(oldSuccessNeedsReconciliation(authority.durable, 2)))
    .expect(external.ruleRetirements.head().previousBindings.size() == 1)
    .expect(external.ruleRetirements.head().durableUnchanged)
    .expect(authority.durable.commands == List(automaticV1Record))

  run retiredDispositionStillAllowsEligibleFailureTest = ordinaryRetirementInit
    .then(finishFailure(2)).expect(commandSafety)
    .expect(retiredDispositionUsedWitness)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(2) }))
    .expect(authority.durable.decisions.head().decision.actor == AutomaticRule(rule2v1.rule))

  run retirementDoesNotStaleReviewedManualCommandTest = automaticRuleCommittedInit
    .then(sendReconciliationCommand({ id: 2, decision: manualAdoption })).expect(commandSafety)
    .then(retireRuleVersion(bothVersionPolicy, rule2v1.rule)).expect(commandSafety)
    .then(receiveReconciliationCommand(retiredV1Policy, { ...adoptionCommand, decision: {
      ...adoptionCommand.decision, reviewedRevision: 8,
      supersedes: Set({ decisionIndex: 0, reports: Set(success1) }),
    } })).expect(commandSafety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, exec: Current(1) }))
    .expect(authority.durable.decisions.length() == 2 and authority.durable.commands.length() == 2)
    .expect(authority.durable.decisions.nth(1).decision.supersedes
      == Set({ decisionIndex: 0, reports: Set(success1) }))

  run retiredV1FreshCommandStillRejectedTest = ordinaryRetirementInit
    .then(sendReconciliationCommand(freshRetiredV1Command)).expect(commandSafety)
    .then(receiveReconciliationCommand(retiredV1Policy, freshRetiredV1Command)).expect(commandSafety)
    .expect(authority.durable.rejections.length() == 1)
    .expect(authority.durable.rejections.head().result == DecisionIneligible)
    .expect(authority.durable.revision == 8 and excludedForJudgment(authority.durable, success1))
    .expect(authority.durable.commands == List(automaticV1Record))

  run pendingRetiredV1HasNoGrandfatheredAdmissionTest = retirementBeforeDecisionInit
    .then(receiveReconciliationCommand(retiredV1Policy, automaticV1Command)).expect(commandSafety)
    .expect(authority.durable.decisions == List() and authority.durable.revision == 7)
    .expect(authority.durable.rejections.head().result == DecisionIneligible)
    .expect(oldSuccessNeedsReconciliation(authority.durable, 2))

  run retiredOriginalResultStillReplaysTest = ordinaryRetirementInit
    .then(sendReconciliationCommand(automaticV1Command)).expect(commandSafety)
    .then(receiveReconciliationCommand(retiredV1Policy, automaticV1Command)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(automaticV1Record))))
    .expect(authority.durable.revision == 8 and excludedForJudgment(authority.durable, success1))

  run retirementAfterClosurePreservesOutcomeAndOriginalResultTest = retirementAfterClosureInit
    .then(sendReconciliationCommand(automaticV1Command)).expect(commandSafety)
    .then(receiveReconciliationCommand(retiredV1Policy, automaticV1Command)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(automaticV1Record))))
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(2) }))
    .expect(authority.durable.commands.head().outcomes == List())
    .expect(external.ruleRetirements.head().durableUnchanged)

  run newEvidenceStillInvalidatesRetiredDispositionTest = ordinaryRetirementInit
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .expect(not(excludedForJudgment(authority.durable, success1)))
    .expect(oldSuccessNeedsReconciliation(authority.durable, 2))
    .expect(authority.durable.revision == 9 and authority.durable.outcomes == List())
    .expect(authority.durable.commands == List(automaticV1Record))

  run retirementOfUnusedVersionDoesNotChangeTreatmentTest = automaticRuleCommittedInit
    .then(retireRuleVersion(bothVersionPolicy, rule2v2.rule)).expect(commandSafety)
    .expect(excludedForJudgment(authority.durable, success1) and authority.durable.revision == 8)
    .expect(external.ruleRetirements.head().nextRules.contains(rule2v1))
    .expect(not(external.ruleRetirements.head().nextRules.contains(rule2v2)))

  run restartAfterRetirementPreservesDispositionTest = ordinaryRetirementInit
    .then(crashCoordinator).expect(commandSafety)
    .then(restartCoordinator).expect(commandSafety)
    .expect(excludedForJudgment(authority.durable, success1) and authority.durable.revision == 8)
    .then(finishFailure(2)).expect(commandSafety)
    .expect(retiredDispositionUsedWitness)
}
