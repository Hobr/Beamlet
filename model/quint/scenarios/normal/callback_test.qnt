module normalCallbackTests {
  import normalSubmissionTests.* from "./submission_test"
  export normalSubmissionTests.*

  run releasedWorkerCallbackWithoutQueryTest = callbackReleasedInit.expect(normalSafety)
    .expect(not(supportsQuery(usage, 1)))
    .then(normalCrashCoordinator).then(normalComplete(1, Success, 2))
    .then(emitCallback(callbackReport(external, 1, 1, 3), true))
    .then(normalRestartCoordinator).then(normalReceive(callbackReport(external, 1, 1, 3)))
    .then(readFacts).expect(normalSafety)
    .expect(not(workers.get(1).alive) and releasedCompletionWitness)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, exec: Current(1), value: 2 }))

  run completionBeforePendingCallbackTest = callbackRunningInit
    .then(normalComplete(1, Success, 1)).then(emitCallback(callbackReport(external, 1, 1, 3), true))
    .then(normalReceive(callbackReport(external, 1, 1, 3))).then(normalPending(t1))
    .then(normalReceive(pendingReport(t1))).expect(normalSafety)
    .expect(authority.durable.attempts.get(1).phase == Resolved and succeededReached)

  run expiredLeaseCallbackTest = callbackReleasedInit.then(normalClock(2)).then(normalExpire(1))
    .expect(authority.durable.attempts.get(1).phase == Waiting)
    .then(normalComplete(1, Success, 1)).then(emitCallback(callbackReport(external, 1, 1, 3), true))
    .then(normalReceive(callbackReport(external, 1, 1, 3))).expect(normalSafety).expect(succeededReached)

  run callbackCorrelationBeforeInvocationTest = preparedInit
    .then(normalAuthorize(t1, callbackHandler)).expect(normalSafety)
    .expect(authority.durable.attempts.get(1).completion == CallbackBinding(1))
    .expect(external.invocations.length() == 0)
    .then(normalGrant(t1)).then(normalCall(t1)).expect(normalSafety)

  run callbackRejectionTest = callbackReleasedInit.then(normalComplete(1, Success, 1))
    .expect(not(canCallback(usage, authority.durable, external, callbackReport(external, 1, 1, 3), false)))
    .expect(not(canCallback(usage, authority.durable, external, callbackReport(external, 1, 9, 3), true)))
    .expect(not(canCallback(usage, authority.durable, external,
      { ...callbackReport(external, 1, 1, 3), value: 2 }, true)))
    .expect(normalSafety).then(emitCallback(callbackReport(external, 1, 1, 3), false).fail())

  run wrongCallbackCorrelationDisabledTest = callbackReleasedInit.then(normalComplete(1, Success, 1))
    .expect(normalSafety).then(emitCallback(callbackReport(external, 1, 9, 3), true).fail())

  run callbackDuplicateAndRebootTest = callbackReleasedInit.then(normalComplete(1, Success, 1))
    .then(emitCallback(callbackReport(external, 1, 1, 3), true))
    .then(normalReceive(callbackReport(external, 1, 1, 3)))
    .then(normalCrashCoordinator).then(normalRestartCoordinator)
    .then(normalLoseReceipt).then(normalDuplicate(callbackReport(external, 1, 1, 3)))
    .expect(normalSafety).expect(authority.durable.reports.size() == 2)
    .expect(authority.durable.outcomes.length() == 1)

  action normalLoseReceipt = all {
    loseMessage(StoredReceipt(callbackReport(external, 1, 1, 3))), usage' = usage,
  }

  run cancellationBeforeCallbackPreservesLateEvidenceTest = callbackReleasedInit
    .then(normalCancel).then(normalComplete(1, Success, 2))
    .then(emitCallback(callbackReport(external, 1, 1, 3), true))
    .then(normalReceive(callbackReport(external, 1, 1, 3))).expect(normalSafety)
    .expect(authority.durable.reports.contains(callbackReport(external, 1, 1, 3)))
    .expect(authority.durable.outcomes == List({ kind: OutcomeCancelled, exec: NoCurrent, value: 0 }))

  run callbackCompletionBeforeCancellationTest = callbackReleasedInit.then(normalComplete(1, Success, 2))
    .then(emitCallback(callbackReport(external, 1, 1, 3), true))
    .then(normalReceive(callbackReport(external, 1, 1, 3))).expect(normalSafety)
    .then(normalCancel.fail())

  run unsupportedPendingDisabledTest = syncRunningInit
    .expect(not(supportsPending(usage, 1))).expect(normalSafety).then(normalPending(t1).fail())

  run unsupportedPendingReceiveDisabledTest = syncRunningInit
    .expect(normalSafety).then(normalReceiveConflict(pendingReport(t1)).fail())

  run unsupportedQueryDisabledTest = callbackReleasedInit
    .expect(not(supportsQuery(usage, 1))).expect(normalSafety).then(normalQuery(1, 3).fail())

  run queryCapabilityCompletesWithoutWorkerTest = preparedInit
    .then(normalAuthorize(t1, queryHandler)).then(normalGrant(t1)).then(normalCall(t1))
    .then(releaseWorker(1)).then(normalComplete(1, Success, 2)).then(normalQuery(1, 3))
    .then(normalReceive(queryReport(external, 1, 3))).expect(normalSafety)
    .expect(succeededReached and not(workers.get(1).alive))

  run incompatibleHandlerDisabledTest = preparedInit
    .expect(not(compatible(usage, { ...syncHandler, operation: 2 })))
    .expect(normalSafety).then(normalAuthorize(t1, { ...syncHandler, operation: 2 }).fail())

  run compatibleHandlerReleaseAllowedTest = preparedInit
    .then(normalAuthorize(t1, { ...syncHandler, id: 9 })).then(normalGrant(t1)).then(normalCall(t1))
    .expect(normalSafety).expect(usage.bindings.get(1) == bindingFor(usage, { ...syncHandler, id: 9 }))
}
