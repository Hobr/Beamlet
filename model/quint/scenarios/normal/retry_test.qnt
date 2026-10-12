module normalRetryTests {
  import normalCallbackTests.* from "./callback_test"
  export normalCallbackTests.*

  run failedCompletionAtomicTest = syncRunningInit.then(normalComplete(1, Failure, 2))
    .then(normalPublish(t1)).then(normalReceive(completionReport(external, t1))).expect(normalSafety)
    .expect(failureAtomicWitness and authority.durable.phase == Closed)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(1), value: 2 }))
    .expect(authority.durable.reports.size() == 1)

  run retryPolicyKeepsFirstFailureOpenTest = retryPendingInit.expect(normalSafety)
    .expect(authority.durable.phase == Open and authority.durable.outcomes.length() == 0)
    .expect(not(stopRequired(usage, authority.durable)))

  run validIdempotentRetryUsesOriginalContextTest = retryPendingInit
    .expect(not(ALLOW_REPEAT) and idempotencyValid(usage, 1, clock))
    .then(normalReplace(1, 2)).then(normalClaim(2, 2)).then(normalRequest(t2))
    .then(normalAuthorize(t2, { ...idempotentHandler, id: 9 }))
    .then(normalGrant(t2)).then(normalCall(t2)).then(normalComplete(2, Success, 1))
    .then(normalPublish(t2)).then(normalReceive(completionReport(external, t2))).expect(normalSafety)
    .expect(retryWitness and succeededReached)
    .expect(external.invocations.length() == 2)
    .expect(match usage.bindings.get(2) {
      | NoHandler => false | BoundHandler(b) => b.context == 1 and b.definition.policy == RetryOnce
    })

  run expiredIdempotencyDoesNotPermitRetryTest = retryPendingInit.then(normalClock(4))
    .expect(not(idempotencyValid(usage, 1, clock)))
    .expect(normalSafety).expect(authority.durable.phase == Open and authority.durable.current == Current(1))
    .then(normalReplace(1, 2).fail())

  run noIdempotencyDoesNotPermitRetryTest = normalInit
    .then(sendSubmission({ ...request, definition: { ...definition, policy: RetryOnce } }))
    .then(receiveSubmission({ ...request, definition: { ...definition, policy: RetryOnce } }))
    .then(normalCreate(1)).then(normalClaim(1, 1)).then(normalRequest(t1))
    .then(normalAuthorize(t1, syncHandler)).then(normalGrant(t1)).then(normalCall(t1))
    .then(normalComplete(1, Failure, 2)).then(normalPublish(t1))
    .then(normalReceive(completionReport(external, t1)))
    .expect(normalSafety).then(normalReplace(1, 2).fail())

  run retryExhaustedFailureAtomicTest = retryPendingInit.then(normalReplace(1, 2))
    .then(normalClaim(2, 2)).then(normalRequest(t2)).then(normalAuthorize(t2, idempotentHandler))
    .then(normalGrant(t2)).then(normalCall(t2)).then(normalComplete(2, Failure, 2))
    .then(normalPublish(t2)).then(normalReceive(completionReport(external, t2))).expect(normalSafety)
    .expect(failureAtomicWitness and failedReached)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(2), value: 2 }))

  run unknownBudgetDoesNotCreateFailureTest = retryRunningInit.then(normalClock(2)).then(normalExpire(1))
    .then(readFacts).expect(normalSafety)
    .expect(authority.durable.phase == Open and authority.durable.outcomes.length() == 0)
    .expect(not(canCommit(authority.durable, { kind: OutcomeFailed, exec: Current(1), value: 2 })))

  run clockRollbackDoesNotRenewIdempotencyTest = retryPendingInit.then(normalClock(4)).then(normalClock(0))
    .expect(usage.contractTime == 4).expect(normalSafety).then(normalReplace(1, 2).fail())

  run retryCannotChangeExternalProtocolTest = retryPendingInit.then(normalReplace(1, 2))
    .then(normalClaim(2, 2)).then(normalRequest(t2)).expect(normalSafety)
    .then(normalAuthorize(t2, { ...idempotentHandler, protocol: 2 }).fail())

  run retryCannotDropIdempotencyTest = retryPendingInit.then(normalReplace(1, 2))
    .then(normalClaim(2, 2)).then(normalRequest(t2)).expect(normalSafety)
    .then(normalAuthorize(t2, syncHandler).fail())

  run expiredBeforeInvocationDoesNotCallTest = retryPendingInit.then(normalReplace(1, 2))
    .then(normalClaim(2, 2)).then(normalRequest(t2)).then(normalAuthorize(t2, idempotentHandler))
    .then(normalGrant(t2)).then(normalClock(4)).expect(normalSafety)
    .then(normalCall(t2).fail())

  run handlerSnapshotSurvivesRestartTest = callbackReleasedInit.then(normalCrashCoordinator)
    .then(normalRestartCoordinator).then(normalRestartWorker(1)).expect(normalSafety)
    .expect(usage.bindings.get(1) == bindingFor(usage, callbackHandler))
    .expect(authority.durable.attempts.get(1).completion == CallbackBinding(1))
    .expect(not(canCall(workers.get(1), external, t1)))
}
