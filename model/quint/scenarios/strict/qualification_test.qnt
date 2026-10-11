// Deterministic scenarios using the shared fixture and real guarded transitions.
module strictQualificationTests {
  import strictFixtures.* from "./fixtures"
  export strictFixtures.*

  // fail() is deliberately last: in Quint 0.32 it does not supply a post-state.
  run closedCreateIsDisabledTest = runningInit
    .then(cancelIntent).expect(safety)
    .then(createExecution(2).fail())

  run staleAuthorizationIsDisabledTest = preparedInit
    .then(requestStart(t1)).expect(safety)
    .then(moveClockTo(2)).expect(safety)
    .then(claimExecution(1, 2)).expect(safety)
    .then(moveClockTo(0)).expect(safety)
    .then(authorizeStart(t1).fail())

  run cancelWithoutExecutionTest = init.expect(safety)
    .then(cancelIntent).expect(safety)
    .expect(authority.durable.current == NoCurrent)
    .expect(EXECUTIONS.forall(e => not(authority.durable.attempts.get(e).exists)))
    .expect(authority.durable.outcomes == List({ kind: OutcomeCancelled, exec: NoCurrent }))

  run cancellationBeforeGrantDeliveryTest = grantedInit
    .then(cancelIntent).expect(safety)
    .then(receiveGrant(t1)).expect(safety)
    .then(callExternal(t1)).expect(safety)
    .expect(cancelledReached and external.effects == Set(1))

  run oldReportAfterWorkerRestartTest = runningInit
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(crashWorker(1)).expect(safety)
    .then(restartWorker(1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .expect(workers.get(1).incarnation == 2 and succeededReached)

  run completionBeforePendingIsProducedTest = runningInit
    .then(completeAtResource(1, Success)).expect(safety)
    .then(queryExternal(1, 3)).expect(safety)
    .then(receiveReport({ id: 3, exec: 1, kind: Success, origin: ByQuery })).expect(safety)
    .expect(succeededReached)
    // The worker may learn/return Pending after the authority accepts completion.
    .then(publishPending(t1)).expect(safety)
    .then(receiveReport(pendingReport(t1))).expect(safety)
    .expect(authority.durable.attempts.get(1).phase == Resolved)
    .expect(authority.durable.outcomes == authority.durable.firstOutcome)

  run boundsTest = init.expect(all {
    WORKERS == Set(1, 2), EXECUTIONS == Set(1, 2), REPORT_IDS.contains(1), REPORT_IDS.contains(2),
    CLOCK_VALUES.contains(0), TTL > 0, MAX_INCARNATION >= 2, MAX_GENERATION >= 2,
  })

  run authorizationIsNotExecutionTest = grantedInit
    .expect(authority.durable.attempts.get(1).phase == StartAuthorized)
    .expect(external.invocations.length() == 0 and authority.durable.outcomes.length() == 0)
    .then(receiveGrant(t1)).expect(safety)
    .expect(external.invocations.length() == 0)
    .then(callExternal(t1)).expect(safety)
    .then(completeAtResource(1, Success)).expect(safety)
    .expect(external.finished.get(1) == ResourceSucceeded)
    .expect(authority.durable.attempts.get(1).knowledge == NoKnowledge)
    .expect(authority.durable.outcomes.length() == 0)

  run successCommitTest = runningInit
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, exec: Current(1) }))
    .expect(authority.durable.reports.contains(success1))
    .expect(authority.durable.history.select(a => a.kind == OutcomeStored).length() == 1)
}
