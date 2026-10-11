// Deterministic scenarios using the shared fixture and real guarded transitions.
module repeatingRejectionsTests {
  import repeatingFixtures.* from "./fixtures"
  export repeatingFixtures.*

  run rejectionIsAtomicAndDoesNotMakeDecisionTest = rejectedStaleInit
    .expect(authority.durable.rejections == List(staleRejection))
    .expect(authority.durable.commands.length() == 0 and authority.durable.decisions.length() == 0)
    .expect(authority.durable.outcomes == List())
    .expect(authority.durable.history.select(a => a.kind == CommandRejectionStored).length() == 1)

  run rejectionLostReplyRestartKeepsOriginalContextTest = rejectedStaleInit
    .then(loseMessage(ReconcileReply(rejectionReply(staleRejection)))).expect(commandSafety)
    .then(crashCoordinator).expect(commandSafety)
    .then(restartCoordinator).expect(commandSafety)
    .then(queryExternal(1, 4)).expect(commandSafety)
    .then(receiveReport(querySuccess4)).expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, readonlyAccess)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(rejectionReply(staleRejection))))
    .expect(authority.durable.rejections == List(staleRejection))
    .expect(authority.durable.reports.size() == 4 and authority.durable.decisions.length() == 0)
    .expect(authority.durable.history.select(a => a.kind == CommandRejectionStored).length() == 1)

  run rejectedCommandIsNotReevaluatedWhenConditionImprovesTest = rejectedIneligibleInit
    .expect(canReconcile(authority.durable, reconciliationPolicy, exclusionCommand.decision))
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIneligible(exclusionCommand))))
    .expect(authority.durable.rejections == List(ineligibleRejection))
    .expect(authority.durable.commands.length() == 0 and authority.durable.decisions.length() == 0)

  run freshIdCanReevaluateRejectedContentTest = rejectedIneligibleInit
    .then(sendReconciliationCommand({ ...exclusionCommand, id: 2 })).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, { ...exclusionCommand, id: 2 })).expect(commandSafety)
    .expect(authority.durable.rejections == List(ineligibleRejection))
    .expect(authority.durable.commands.head().command == { ...exclusionCommand, id: 2 })
    .expect(authority.durable.decisions.length() == 1)
    .then(finishFailure(2)).expect(commandSafety)
    .expect(failedReached)

  run rejectedIdCannotBeReusedForDifferentContentTest = rejectedIneligibleInit
    .then(sendReconciliationCommand({ ...adoptionCommand, id: 1 })).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, { ...adoptionCommand, id: 1 })).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIdentityConflict({ ...adoptionCommand, id: 1 }))))
    .expect(authority.durable.rejections == List(ineligibleRejection))
    .expect(authority.durable.commands.length() == 0 and authority.durable.decisions.length() == 0)
}
