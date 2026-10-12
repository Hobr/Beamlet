// Scoped withdrawal examples. The policy is a checked premise, not a client-supplied permission.
module conflictWithdrawalFixtures {
  import conflictFixtures.* from "./fixtures"
  export conflictFixtures.*

  pure val withdrawD1: Set[Supersession] = Set({
    decisionIndex: 1, reports: Set(success1, disputedFailure),
  })
  pure val withdrawSuccess: Set[Supersession] = Set({ decisionIndex: 1, reports: Set(success1) })
  pure val withdrawKeep: Set[Supersession] = Set({ decisionIndex: 1, reports: Set(disputedFailure) })
  pure val withdrawD0: Set[Supersession] = Set({
    decisionIndex: 0, reports: Set(success1, disputedFailure),
  })
  pure val withdrawBothOwners = withdrawD1.union(Set({ decisionIndex: 0, reports: Set(failure2) }))
  pure val withdrawalPolicy: ReconciliationPolicy = {
    ...policy, withdrawals: Set(withdrawD1, withdrawSuccess, withdrawKeep, withdrawD0, withdrawBothOwners),
  }

  // Model-only shape, reusing command transport; a public withdrawal API remains undecided.
  pure val withdrawalCommand: ReconciliationCommand = {
    id: 3, decision: {
      kind: WithdrawDisposition, report: success1, actor: Operator(1), basis: VerifiedWithdrawal,
      reviewedRevision: 10, evidence: Set(), supersedes: withdrawD1,
    },
  }
  pure val partialWithdrawalCommand: ReconciliationCommand = {
    ...withdrawalCommand, decision: { ...withdrawalCommand.decision, supersedes: withdrawSuccess },
  }
  pure val keepWithdrawalCommand: ReconciliationCommand = {
    ...withdrawalCommand, decision: {
      ...withdrawalCommand.decision, report: disputedFailure, supersedes: withdrawKeep,
    },
  }
  pure val withdrawalRecord: CommandRecord = {
    command: withdrawalCommand, outcomes: List(), decisionIndex: 2,
  }

  action withdrawalPendingInit = partiallySupersededInit
    .then(sendReconciliationCommand(withdrawalCommand)).expect(commandSafety)
  action withdrawnInit = withdrawalPendingInit
    .then(receiveReconciliationCommand(withdrawalPolicy, withdrawalCommand)).expect(commandSafety)
  action partiallyWithdrawnInit = partiallySupersededInit
    .then(sendReconciliationCommand(partialWithdrawalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(withdrawalPolicy, partialWithdrawalCommand)).expect(commandSafety)

  def renewedAllExclusion: ReconciliationCommand = {
    id: 4, decision: conflictDecision(authority.durable, failure2,
      ExcludeAllEvidence, excludeAllAcross, Operator(1)),
  }

  val withdrawalWitness = withdrawalReached
  val renewedJudgmentWitness = authority.durable.decisions.select(w =>
    w.decision.kind == WithdrawDisposition).length() > 0
    and authority.durable.commands.select(c => c.command.id == 4).length() > 0

  action withdrawalStep = any {
    stepWithCommands(withdrawalPolicy), offerAnyCheckedEvidence, proposeConflictCommand,
    sendReconciliationCommand(withdrawalCommand), sendReconciliationCommand(partialWithdrawalCommand),
    sendReconciliationCommand(renewedAllExclusion),
  }
}
