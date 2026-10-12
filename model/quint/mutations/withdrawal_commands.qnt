// Deliberate Q77 command bugs: replay retargeting, split operation namespaces, early reply.
module withdrawalCommandMutations {
  import conflictWithdrawalFixtures.* from "../scenarios/conflicts/withdrawal_fixtures"
  export conflictWithdrawalFixtures.*
  const WITHDRAWAL_COMMAND_BUG: int

  action mutantInit =
    if (WITHDRAWAL_COMMAND_BUG == 1) renewedWithdrawalInit
      .then(sendReconciliationCommand(withdrawalCommand)).expect(commandSafety)
    else if (WITHDRAWAL_COMMAND_BUG == 2) withdrawnInit
      .then(sendReconciliationCommand(coordinationUsingWithdrawalId)).expect(commandSafety)
    else withdrawalPendingInit

  action mutantStep = {
    val before = authority.durable
    val request = if (WITHDRAWAL_COMMAND_BUG == 2) coordinationUsingWithdrawalId else withdrawalCommand
    val target = Set({ decisionIndex: 3, reports: Set(success1, disputedFailure) })
    val retargeted = { ...withdrawalCommand, decision: { ...withdrawalCommand.decision,
      reviewedRevision: before.revision, supersedes: target } }
    val checkedPolicy = { ...withdrawalPolicy, withdrawals: Set(target) }
    val updated =
      if (WITHDRAWAL_COMMAND_BUG == 1) applyNewCommand(before, checkedPolicy, retargeted)
      else if (WITHDRAWAL_COMMAND_BUG == 2) applyNewCommand(before, withdrawalPolicy, request)
      else before
    val original = if (WITHDRAWAL_COMMAND_BUG == 3) withdrawalRecord
      else updated.commands.nth(updated.commands.length() - 1)
    val reply = CommandCommitted(original)
    all {
      authority.online, network.contains(ReconcileRequest(request)),
      // These candidate effects are eligible apart from their already occupied command identity.
      (WITHDRAWAL_COMMAND_BUG == 3 or canReconcile(before,
        if (WITHDRAWAL_COMMAND_BUG == 1) checkedPolicy else withdrawalPolicy,
        if (WITHDRAWAL_COMMAND_BUG == 1) retargeted.decision else request.decision)),
      authority' = { ...authority, durable: updated }, workers' = workers, clock' = clock,
      network' = network.exclude(Set(ReconcileRequest(request))).union(Set(ReconcileReply(reply))),
      external' = observeCommandHandling(external, before, updated, withdrawalPolicy, request, reply),
    }
  }

  val mutantInvariant =
    if (WITHDRAWAL_COMMAND_BUG == 1) commandHandlingSound
    else if (WITHDRAWAL_COMMAND_BUG == 2) commandRecordsUnique
    else commandRepliesSound

  run mutationCaughtTest = mutantInit.expect(commandSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(commandSafety))
}
