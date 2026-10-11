// Pinned version admission, current conditions, original result replay and reevaluation.
module repeatingRuleTests {
  import repeatingRuleFixtures.* from "./rules_fixtures"
  export repeatingRuleFixtures.*

  run pinnedV1AcceptedAlongsideV2Test = automaticRuleCommittedInit
    .expect(authority.durable.decisions.head().decision.actor == AutomaticRule(rule2v1.rule))
    .expect(authority.durable.decisions.head().rulesAtDecision == bothVersionPolicy.registeredRules)
    .expect(authority.durable.commands == List(automaticV1Record) and authority.durable.revision == 8)

  run narrowerV2DoesNotBorrowV1ConditionsTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(automaticV2Command)).expect(commandSafety)
    .then(receiveReconciliationCommand(bothVersionPolicy, automaticV2Command)).expect(commandSafety)
    .expect(authority.durable.decisions == List() and authority.durable.rejections.length() == 1)
    .expect(authority.durable.rejections.head().result == DecisionIneligible)

  run retiredV1RejectedEvenAtCurrentRevisionTest = retiredRuleRejectedInit
    .expect(authority.durable.rejections.head().command == automaticV1Command)
    .expect(authority.durable.rejections.head().result == DecisionIneligible)
    .expect(authority.durable.decisions == List() and authority.durable.revision == 7)

  run missingRuleVersionRejectedTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand({ ...automaticV1Command, decision: {
      ...automaticV1Command.decision, actor: AutomaticRule({ id: 2, version: 0 }) } })).expect(commandSafety)
    .then(receiveReconciliationCommand(bothVersionPolicy, { ...automaticV1Command, decision: {
      ...automaticV1Command.decision, actor: AutomaticRule({ id: 2, version: 0 }) } })).expect(commandSafety)
    .expect(authority.durable.decisions == List() and authority.durable.rejections.length() == 1)

  run unknownRuleVersionRejectedTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand({ ...automaticV1Command, decision: {
      ...automaticV1Command.decision, actor: AutomaticRule({ id: 2, version: 9 }) } })).expect(commandSafety)
    .then(receiveReconciliationCommand(bothVersionPolicy, { ...automaticV1Command, decision: {
      ...automaticV1Command.decision, actor: AutomaticRule({ id: 2, version: 9 }) } })).expect(commandSafety)
    .expect(authority.durable.decisions == List() and authority.durable.rejections.length() == 1)

  run duplicateVersionDefinitionRejectedTest = automaticRulePendingInit
    .then(receiveReconciliationCommand({ ...bothVersionPolicy,
      registeredRules: bothVersionPolicy.registeredRules.union(Set({ ...rule2v1, queryRequired: true })) },
      automaticV1Command)).expect(commandSafety)
    .expect(authority.durable.decisions == List() and authority.durable.rejections.length() == 1)

  run retiredRuleOriginalResultReplaysTest = automaticRuleCommittedInit
    .then(sendReconciliationCommand(automaticV1Command)).expect(commandSafety)
    .then(receiveReconciliationCommand(upgradedRulePolicy, automaticV1Command)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(automaticV1Record))))
    .expect(authority.durable.commands == List(automaticV1Record) and authority.durable.decisions.length() == 1)
    .expect(authority.durable.revision == 8)

  run noRegisteredRulesStillPermitsOriginalReadTest = automaticRuleCommittedInit
    .then(sendReconciliationCommand(automaticV1Command)).expect(commandSafety)
    .then(receiveCommandWithAccess({ ...reconciliationPolicy, registeredRules: Set() },
      automaticV1Command, readonlyAccess)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(automaticV1Record))))
    .expect(authority.durable.decisions.head().rulesAtDecision == bothVersionPolicy.registeredRules)
    .expect(authority.durable.commands.length() == 1)

  run retiredRuleReplayStillNeedsReadAccessTest = automaticRuleCommittedInit
    .then(sendReconciliationCommand(automaticV1Command)).expect(commandSafety)
    .then(receiveCommandWithAccess(upgradedRulePolicy, automaticV1Command, noAccess)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandForbidden(automaticV1Command))))
    .expect(authority.durable.commands == List(automaticV1Record))

  run retiredRuleReplayAfterClosureTest = automaticRuleCommittedInit
    .then(finishFailure(2)).expect(commandSafety)
    .then(sendReconciliationCommand(automaticV1Command)).expect(commandSafety)
    .then(receiveReconciliationCommand(upgradedRulePolicy, automaticV1Command)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(automaticV1Record))))
    .expect(authority.durable.commands.head().outcomes == List())
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(2) }))

  run retiredVersionRejectionRemainsOriginalTest = retiredRuleRejectedInit
    .then(sendReconciliationCommand(automaticV1Command)).expect(commandSafety)
    .then(receiveReconciliationCommand(bothVersionPolicy, automaticV1Command)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIneligible(automaticV1Command))))
    .expect(authority.durable.decisions == List() and authority.durable.rejections.length() == 1)

  run sameCommandIdCannotChangeRuleVersionTest = automaticRuleCommittedInit
    .then(sendReconciliationCommand(automaticV2Command)).expect(commandSafety)
    .then(receiveReconciliationCommand(upgradedRulePolicy, automaticV2Command)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIdentityConflict(automaticV2Command))))
    .expect(authority.durable.commands == List(automaticV1Record) and authority.durable.decisions.length() == 1)

  run reevaluationUsesNewIdAndPinnedV2Test = retiredRuleRejectedInit
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(sendReconciliationCommand(automaticQueryV2)).expect(commandSafety)
    .then(receiveReconciliationCommand(queryRulePolicy, automaticQueryV2)).expect(commandSafety)
    .expect(authority.durable.decisions.head().decision.actor == AutomaticRule(rule2v2.rule))
    .expect(authority.durable.commands.head().command.id == 2 and authority.durable.rejections.head().command.id == 1)
    .expect(authority.durable.rejections.head().command.decision.actor == AutomaticRule(rule2v1.rule))
    .expect(authority.durable.revision == 9 and authority.durable.outcomes == List())

  run currentV2QueryStillNeedsContractBasisTest = oldSuccessCurrentFailureInit
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(sendReconciliationCommand(automaticQueryV2)).expect(commandSafety)
    .then(receiveReconciliationCommand(upgradedRulePolicy, automaticQueryV2)).expect(commandSafety)
    .expect(authority.durable.decisions == List() and authority.durable.rejections.length() == 1)

  run newEvidenceStillInvalidatesPinnedDecisionTest = automaticRulePendingInit
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(receiveReconciliationCommand(bothVersionPolicy, automaticV1Command)).expect(commandSafety)
    .expect(staleCommandRejectedReached and authority.durable.decisions == List())

  run manualDecisionUnaffectedByRuleUpgradeTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(upgradedRulePolicy, exclusionCommand)).expect(commandSafety)
    .expect(authority.durable.commands == List(excludedRecord))
    .expect(authority.durable.decisions.head().decision.actor == Operator(1))
}
