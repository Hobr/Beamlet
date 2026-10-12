// One shared unbound instance, legal prefixes and fixed original requests for mutations.
module reconciliationMutationFixtures {

  const BUG: int

  import beamletCore.* from "../beamletCore"
  export beamletCore.*

  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }

  pure val t2: Token = { exec: 2, worker: 2, incarnation: 1, generation: 1 }

  pure val success1: Report = { id: 2, exec: 1, kind: Success, origin: ByWorker(t1) }

  pure val failure2: Report = { id: 2, exec: 2, kind: Failure, origin: ByWorker(t2) }

  pure val querySuccess: Report = { id: 3, exec: 1, kind: Success, origin: ByQuery }

  pure val policy: ReconciliationPolicy = {
    operators: Set(1), registeredRules: Set(rule1v1, rule2v1), excludable: Set(success1), resolutions: Set(), withdrawals: Set(),
  }

  action readyInit = init.expect(safety)
    .then(createExecution(1)).expect(safety)
    .then(claimExecution(1, 1)).expect(safety)
    .then(requestStart(t1)).expect(safety)
    .then(authorizeStart(t1)).expect(safety)
    .then(receiveGrant(t1)).expect(safety)
    .then(moveClockTo(2)).expect(safety)
    .then(expireLease(1)).expect(safety)
    .then(replaceExecution(1, 2)).expect(safety)
    .then(claimExecution(2, 2)).expect(safety)
    .then(requestStart(t2)).expect(safety)
    .then(authorizeStart(t2)).expect(safety)
    .then(receiveGrant(t2)).expect(safety)
    .then(callExternal(t1)).expect(safety)
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .then(callExternal(t2)).expect(safety)
    .then(completeAtResource(2, Failure)).expect(safety)
    .then(publishCompletion(t2)).expect(safety)
    .then(receiveReport(failure2)).expect(safety)

  def validExclusion: Decision =
    proposeDecision(authority.durable, success1, ExcludeFromJudgment, Operator(1))

  def invalidProposal: Decision =
    if (BUG == 1) { ...validExclusion, actor: Operator(2) }
    else if (BUG == 2) { ...validExclusion, actor: AutomaticRule({ id: 3, version: 1 }) }
    else { ...validExclusion, reviewedRevision: 7 }

  action newEvidenceInit = readyInit
    .then(queryExternal(1, 3)).expect(safety)
    .then(receiveReport(querySuccess)).expect(safety)

  action invalidatedDispositionInit = readyInit
    .then(reconcileDecision(policy, validExclusion)).expect(safety)
    .then(queryExternal(1, 3)).expect(safety)
    .then(receiveReport(querySuccess)).expect(safety)

  pure val originalCommand: ReconciliationCommand = {
    id: 1, decision: {
      kind: ExcludeFromJudgment, report: success1, actor: Operator(1), basis: ContractExclusion,
      reviewedRevision: 7, evidence: Set(), supersedes: Set(),
    },
  }

  pure val originalRecord: CommandRecord = {
    command: originalCommand, outcomes: List(), decisionIndex: 0,
  }

  action committedCommandInit = readyInit
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, originalCommand)).expect(commandSafety)

  action replayPendingInit = committedCommandInit
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)

  action newEvidencePendingInit = newEvidenceInit
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)

  action laterFailurePendingInit = committedCommandInit
    .then(finishFailure(2)).expect(commandSafety)
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)

  action staleReplayPendingInit = committedCommandInit
    .then(queryExternal(1, 3)).expect(commandSafety)
    .then(receiveReport(querySuccess)).expect(commandSafety)
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)

  action earlyReplyInit = readyInit
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)

  action rejectedConditionPendingInit = readyInit
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand({ ...policy, excludable: Set() }, originalCommand)).expect(commandSafety)
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)

  action rejectedStalePendingInit = newEvidenceInit
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)
    .then(receiveReconciliationCommand(policy, originalCommand)).expect(commandSafety)
    .then(queryExternal(1, 4)).expect(commandSafety)
    .then(receiveReport({ ...querySuccess, id: 4 })).expect(commandSafety)
    .then(sendReconciliationCommand(originalCommand)).expect(commandSafety)
}
