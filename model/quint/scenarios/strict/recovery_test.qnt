// Deterministic scenarios using the shared fixture and real guarded transitions.
module strictRecoveryTests {
  import strictFixtures.* from "./fixtures"
  export strictFixtures.*

  run expiryAndClockRollbackTest = grantedInit
    .then(receiveGrant(t1)).expect(safety)
    .then(moveClockTo(2)).expect(safety)
    .then(expireLease(1)).expect(safety)
    .expect(authority.durable.attempts.get(1).phase == Unknown)
    .then(moveClockTo(0)).expect(safety)
    .expect(not(canRenew(authority.durable, t1, clock)))
    .expect(not(canClaim(authority.durable, 1, clock)))
    .expect(not(canReplace(authority.durable, 1, 2)))
    // An already authorized old worker can still invoke after persisted expiry.
    .then(callExternal(t1)).expect(safety)
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .expect(succeededReached and lateReportReached)

  run preparedReassignmentTest = preparedInit
    .then(requestStart(t1)).expect(safety)
    .then(moveClockTo(2)).expect(safety)
    .then(claimExecution(1, 2)).expect(safety)
    .expect(authority.durable.attempts.get(1).lease.generation == 2)
    .then(moveClockTo(0)).expect(safety)
    .expect(not(canRenew(authority.durable, t1, clock)))
    .expect(not(canAuthorize(authority.durable, t1, clock)))
    .then(requestStart(reclaimed)).expect(safety)
    .then(authorizeStart(reclaimed)).expect(safety)
    .then(receiveGrant(reclaimed)).expect(safety)
    .then(callExternal(reclaimed)).expect(safety)
    .expect(external.invocations.length() == 1)
    .expect(authority.durable.starts.length() == 1)

  run restartedWorkerCannotInheritGrantTest = grantedInit
    .then(crashWorker(1)).expect(safety)
    .then(restartWorker(1)).expect(safety)
    .expect(not(canReceiveGrant(workers.get(1), t1)))
    .then(discardOldGrant(t1)).expect(safety)
    .expect(not(canCall(workers.get(1), external, t1)))
    .expect(workers.get(1).incarnation == 2 and external.invocations.length() == 0)
    .expect(authority.durable.attempts.get(1).grant == StartGrant(t1))

  run coordinatorRestartPreservesLeaseTest = preparedInit
    .then(moveClockTo(1)).expect(safety)
    .then(crashCoordinator).expect(safety)
    .then(restartCoordinator).expect(safety)
    .then(renewLease(t1)).expect(safety)
    .expect(authority.durable.attempts.get(1).lease.generation == 1)
    .expect(authority.durable.attempts.get(1).lease.expiresAt == 3)
    .expect(authority.durable.history.length() == 2)
    .then(requestStart(t1)).expect(safety)
    .then(authorizeStart(t1)).expect(safety)

  run pendingSurvivesWorkerLossTest = runningInit
    .then(publishPending(t1)).expect(safety)
    .then(receiveReport(pendingReport(t1))).expect(safety)
    .then(moveClockTo(2)).expect(safety)
    .then(expireLease(1)).expect(safety)
    .expect(authority.durable.attempts.get(1).phase == Waiting)
    .then(crashWorker(1)).expect(safety)
    .then(crashCoordinator).expect(safety)
    .then(completeAtResource(1, Success)).expect(safety)
    .then(queryExternal(1, 3)).expect(safety)
    .then(restartCoordinator).expect(safety)
    .then(receiveReport({ id: 3, exec: 1, kind: Success, value: 0, origin: ByQuery })).expect(safety)
    .expect(succeededReached and lateReportReached)
    .expect(not(workers.get(1).alive))

  run negativeQueryDoesNotAuthorizeRetryTest = grantedInit
    .then(receiveGrant(t1)).expect(safety)
    .then(queryExternal(1, 3)).expect(safety)
    .then(receiveReport(notFound1)).expect(safety)
    .expect(authority.durable.attempts.get(1).negativeSeen)
    .expect(authority.durable.attempts.get(1).knowledge == NoKnowledge)
    .then(moveClockTo(2)).expect(safety)
    .then(expireLease(1)).expect(safety)
    .expect(not(canReplace(authority.durable, 1, 2)))
    .expect(not(canCommit(authority.durable, { kind: OutcomeFailed, value: 0, exec: Current(1) })))
    .then(callExternal(t1)).expect(safety)
    .expect(external.effects == Set(1) and external.noFuture.size() == 0)
    .expect(authority.durable.outcomes.length() == 0)

  run lostReportAndLostAckTest = runningInit
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(loseMessage(ResultReport(success1))).expect(safety)
    .then(resendReport(success1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .then(loseMessage(StoredReceipt(success1))).expect(safety)
    .then(acknowledgeDuplicate(success1)).expect(safety)
    .then(receiveReceipt(success1)).expect(safety)
    .expect(reportResentReached and duplicateReportReached and receiptReached)
    .expect(authority.durable.reports.size() == 1 and authority.durable.history.length() == 5)
    .expect(authority.durable.outcomes.length() == 1)

  run duplicateGrantDoesNotInvokeAgainTest = runningInit
    .then(requestStart(t1)).expect(safety)
    .then(resendGrant(t1)).expect(safety)
    .expect(not(canReceiveGrant(workers.get(1), t1)))
    .then(discardDuplicateGrant(t1)).expect(safety)
    .expect(not(canCall(workers.get(1), external, t1)))
    .expect(duplicateGrantReached and external.invocations.length() == 1)
}
