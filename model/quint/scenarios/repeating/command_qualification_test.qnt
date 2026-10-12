// Deterministic scenarios using the shared fixture and real guarded transitions.
module repeatingCommandQualificationTests {
  import repeatingFixtures.* from "./fixtures"
  export repeatingFixtures.*

  run heartbeatDoesNotInvalidateReviewTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(moveClockTo(3)).expect(commandSafety)
    .then(renewLease(t2)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)
    .expect(authority.durable.commands == List(excludedRecord))
    .expect(network.contains(ReconcileReply(CommandCommitted(excludedRecord))))

  // 新证据后的自动重算是新请求;旧 ID 只能取原处理结果,不能用它重新采用当前判断.
  run automaticFreshEvaluationUsesNewCommandTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand({
      ...exclusionCommand, decision: { ...exclusionCommand.decision, actor: AutomaticRule({ id: 2, version: 1 }) },
    })).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, {
      ...exclusionCommand, decision: { ...exclusionCommand.decision, actor: AutomaticRule({ id: 2, version: 1 }) },
    })).expect(commandSafety)
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .expect(oldSuccessNeedsReconciliation(authority.durable, 2))
    .then(sendReconciliationCommand({
      id: 2, decision: proposeDecision(authority.durable, querySuccess, AdoptSuccess, AutomaticRule({ id: 1, version: 1 })),
    })).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, {
      id: 2, decision: proposeDecision(authority.durable, querySuccess, AdoptSuccess, AutomaticRule({ id: 1, version: 1 })),
    })).expect(commandSafety)
    .expect(authority.durable.commands.length() == 2 and authority.durable.decisions.length() == 2)
    .expect(authority.durable.commands.head().command.id == 1)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, value: 0, exec: Current(1) }))

  run unauthorizedCommandHasNoDecisionTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...reconciliationPolicy, operators: Set() }, exclusionCommand))
      .expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandForbidden(exclusionCommand))))
    .expect(authority.durable.commands.length() == 0 and authority.durable.decisions.length() == 0)
    .expect(authority.durable.rejections.length() == 0)

  run newCommandCannotChangeClosedIntentTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(adoptionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, adoptionCommand)).expect(commandSafety)
    .then(sendReconciliationCommand({
      ...exclusionCommand, decision: { ...exclusionCommand.decision, reviewedRevision: 9 },
    })).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, {
      ...exclusionCommand, decision: { ...exclusionCommand.decision, reviewedRevision: 9 },
    })).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIneligible({
      ...exclusionCommand, decision: { ...exclusionCommand.decision, reviewedRevision: 9 },
    }))))
    .expect(authority.durable.commands == List(adoptedRecord) and authority.durable.decisions.length() == 1)
}
