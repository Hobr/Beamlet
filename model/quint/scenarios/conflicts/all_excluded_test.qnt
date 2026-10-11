// Deterministic defensive scenarios sharing the bound conflict fixture.
module conflictAllExcludedTests {
  import conflictFixtures.* from "./fixtures"
  export conflictFixtures.*

  run allExcludedRemainsUnknownTest = allExcludedInit
    .expect(authority.durable.phase == Open and authority.durable.outcomes == List())
    .expect(noConflicts(authority.durable) and authority.durable.attempts.get(1).conflict)
    .expect(authority.durable.attempts.get(1).knowledge == SuccessKnown)
    .expect(judgmentKnowledge(authority.durable, 1) == NoKnowledge)
    .expect(not(noUnresolvedRisk(authority.durable)))
    .expect(authority.durable.reports == Set(success1, disputedFailure, failure2))
    .expect(authority.durable.commands.head().outcomes == List())
    .then(finishFailure(2)).fail()

  run allExcludedReplayIsOriginalTest = allExcludedInit
    .then(sendReconciliationCommand(allExclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, allExclusionCommand)).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 1 and authority.durable.commands.length() == 1)
    .expect(authority.durable.revision == 9 and authority.durable.outcomes == List())
    .expect(authority.durable.commands.head().outcomes == List())

  run allExcludedNewEvidenceRequiresReviewTest = allExcludedInit
    .then(offerCheckedEvidence(querySuccess)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .expect(not(noConflicts(authority.durable)) and authority.durable.revision == 10)
    .then(sendReconciliationCommand(allExclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, allExclusionCommand)).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 1 and not(noConflicts(authority.durable)))
    .expect(authority.durable.outcomes == List())

  run allExcludedFreshEvidenceCanSucceedTest = allExcludedInit
    .then(offerCheckedEvidence(querySuccess)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(sendReconciliationCommand({ id: 2, decision: adoption })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { id: 2, decision: adoption })).expect(commandSafety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, exec: Current(1) }))
    .expect(authority.durable.commands.head().outcomes == List())

  run allExcludedNeedsCheckedBasisTest = conflictInit
    .then(sendReconciliationCommand(allExclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...policy,
      resolutions: policy.resolutions.exclude(Set(excludeAllConflict)) }, allExclusionCommand)).expect(commandSafety)
    .expect(authority.durable.decisions == List() and authority.durable.rejections.length() == 1)
    .expect(not(noConflicts(authority.durable)))

  run automaticAllExcludedTest = conflictInit
    .then(sendReconciliationCommand({ id: 1, decision: {
      ...allExclusionCommand.decision, actor: AutomaticRule(5) } })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { id: 1, decision: {
      ...allExclusionCommand.decision, actor: AutomaticRule(5) } })).expect(commandSafety)
    .expect(noConflicts(authority.durable) and judgmentKnowledge(authority.durable, 1) == NoKnowledge)
    .expect(authority.durable.phase == Open and authority.durable.outcomes == List())

  run bothAttemptsAllExcludedTest = bothConflictsInit
    .then(sendReconciliationCommand({ id: 1, decision: conflictDecision(authority.durable,
      querySuccess2, ExcludeAllEvidence, excludeAllBoth, Operator(1)) })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { id: 1, decision: conflictDecision(authority.durable,
      querySuccess2, ExcludeAllEvidence, excludeAllBoth, Operator(1)) })).expect(commandSafety)
    .expect(noConflicts(authority.durable))
    .expect(judgmentKnowledge(authority.durable, 1) == NoKnowledge and judgmentKnowledge(authority.durable, 2) == NoKnowledge)
    .expect(authority.durable.attempts.get(2).knowledge == FailureKnown)
    .expect(not(noUnresolvedRisk(authority.durable)) and authority.durable.outcomes == List())
    .then(finishFailure(2)).fail()

  run allExcludedStillAllowsCancellationTest = allExcludedInit
    .then(cancelIntent).expect(commandSafety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeCancelled, exec: NoCurrent }))
    .expect(authority.durable.commands.head().outcomes == List())
    .expect(authority.durable.reports.size() == 3 and authority.durable.attempts.get(1).conflict)

  run allExcludedCannotKeepOneReportTest = conflictInit
    .then(sendReconciliationCommand({ id: 1, decision: {
      ...allExclusionCommand.decision, evidence: excludeOldConflict } })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { id: 1, decision: {
      ...allExclusionCommand.decision, evidence: excludeOldConflict } })).expect(commandSafety)
    .expect(authority.durable.decisions == List() and authority.durable.rejections.length() == 1)

  run allExcludedBlocksExplicitFailureAdoptionTest = allExcludedInit
    .then(sendReconciliationCommand({ id: 2, decision: conflictDecision(authority.durable,
      failure2, AdoptFailure, failWithUnknownOld, Operator(1)) })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { id: 2, decision: conflictDecision(authority.durable,
      failure2, AdoptFailure, failWithUnknownOld, Operator(1)) })).expect(commandSafety)
    .expect(authority.durable.outcomes == List() and authority.durable.rejections.length() == 1)
    .expect(judgmentKnowledge(authority.durable, 1) == NoKnowledge)

  run freshAllExclusionDoesNotResurrectEarlierKeepTest = resolvedConflictInit
    .then(sendReconciliationCommand(freshAllExclusion)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, freshAllExclusion)).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 2 and noConflicts(authority.durable))
    .expect(judgmentKnowledge(authority.durable, 1) == NoKnowledge)
    .then(finishFailure(2)).fail()

  run freshCheckedKeepCanReplaceAllExclusionTest = allExcludedInit
    .then(sendReconciliationCommand(freshPartialExclusion)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, freshPartialExclusion)).expect(commandSafety)
    .expect(judgmentKnowledge(authority.durable, 1) == FailureKnown)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.commands.head().outcomes == List())
    .then(finishFailure(2)).expect(commandSafety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(2) }))
}
