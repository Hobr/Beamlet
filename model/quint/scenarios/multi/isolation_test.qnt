module multiIntentIsolationTests {
  import multiIntentFixtures.* from "./fixtures"
  export multiIntentFixtures.*

  run independentAgentsCompleteTest = independentInit
    .then(startFirst(1, 1, syncHandler)).then(startFirst(2, 2, callbackHandler))
    .then(finishCallback(2, Success, 2)).then(finishWorker(1, t1, Success, 1))
    .then(multiResolve(1, { request: request, result: CreatedIntent(1) }))
    .then(multiResolve(2, { request: requestB, result: CreatedIntent(2) }))
    .then(readDependency(1, refA)).then(readDependency(2, { call: 2, slot: 2, intent: 2 }))
    .then(collectRound(2, 2)).then(collectRound(1, 1)).expect(multiSafety and independentWitness)

  run sharedWorkerLocalIdsDoNotCollideTest = bothRunningInit.expect(multiSafety)
    .expect(sharedWorkerWitness and resources.get(1).invocations.nth(0).token == resources.get(2).invocations.nth(0).token)
    .expect(focused(multiStore.intents.get(1).use).context != focused(multiStore.intents.get(2).use).context)

  run completionAndHistoryStayLocalTest = bothRunningInit.then(finishCallback(1, Success, 1)).expect(multiSafety)
    .expect(multiStore.intents.get(2).ledger.phase == Open and multiStore.intents.get(2).ledger.reports.size() == 0)
    .then(finishCallback(2, Failure, 2)).expect(multiSafety and bothClosedWitness)
    .expect(multiStore.intents.get(1).ledger.outcomes.nth(0).value == 1)
    .expect(multiStore.intents.get(2).ledger.outcomes.nth(0).kind == OutcomeFailed)

  run wrongIntentWorkerReportRejectedTest = joinedInit.then(startFirst(1, 1, syncHandler))
    .then(startFirst(2, 1, syncHandler)).then(multiComplete(1, 1, Success, 1)).then(multiPublish(1, t1, false))
    .expect(reportSourceValid(multiStore.intents.get(2).ledger, workerValue(t1, Success, 1))).expect(multiSafety)
    .then(multiReceive(2, scoped(1, ResultReport(workerValue(t1, Success, 1))), workerValue(t1, Success, 1)).fail())

  run wrongIntentGrantRejectedTest = joinedInit.then(multiCreate(1, 1)).then(multiClaim(1, 1, 1))
    .then(multiRequest(1, t1)).then(multiAuthorize(1, t1, syncHandler)).expect(multiSafety)
    .then(multiGrant(2, scoped(1, StartReply(t1)), t1).fail())

  run wrongIntentReceiptRejectedTest = bothRunningInit.then(finishCallback(1, Success, 1)).expect(multiSafety)
    .then(multiReceipt(2, scoped(1, StoredReceipt(callbackValue(1, Success, 1))), callbackValue(1, Success, 1)).fail())

  run callbackCorrelationCannotCrossIntentTest = bothRunningInit.then(multiComplete(1, 1, Success, 1))
    .then(multiComplete(2, 1, Success, 1)).expect(multiSafety)
    .then(multiEmitCallback(2, callbackValue(1, Success, 1), true).fail())

  run callbackSenderMustBeVerifiedTest = bothRunningInit.then(multiComplete(1, 1, Success, 1)).expect(multiSafety)
    .then(multiEmitCallback(1, callbackValue(1, Success, 1), false).fail())

  run sharedWorkerCrashClearsBothLocalSlotsTest = releasedPairInit.expect(multiSafety)
    .expect(INTENTS.forall(i => not(localFor(i, 1).alive) and localFor(i, 1).grants.size() == 0))
    .then(sharedWorkerRestart(1)).expect(multiSafety).expect(multiSafety)
    .then(multiGrant(1, scoped(1, StartReply(t1)), t1).fail())

  run callbacksCompleteBothAfterReleaseTest = releasedPairInit.then(multiAvailability(false))
    .then(multiComplete(1, 1, Success, 1)).then(multiComplete(2, 1, Failure, 2))
    .then(multiEmitCallback(2, callbackValue(2, Failure, 2), true))
    .then(multiEmitCallback(1, callbackValue(1, Success, 1), true)).then(multiAvailability(true))
    .then(multiReceive(2, scoped(2, ResultReport(callbackValue(2, Failure, 2))), callbackValue(2, Failure, 2)))
    .then(multiReceive(1, scoped(1, ResultReport(callbackValue(1, Success, 1))), callbackValue(1, Success, 1)))
    .expect(multiSafety and multiReleasedCompletionWitness)

  run unknownDoesNotBlockOtherIntentTest = unknownPairInit.then(finishCallback(2, Success, 2))
    .expect(multiSafety and unknownIsolationWitness).expect(multiSafety)
    .then(multiStop(1, 1).fail())

  run cancelDoesNotCancelSiblingTest = bothRunningInit.then(multiCancel(1)).then(finishCallback(2, Success, 2))
    .expect(multiSafety and bothClosedWitness)
    .expect(multiStore.intents.get(1).ledger.outcomes.nth(0).kind == OutcomeCancelled)
    .expect(multiStore.intents.get(2).ledger.outcomes.nth(0).kind == OutcomeSucceeded)

  run callbackRedeliveryDoesNotDuplicateOutcomeTest = completePairInit
    .then(multiReceipt(1, scoped(1, StoredReceipt(callbackValue(1, Success, 1))), callbackValue(1, Success, 1)))
    .then(multiRedeliver(1, callbackValue(1, Success, 1))).then(multiDuplicate(1, callbackValue(1, Success, 1)))
    .expect(multiSafety and bothClosedWitness)
    .expect(INTENTS.forall(i => multiStore.intents.get(i).ledger.outcomes.length() == 1))

  run retryOneIntentKeepsOtherBindingTest = retryPairInit.then(multiCall(1, t2))
    .then(finishWorker(1, t2, Success, 1)).then(finishCallback(2, Success, 2)).expect(multiSafety and bothClosedWitness)
    .expect(multiStore.intents.get(1).use.launches.length() == 2 and multiStore.intents.get(2).use.launches.length() == 1)

  run originalWindowStillConstrainsRetryTest = retryPairInit.then(multiClockMove(4)).expect(multiSafety)
    .then(multiCall(1, t2).fail())

  run wallClockRollbackCannotReviveEitherLeaseTest = bothRunningInit.then(multiClockMove(2))
    .then(multiExpire(1, 1)).then(multiExpire(2, 1)).then(multiClockMove(0)).expect(multiSafety)
    .expect(INTENTS.forall(i => not(leaseValid(multiStore.intents.get(i).ledger, t1, multiClock))))
}
