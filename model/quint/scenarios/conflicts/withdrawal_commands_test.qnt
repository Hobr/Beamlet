// A replay is historical reading, not a second withdrawal or an operation-kind namespace.
module conflictWithdrawalCommandTests {
  import conflictWithdrawalFixtures.* from "./withdrawal_fixtures"
  export conflictWithdrawalFixtures.*

  val renewedDispositionPreserved = authority.durable.revision == 12
    and authority.durable.decisions.length() == 4 and authority.durable.commands.length() == 4
    and applicableBindings(authority.durable).size() == 3
    and applicableBindings(authority.durable).forall(b => b.decisionIndex == 3)
    and authority.durable.commands.nth(2) == withdrawalRecord
    and authority.durable.history.select(a => a.kind == EvidenceReconciled).length() == 4
    and authority.durable.outcomes == List()

  run withdrawalReplayAfterRenewedDispositionDoesNotRetargetTest = renewedWithdrawalInit
    .expect(renewedDispositionPreserved and not(decisionScopeCurrent(authority.durable, withdrawalCommand.decision)))
    .then(sendReconciliationCommand(withdrawalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
    .expect(renewedDispositionPreserved and withdrawalOriginalReplayWitness)
    .expect(network.contains(ReconcileReply(CommandCommitted(withdrawalRecord))))

  run lostWithdrawalReplyRestartAndRenewalStillReplayOriginalTest = withdrawnInit
    .then(loseMessage(ReconcileReply(CommandCommitted(withdrawalRecord)))).expect(commandSafety)
    .then(crashCoordinator).expect(commandSafety)
    .then(restartCoordinator).expect(commandSafety)
    .then(sendReconciliationCommand(renewedAllExclusion)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, renewedAllExclusion)).expect(commandSafety)
    .expect(renewedDispositionPreserved)
    .then(sendReconciliationCommand(withdrawalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
    .expect(renewedDispositionPreserved and withdrawalOriginalReplayWitness)

  run renewedWithdrawalReplayIgnoresNewSubmissionEligibilityTest = renewedWithdrawalInit
    .then(sendReconciliationCommand(withdrawalCommand)).expect(commandSafety)
    .then(receiveCommandWithAccess(policy, withdrawalCommand,
      { maySubmit: false, mayRead: true })).expect(commandSafety)
    .expect(renewedDispositionPreserved and withdrawalOriginalReplayWitness)
    .expect(network.contains(ReconcileReply(CommandCommitted(withdrawalRecord))))

  run withdrawalCannotReuseAcceptedCoordinationIdTest = partiallySupersededInit
    .then(sendReconciliationCommand(withdrawalUsingCoordinationId)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalUsingCoordinationId)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIdentityConflict(withdrawalUsingCoordinationId))))
    .expect(crossKindIdentityConflictWitness and authority.durable.decisions.length() == 2)
    .expect(authority.durable.commands.length() == 2 and authority.durable.rejections == List())
    .expect(authority.durable.revision == 10 and applicableBindings(authority.durable).size() == 3)

  run coordinationCannotReuseAcceptedWithdrawalIdTest = withdrawnInit
    .then(sendReconciliationCommand(coordinationUsingWithdrawalId)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, coordinationUsingWithdrawalId)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIdentityConflict(coordinationUsingWithdrawalId))))
    .expect(crossKindIdentityConflictWitness and authority.durable.decisions.length() == 3)
    .expect(authority.durable.commands.length() == 3 and authority.durable.rejections == List())
    .expect(authority.durable.revision == 11 and applicableBindings(authority.durable).size() == 1)

  run changedWithdrawalTargetEvenAfterRenewalIsIdentityConflictTest = renewedWithdrawalInit
    .then(sendReconciliationCommand({ ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, reviewedRevision: 12,
      supersedes: Set({ decisionIndex: 3, reports: Set(success1, disputedFailure) }) } })).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...withdrawalPolicy,
      withdrawals: Set(Set({ decisionIndex: 3, reports: Set(success1, disputedFailure) })) },
      { ...withdrawalCommand, decision: { ...withdrawalCommand.decision, reviewedRevision: 12,
        supersedes: Set({ decisionIndex: 3, reports: Set(success1, disputedFailure) }) } })).expect(commandSafety)
    .expect(renewedDispositionPreserved and authority.durable.rejections == List())
    .expect(external.marks.contains("commandIdentityConflict"))

  run rejectedWithdrawalKeepsOriginalResultAfterGroundsImproveTest = withdrawalPendingInit
    .then(receiveReconciliationCommand(policy, withdrawalCommand)).expect(commandSafety)
    .expect(authority.durable.rejections.head() == { command: withdrawalCommand, result: DecisionIneligible })
    .then(sendReconciliationCommand(withdrawalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIneligible(withdrawalCommand))))
    .expect(authority.durable.commands.length() == 2 and authority.durable.rejections.length() == 1)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.revision == 10)

  run freshIdentityCanWithdrawAfterOriginalRejectionTest = withdrawalPendingInit
    .then(receiveReconciliationCommand(policy, withdrawalCommand)).expect(commandSafety)
    .then(sendReconciliationCommand({ ...withdrawalCommand, id: 4 })).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, { ...withdrawalCommand, id: 4 })).expect(commandSafety)
    .expect(authority.durable.rejections.head() == { command: withdrawalCommand, result: DecisionIneligible })
    .expect(authority.durable.commands.nth(2).command == { ...withdrawalCommand, id: 4 })
    .expect(authority.durable.commands.nth(2).outcomes == List() and authority.durable.revision == 11)

  run rejectedWithdrawalAlsoReservesIdAgainstCoordinationTest = withdrawalPendingInit
    .then(receiveReconciliationCommand(policy, withdrawalCommand)).expect(commandSafety)
    .then(sendReconciliationCommand(coordinationUsingWithdrawalId)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, coordinationUsingWithdrawalId)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIdentityConflict(coordinationUsingWithdrawalId))))
    .expect(authority.durable.commands.length() == 2 and authority.durable.rejections.length() == 1)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.revision == 10)

  run rejectedCoordinationAlsoReservesIdAgainstWithdrawalTest = withdrawalPendingInit
    .then(sendReconciliationCommand(coordinationUsingWithdrawalId)).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...policy, resolutions: Set() },
      coordinationUsingWithdrawalId)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
    .expect(network.contains(ReconcileReply(CommandIdentityConflict(withdrawalCommand))))
    .expect(authority.durable.commands.length() == 2 and authority.durable.rejections.length() == 1)
    .expect(authority.durable.rejections.head().command.decision.kind == ExcludeAllEvidence)
    .expect(authority.durable.decisions.length() == 2 and authority.durable.revision == 10)

  run withdrawalRequiresFreshReviewForFirstAdmissionTest = partiallySupersededInit
    .then(sendReconciliationCommand({ ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, reviewedRevision: 9 } })).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, { ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, reviewedRevision: 9 } })).expect(commandSafety)
    .expect(authority.durable.rejections.length() == 1 and authority.durable.decisions.length() == 2)
    .expect(authority.durable.revision == 10)
    .expect(match authority.durable.rejections.head().result {
      | ReviewStale(s) => s.revision == 10
      | _ => false
    })

  run acceptedWithdrawalStoresRelationResultAuditAndRevisionTogetherTest = withdrawnInit
    .expect(authority.durable.commands.nth(2) == withdrawalRecord)
    .expect(authority.durable.decisions.nth(2).decision == withdrawalCommand.decision)
    .expect(authority.durable.decisionSnapshots.nth(2) == withdrawalCommand.decision)
    .expect(authority.durable.history.select(a => a.kind == EvidenceReconciled).length() == 3)
    .expect(authority.durable.commandCommits.nth(2).decisionsAfter == 3)
    .expect(authority.durable.commandCommits.nth(2).historyAfter == authority.durable.history.length())
    .expect(authority.durable.revision == 11 and authority.durable.outcomes == List())
}
