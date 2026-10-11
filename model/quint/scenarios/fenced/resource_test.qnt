// Deterministic scenarios using the shared fixture and real guarded transitions.
module fencedResourceTests {
  import fencedFixtures.* from "./fixtures"
  export fencedFixtures.*

  run fencedReplacementTest = grantHeldInit
    .then(fenceAtResource(1, 3)).expect(safety)
    .expect(external.noFuture.contains(1))
    .expect(authority.durable.attempts.get(1).knowledge == NoKnowledge)
    .then(receiveReport(excluded1)).expect(safety)
    .then(replaceExecution(1, 2)).expect(safety)
    .expect(not(canCall(workers.get(1), external, t1)))
    .then(claimExecution(2, 2)).expect(safety)
    .then(requestStart(t2)).expect(safety)
    .then(authorizeStart(t2)).expect(safety)
    .then(receiveGrant(t2)).expect(safety)
    .then(callExternal(t2)).expect(safety)
    .then(completeAtResource(2, Success)).expect(safety)
    .then(publishCompletion(t2)).expect(safety)
    .then(receiveReport(success2)).expect(safety)
    .expect(external.effects == Set(2))
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, exec: Current(2) }))

  run fencedOldInvocationIsDisabledTest = grantHeldInit
    .then(fenceAtResource(1, 3)).expect(safety)
    .then(callExternal(t1).fail())
}
