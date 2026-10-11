// Deterministic scenarios using the shared fixture and real guarded transitions.
module strictLifecycleTests {
  import strictFixtures.* from "./fixtures"
  export strictFixtures.*

  run latePendingCannotRegressTest = runningInit
    .then(publishPending(t1)).expect(safety)
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .then(receiveReport(pendingReport(t1))).expect(safety)
    .expect(authority.durable.attempts.get(1).phase == Resolved)
    .expect(authority.durable.outcomes == authority.durable.firstOutcome)
    .expect(authority.durable.reports.size() == 2)

  run cancellationWinsTest = runningInit
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(cancelIntent).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeCancelled, exec: NoCurrent }))
    .expect(authority.durable.attempts.get(1).phase == Resolved)
    .expect(authority.durable.reports.contains(success1))
    .expect(not(canCreate(authority.durable, 2)))

  run completionWinsTest = runningInit
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .expect(not(canCommit(authority.durable, { kind: OutcomeCancelled, exec: NoCurrent })))
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, exec: Current(1) }))

  run knownFailureCanCloseTest = runningInit
    .then(completeAtResource(1, Failure)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(failure1)).expect(safety)
    .expect(authority.durable.phase == Open and authority.durable.outcomes.length() == 0)
    .then(finishFailure(1)).expect(safety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(1) }))
}
