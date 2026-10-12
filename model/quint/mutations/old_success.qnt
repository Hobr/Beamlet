// Intentionally broken rules; each initializer follows real guarded transitions.
module oldSuccessMutation {

  import beamletCore.* from "../beamletCore"
  export beamletCore.*

  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }

  pure val t2: Token = { exec: 2, worker: 2, incarnation: 1, generation: 1 }

  pure val success1: Report = { id: 2, exec: 1, kind: Success, value: 0, origin: ByWorker(t1) }

  pure val failure2: Report = { id: 2, exec: 2, kind: Failure, value: 0, origin: ByWorker(t2) }

  pure val failed2: Outcome = { kind: OutcomeFailed, value: 0, exec: Current(2) }

  action mutantInit = init.expect(safety)
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

  // This was insufficient: every attempt is known, yet old success still needs a decision.
  action mutantStep = all {
    authority.online, authority.durable.phase == Open,
    authority.durable.current == Current(2), noConflicts(authority.durable),
    authority.durable.attempts.get(2).knowledge == FailureKnown,
    hasEvidence(authority.durable, 2, Failure), noUnresolvedRisk(authority.durable),
    authority' = { ...authority, durable: applyCommit(authority.durable, failed2) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  val mutantInvariant = failureRespectsOldSuccess

  run mutationCaughtTest = mutantInit.expect(safety)
    .then(mutantStep).expect(not(mutantInvariant) and not(safety))
}
