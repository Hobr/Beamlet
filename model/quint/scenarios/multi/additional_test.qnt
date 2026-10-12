module multiIntentAdditionalTests {
  import multiIntentCallerTests.* from "./caller_test"
  export multiIntentCallerTests.*

  run duplicateReadCannotCountTwiceTest = partiallyReadInit.expect(multiSafety)
    .then(readDependency(1, refA).fail())

  run unknownCannotBeReadAsFailedOutcomeTest = unknownPairInit.then(resolveJoined).expect(multiSafety)
    .then(readDependency(1, refA).fail())

  run pendingCannotBeReadAsOutcomeTest = releasedPairInit.then(resolveJoined).expect(multiSafety)
    .then(readDependency(1, refA).fail())

  run unsafeReplacementOfUnknownStillRejectedTest = unknownPairInit.then(finishCallback(2, Success, 2))
    .expect(multiSafety and unknownIsolationWitness).then(multiReplace(1, 1, 2).fail())

  run oldGrantActuallyInFlightCannotSurviveSharedWorkerRestartTest = bothRunningInit
    .then(multiRequest(1, t1)).then(multiResendGrant(1, t1)).then(sharedWorkerCrash(1)).then(sharedWorkerRestart(1))
    .expect(multiSafety and multiNetwork.messages.contains(scoped(1, StartReply(t1))))
    .expect(INTENTS.forall(i => localFor(i, 1).incarnation == 2 and localFor(i, 1).grants.size() == 0))
    .then(multiGrant(1, scoped(1, StartReply(t1)), t1).fail())

  run twoExplicitSlotsMayReuseOneTerminalIntentTest = multiInit
    .then(openRound(1, 1, Set(dependencyA, { ...dependencyA, slot: 2 })))
    .then(multiSend(1, request)).then(multiSubmit(1, request))
    .then(multiResolve(1, { request: request, result: CreatedIntent(1) }))
    .then(startFirst(1, 1, callbackHandler)).then(finishCallback(1, Success, 1))
    .then(readDependency(1, refA)).then(readDependency(1, { ...refA, slot: 2 })).then(collectRound(1, 1))
    .expect(multiSafety and joinedWitness and multiStore.catalog.length() == 1)

  run mixedSuccessAndFailureAreCollectedBySlotTest = bothRunningInit.then(resolveJoined)
    .then(finishCallback(1, Failure, 1)).then(finishCallback(2, Success, 2))
    .then(readJoined).then(collectRound(1, 1)).expect(multiSafety and joinedWitness)
    .expect(callerRounds.get(1).results.exists(r => r.slot == 1 and r.outcome.kind == OutcomeFailed))
    .expect(callerRounds.get(1).results.exists(r => r.slot == 2 and r.outcome.kind == OutcomeSucceeded))

  run lostReplyCanRecoverAlreadyClosedBusinessResultTest = completePairInit
    .then(multiLoseSubmissionReply(1, { request: request, result: CreatedIntent(1) }))
    .then(multiSend(1, request)).then(multiSubmit(1, request))
    .then(multiResolve(1, { request: request, result: ExistingIntent({ id: 1,
      outcomes: List({ kind: OutcomeSucceeded, exec: Current(1), value: 1 }) }) }))
    .then(multiResolve(1, { request: requestB, result: CreatedIntent(2) }))
    .then(readJoined).then(collectRound(1, 1)).expect(multiSafety and joinedWitness)
    .expect(INTENTS.forall(i => resources.get(i).invocations.length() == 1))

  run callerRoundIdentitySeparatesTwoRoundsOfOneAgentTest = multiInit
    .then(openRound(1, 1, Set(dependencyA))).then(openRound(1, 2, Set(dependencyB)))
    .then(multiSend(1, request)).then(multiSend(1, requestB))
    .then(multiSubmit(1, request)).then(multiSubmit(1, requestB)).then(resolveJoined)
    .then(startFirst(1, 1, callbackHandler)).then(startFirst(2, 1, callbackHandler))
    .then(finishCallback(2, Success, 2)).then(finishCallback(1, Success, 1))
    .then(readDependency(1, refA)).then(readDependency(1, { ...refB, call: 2 }))
    .then(collectRound(1, 2)).then(collectRound(1, 1)).expect(multiSafety)
    .expect(callerRounds.get(1).results.forall(r => r.intent == 1 and r.call == 1))
    .expect(callerRounds.get(2).results.forall(r => r.intent == 2 and r.call == 2))

  run otherAgentCannotReadThisRoundsReferenceTest = completePairInit.then(resolveJoined).expect(multiSafety)
    .then(readDependency(2, refA).fail())
}
