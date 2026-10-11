// Deterministic defensive scenarios sharing the bound conflict fixture.
module conflictSupersessionTests {
  import conflictFixtures.* from "./fixtures"
  export conflictFixtures.*

  run missingSupersessionRejectedTest = resolvedConflictInit
    .then(sendReconciliationCommand({ ...replacementCommand, decision: {
      ...replacementCommand.decision, supersedes: Set() } })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { ...replacementCommand, decision: {
      ...replacementCommand.decision, supersedes: Set() } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 1 and authority.durable.rejections.length() == 1)
    .expect(authority.durable.revision == 9 and judgmentKnowledge(authority.durable, 1) == FailureKnown)

  run unknownSupersessionTargetRejectedTest = resolvedConflictInit
    .then(sendReconciliationCommand({ ...replacementCommand, decision: {
      ...replacementCommand.decision, supersedes: Set({ decisionIndex: 7, reports: Set(success1, disputedFailure) }) } })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { ...replacementCommand, decision: {
      ...replacementCommand.decision, supersedes: Set({ decisionIndex: 7, reports: Set(success1, disputedFailure) }) } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 1 and authority.durable.rejections.length() == 1)

  run selfSupersessionRejectedTest = resolvedConflictInit
    .then(sendReconciliationCommand({ ...replacementCommand, decision: {
      ...replacementCommand.decision, supersedes: Set({ decisionIndex: 1, reports: Set(success1, disputedFailure) }) } })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { ...replacementCommand, decision: {
      ...replacementCommand.decision, supersedes: Set({ decisionIndex: 1, reports: Set(success1, disputedFailure) }) } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 1 and authority.durable.rejections.length() == 1)

  run alreadySupersededTargetRejectedTest = resolvedConflictInit
    .then(sendReconciliationCommand(replacementCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, replacementCommand)).expect(commandSafety)
    .then(sendReconciliationCommand({ ...replacementCommand, id: 3, decision: {
      ...exclusionCommand.decision, reviewedRevision: 10, supersedes: replacementCommand.decision.supersedes } })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { ...replacementCommand, id: 3, decision: {
      ...exclusionCommand.decision, reviewedRevision: 10, supersedes: replacementCommand.decision.supersedes } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.rejections.length() == 1)
    .expect(judgmentKnowledge(authority.durable, 1) == NoKnowledge)

  run overbroadSupersessionRejectedTest = wideExcludedInit
    .then(sendReconciliationCommand({ ...freshPartialExclusion, decision: {
      ...freshPartialExclusion.decision, supersedes: Set({ decisionIndex: 0, reports: Set(success1, disputedFailure, failure2) }) } })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { ...freshPartialExclusion, decision: {
      ...freshPartialExclusion.decision, supersedes: Set({ decisionIndex: 0, reports: Set(success1, disputedFailure, failure2) }) } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 1 and authority.durable.rejections.length() == 1)
    .expect(judgmentKnowledge(authority.durable, 2) == NoKnowledge)

  run partialSupersessionPreservesOtherRangeTest = partiallySupersededInit
    .expect(authority.durable.decisions.nth(1).decision.supersedes ==
      Set({ decisionIndex: 0, reports: Set(success1, disputedFailure) }))
    .expect(applicableBindings(authority.durable).exists(b => b.item.report == failure2 and b.decisionIndex == 0))
    .expect(applicableBindings(authority.durable).filter(b => b.item.report != failure2).forall(b => b.decisionIndex == 1))
    .expect(judgmentKnowledge(authority.durable, 1) == FailureKnown and judgmentKnowledge(authority.durable, 2) == NoKnowledge)
    .expect(authority.durable.decisions.head().decision == wideExclusionCommand.decision)

  run supersededOriginalCommandReplaysTest = partiallySupersededInit
    .then(sendReconciliationCommand(wideExclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, wideExclusionCommand)).expect(commandSafety)
    .expect(authority.durable.commands.length() == 2 and authority.durable.decisions.length() == 2)
    .expect(authority.durable.commands.head().outcomes == List() and authority.durable.revision == 10)
    .expect(judgmentKnowledge(authority.durable, 2) == NoKnowledge)

  run supersededCommandReplaysAfterClosureTest = partiallySupersededInit
    .then(cancelIntent).expect(commandSafety)
    .then(sendReconciliationCommand(wideExclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, wideExclusionCommand)).expect(commandSafety)
    .expect(authority.durable.commands.head().outcomes == List())
    .expect(authority.durable.outcomes == List({ kind: OutcomeCancelled, exec: NoCurrent }))
    .expect(authority.durable.commands.length() == 2 and authority.durable.decisions.length() == 2)

  run concurrentSupersessionReviewGoesStaleTest = resolvedConflictInit
    .then(sendReconciliationCommand(replacementCommand)).expect(commandSafety)
    .then(sendReconciliationCommand({ ...replacementCommand, id: 3, decision: {
      ...replacementCommand.decision, actor: AutomaticRule(5) } })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, replacementCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { ...replacementCommand, id: 3, decision: {
      ...replacementCommand.decision, actor: AutomaticRule(5) } })).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.rejections.length() == 1)
    .expect(authority.durable.rejections.head().command.decision.supersedes == replacementCommand.decision.supersedes)
    .expect(authority.durable.revision == 10)

  run evidenceBeforeSupersessionRequiresReviewTest = resolvedConflictInit
    .then(sendReconciliationCommand(replacementCommand)).expect(commandSafety)
    .then(offerCheckedEvidence(querySuccess)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, replacementCommand)).expect(commandSafety)
    .expect(authority.durable.decisions.length() == 1 and authority.durable.rejections.length() == 1)
    .expect(authority.durable.rejections.head().command == replacementCommand)
    .expect(not(noConflicts(authority.durable)))

  run supersessionCanReferenceTwoOldOwnersTest = partiallySupersededInit
    .then(sendReconciliationCommand({ id: 3, decision: conflictDecision(authority.durable,
      failure2, ExcludeAllEvidence, excludeAllAcross, Operator(1)) })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { id: 3, decision: conflictDecision(authority.durable,
      failure2, ExcludeAllEvidence, excludeAllAcross, Operator(1)) })).expect(commandSafety)
    .expect(authority.durable.decisions.nth(2).decision.supersedes == Set(
      { decisionIndex: 0, reports: Set(failure2) },
      { decisionIndex: 1, reports: Set(success1, disputedFailure) }))
    .expect(applicableBindings(authority.durable).forall(b => b.decisionIndex == 2))
    .expect(authority.durable.decisions.length() == 3 and authority.durable.outcomes == List())

  run changedSupersessionIsDifferentCommandContentTest = resolvedConflictInit
    .then(sendReconciliationCommand(replacementCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, replacementCommand)).expect(commandSafety)
    .then(sendReconciliationCommand({ ...replacementCommand, decision: {
      ...replacementCommand.decision, supersedes: Set() } })).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, { ...replacementCommand, decision: {
      ...replacementCommand.decision, supersedes: Set() } })).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIdentityConflict({
      ...replacementCommand, decision: { ...replacementCommand.decision, supersedes: Set() } }))))
    .expect(authority.durable.commands.length() == 2 and authority.durable.decisions.length() == 2)
}
