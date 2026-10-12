module normalRecoveryTests {
  import normalRetryTests.* from "./retry_test"
  export normalRetryTests.*
  import normalRecoveryActions.* from "../../normal/recovery"
  export normalRecoveryActions.*

  run lostCallbackRedeliveredAfterRestartTest = callbackReleasedInit
    .then(normalComplete(1, Success, 2)).then(emitCallback(callbackReport(external, 1, 1, 3), true))
    .then(all { loseMessage(ResultReport(callbackReport(external, 1, 1, 3))), usage' = usage })
    .then(normalCrashCoordinator).then(normalRestartCoordinator)
    .then(redeliverCallback(callbackReport(external, 1, 1, 3)))
    .then(normalReceive(callbackReport(external, 1, 1, 3))).expect(normalSafety)
    .expect(callbackRedeliveryWitness and recoveryCompletionWitness and succeededReached)

  run lostAuthorizationReplyUsesOriginalBindingTest = preparedInit
    .then(normalAuthorize(t1, callbackHandler))
    .then(all { loseMessage(StartReply(t1)), usage' = usage })
    .then(normalCrashCoordinator).then(normalRestartCoordinator)
    .then(normalRequest(t1)).then(normalResendGrant(t1)).then(normalGrant(t1)).then(normalCall(t1))
    .expect(normalSafety).expect(authority.durable.starts.length() == 1)
    .expect(usage.bindings.get(1) == bindingFor(usage, callbackHandler))

  run earlyStopWhenIdempotencyExpiresTest = retryPendingInit.then(normalClock(4))
    .then(normalStop(1)).expect(normalSafety).expect(policyStopWitness and failedReached)
    .expect(authority.durable.attempts.get(2).exists == false)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(1), value: 2 }))

  run availableRetryCannotStopEarlyTest = retryPendingInit.expect(normalSafety).then(normalStop(1).fail())

  run unknownCannotStopAfterWindowExpiresTest = retryRunningInit.then(normalClock(4)).then(normalExpire(1))
    .expect(stopRequired(usage, authority.durable)).expect(normalSafety).then(normalStop(1).fail())

  run missingIdempotencyStopsKnownFailureTest = normalInit
    .then(sendSubmission({ ...request, definition: { ...definition, policy: RetryOnce } }))
    .then(receiveSubmission({ ...request, definition: { ...definition, policy: RetryOnce } }))
    .then(normalCreate(1)).then(normalClaim(1, 1)).then(normalRequest(t1))
    .then(normalAuthorize(t1, syncHandler)).then(normalGrant(t1)).then(normalCall(t1))
    .then(normalComplete(1, Failure, 2)).then(normalPublish(t1))
    .then(normalReceive(completionReport(external, t1))).expect(normalSafety)
    .expect(failedReached and authority.durable.attempts.get(2).exists == false)

  run newHandlerCannotExtendOriginalWindowTest = retryPendingInit.then(normalReplace(1, 2))
    .then(normalClaim(2, 2)).then(normalRequest(t2))
    .then(normalAuthorize(t2, { ...idempotentHandler, validThrough: 6 })).then(normalGrant(t2))
    .then(normalClock(4)).expect(normalSafety).then(normalCall(t2).fail())

  run earlyStopAfterLeaseRollbackTest = retryPendingInit.then(normalClock(4)).then(normalClock(0))
    .then(normalStop(1)).expect(normalSafety).expect(failedReached and usage.contractTime == 4)

  run recoveryRestartRejectsOldGrantTest = preparedInit.then(normalAuthorize(t1, callbackHandler))
    .then(releaseWorker(1)).then(normalRestartWorker(1)).then(normalDiscardOld(t1))
    .expect(normalSafety).expect(oldGrantRejectedReached)
    .expect(usage.bindings.get(1) == bindingFor(usage, callbackHandler))
    .expect(not(canCall(workers.get(1), external, t1)))
}
