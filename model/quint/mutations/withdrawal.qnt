// Deliberately broken withdrawal effects, scope, version and checked-basis handling.
module withdrawalMutations {
  import conflictWithdrawalFixtures.* from "../scenarios/conflicts/withdrawal_fixtures"
  export conflictWithdrawalFixtures.*
  const WITHDRAWAL_BUG: int

  action mutantInit =
    if (WITHDRAWAL_BUG == 1) withdrawnInit
    else if (WITHDRAWAL_BUG == 2) partiallySupersededInit
      .then(sendReconciliationCommand(partialWithdrawalCommand)).expect(commandSafety)
    else withdrawalPendingInit

  // 错误涵盖恢复旧边,越界撤销,漏增版本,未核验依据,错误终结和删证据;都应被专属性质检出.
  action mutantStep = {
    val before = authority.durable
    val request = if (WITHDRAWAL_BUG == 2) partialWithdrawalCommand else withdrawalCommand
    val applied = applyNewCommand(before, withdrawalPolicy, withdrawalCommand)
    val updated =
      if (WITHDRAWAL_BUG == 1) {
        // Mistaken rollback: removing D1's old links resurrects D0 after withdrawing D1.
        val d1 = before.decisions.nth(1)
        { ...before, decisions: List(before.decisions.head(),
          { ...d1, decision: { ...d1.decision, supersedes: Set() } }, before.decisions.nth(2)) }
      } else if (WITHDRAWAL_BUG == 2)
        recordCommittedCommand(before, applyReconcile(before, withdrawalPolicy, withdrawalCommand.decision), request)
      else if (WITHDRAWAL_BUG == 3)
        { ...applied, revision: before.revision, judgmentChanges: before.judgmentChanges }
      else if (WITHDRAWAL_BUG == 4) {
        val unchecked = applyNewCommand(before, policy, request)
        { ...unchecked, decisions: before.decisions.append({
          ...unchecked.decisions.nth(2), contractQualified: true }) }
      } else if (WITHDRAWAL_BUG == 5)
        recordCommittedCommand(before, applyCommit(applyReconcile(before, withdrawalPolicy, request.decision),
          { kind: OutcomeSucceeded, exec: Current(1) }), request)
      else { ...applied, reports: applied.reports.exclude(Set(success1)) }
    all {
      authority.online,
      authority' = { ...authority, durable: updated }, workers' = workers,
      network' = network, external' = external, clock' = clock,
    }
  }

  val mutantInvariant =
    if (WITHDRAWAL_BUG == 1 or WITHDRAWAL_BUG == 4) withdrawalScopeSound
    else if (WITHDRAWAL_BUG == 2) commandExecutionMatchesRequest
    else if (WITHDRAWAL_BUG == 3) judgmentRevisionSound
    else if (WITHDRAWAL_BUG == 5) withdrawalCommandsNonterminal
    else reconciledEvidencePreserved

  run mutationCaughtTest = mutantInit.expect(commandSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(commandSafety))
}
