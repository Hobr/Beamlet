// Deterministic scenarios using the shared fixture and real guarded transitions.
module repeatingAccessTests {
  import repeatingFixtures.* from "./fixtures"
  export repeatingFixtures.*

  run permissionFailureDoesNotReserveCommandIdTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, readonlyAccess)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandForbidden(exclusionCommand))))
    .expect(authority.durable.rejections.length() == 0 and authority.durable.commands.length() == 0)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(reconciliationPolicy, exclusionCommand)).expect(commandSafety)
    .expect(authority.durable.commands == List(excludedRecord))

  run revokedSubmitPermissionAllowsReadingOriginalResultTest = committedExclusionInit
    .then(loseMessage(ReconcileReply(CommandCommitted(excludedRecord)))).expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess({ ...reconciliationPolicy, operators: Set() }, exclusionCommand, readonlyAccess))
      .expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(excludedRecord))))
    .expect(authority.durable.commands == List(excludedRecord) and authority.durable.decisions.length() == 1)
    .expect(readonlyReplayReached)

  run revokedReadPermissionPreservesIdentityForLaterReadTest = committedExclusionInit
    .then(loseMessage(ReconcileReply(CommandCommitted(excludedRecord)))).expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, noAccess)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandForbidden(exclusionCommand))))
    .expect(not(network.contains(ReconcileReply(CommandCommitted(excludedRecord)))))
    .expect(authority.durable.commands == List(excludedRecord))
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, readonlyAccess)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(excludedRecord))))
    .expect(authority.durable.decisions.length() == 1)

  run readDeniedAlsoProtectsOriginalRejectionTest = rejectedStaleInit
    .then(loseMessage(ReconcileReply(rejectionReply(staleRejection)))).expect(commandSafety)
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, noAccess)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandForbidden(exclusionCommand))))
    .expect(not(network.contains(ReconcileReply(rejectionReply(staleRejection)))))
    .expect(authority.durable.rejections == List(staleRejection))
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, readonlyAccess)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(rejectionReply(staleRejection))))
    .expect(authority.durable.decisions.length() == 0)

  run submitAndReadRightsAreIndependentTest = oldSuccessCurrentFailureInit
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, { maySubmit: true, mayRead: false }))
      .expect(commandSafety)
    .expect(authority.durable.commands == List(excludedRecord))
    .expect(network.contains(ReconcileReply(CommandForbidden(exclusionCommand))))
    .expect(not(network.contains(ReconcileReply(CommandCommitted(excludedRecord)))))
    .then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, exclusionCommand, readonlyAccess)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandCommitted(excludedRecord))))
    .expect(authority.durable.decisions.length() == 1)

  run readDeniedIdentityConflictDoesNotExecuteTest = committedExclusionInit
    .then(sendReconciliationCommand({ ...adoptionCommand, id: 1 })).expect(commandSafety)
    .then(receiveCommandWithAccess(reconciliationPolicy, { ...adoptionCommand, id: 1 }, noAccess))
      .expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandForbidden({ ...adoptionCommand, id: 1 }))))
    .expect(authority.durable.commands == List(excludedRecord) and authority.durable.decisions.length() == 1)
    .expect(authority.durable.outcomes == List())
}
