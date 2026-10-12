module sharedScenarios {
  import sharedProtocol.* from "../../contracts/shared"
  export sharedProtocol.*
  action receiveObjectQuery(i: int, e: int, value: int): bool = {
    val r: Report = { id: 3, exec: e, kind: Success, value: value, origin: ByQuery }
    all { multiReceive(i, scoped(i, ResultReport(r)), r), holdObject }
  }
  run sameVersionOnlyOneWriteTest = sharedBothInit.expect(sharedSafety and mismatchWitness)
    .expect(sharedObject.version == 1 and sharedObject.content == 1)
    .expect(objectReceipt(sharedObject, objectRequest(2)).value == 2)
  run reverseArrivalLetsOtherIntentWinTest = sharedRunningInit.then(executeObject(2, 1))
    .then(executeObject(1, 1)).expect(sharedSafety and mismatchWitness)
    .expect(sharedObject.content == 2 and objectReceipt(sharedObject, objectRequest(1)).value == 2)
  run replayOriginalKeyDoesNotWriteAgainTest = sharedBothInit.then(replayObject(1)).then(replayObject(2))
    .expect(sharedSafety and objectReplayWitness and sharedObject.writes.length() == 1)
  run versionMismatchIsSuccessfulBusinessResultTest = sharedBothInit.then(queryObject(2, 1))
    .then(receiveObjectQuery(2, 1, 2)).expect(sharedSafety)
    .expect(multiStore.intents.get(2).ledger.outcomes == List({ kind: OutcomeSucceeded, exec: Current(1), value: 2 }))
  run externalCommitDoesNotImplyOutcomeTest = sharedAppliedInit.expect(sharedSafety)
    .expect(multiStore.intents.get(1).ledger.phase == Open and sharedObject.version == 1)
  run workerLossRecoversOriginalReceiptTest = sharedAppliedInit
    .then(all { sharedWorkerCrash(1), holdObject }).then(queryObject(1, 1))
    .then(receiveObjectQuery(1, 1, 1)).expect(sharedSafety and objectRecoveryWitness)
    .expect(sharedObject.writes.length() == 1 and multiStore.intents.get(1).ledger.phase == Closed)
  run authorityRestartAfterResourceWriteTest = sharedAppliedInit
    .then(all { multiAvailability(false), holdObject }).then(all { multiAvailability(true), holdObject })
    .then(queryObject(1, 1)).then(receiveObjectQuery(1, 1, 1)).expect(sharedSafety)
  run twoIndependentOutcomesReflectSeparateReceiptsTest = sharedBothInit
    .then(queryObject(1, 1)).then(receiveObjectQuery(1, 1, 1))
    .then(queryObject(2, 1)).then(receiveObjectQuery(2, 1, 2)).expect(sharedSafety and bothOutcomesWitness)
  run noReceiptCannotBeQueriedAsCompletionTest = sharedRunningInit.expect(sharedSafety)
    .then(queryObject(1, 1).fail())
  run newExecutionReusesOriginalResourceReceiptTest = sharedAppliedInit
    .then(all { multiClockMove(2), holdObject }).then(all { multiExpire(1, 1), holdObject })
    .then(all { multiReplace(1, 1, 2), holdObject })
    .then(all { multiClaim(1, 2, 2), holdObject }).then(all { multiRequest(1, t2), holdObject })
    .then(all { multiAuthorize(1, t2, sharedHandler), holdObject })
    .then(all { multiGrant(1, scoped(1, StartReply(t2)), t2), holdObject })
    .then(all { multiCall(1, t2), holdObject }).then(executeObject(1, 2))
    .expect(sharedSafety and objectReplayWitness and sharedObject.writes.length() == 1)
}
