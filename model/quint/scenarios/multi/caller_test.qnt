module multiIntentCallerTests {
  import multiIntentIsolationTests.* from "./isolation_test"
  export multiIntentIsolationTests.*

  run oneToolCallCollectsTwoDifferentValuesTest = completePairInit.then(resolveJoined).then(readJoined)
    .then(collectRound(1, 1)).expect(multiSafety and joinedWitness)
    .expect(callerRounds.get(1).results.exists(r => r.slot == 1 and r.outcome.value == 1))
    .expect(callerRounds.get(1).results.exists(r => r.slot == 2 and r.outcome.value == 2))

  run oneCompletedDependencyIsInsufficientTest = partiallyReadInit.expect(multiSafety and partialJoinWitness)
    .then(collectRound(1, 1).fail())

  run pendingReportsCannotCompleteToolCallTest = releasedPairInit.then(resolveJoined).expect(multiSafety)
    .then(collectRound(1, 1).fail())

  run unknownKeepsJoinWaitingButPreservesOtherResultTest = unknownPairInit.then(resolveJoined)
    .then(finishCallback(2, Success, 2)).then(readDependency(1, refB)).expect(multiSafety)
    .then(collectRound(1, 1).fail())

  run failedDependencyIsAResultWithoutCancellingSiblingTest = bothRunningInit.then(resolveJoined)
    .then(finishCallback(1, Failure, 1)).then(readDependency(1, refA))
    .expect(multiStore.intents.get(2).ledger.phase == Open).expect(multiSafety)
    .then(collectRound(1, 1).fail())

  run explicitCancellationCanSatisfyOneDependencyTest = bothRunningInit.then(resolveJoined)
    .then(multiCancel(1)).then(readDependency(1, refA)).then(finishCallback(2, Success, 2))
    .then(readDependency(1, refB)).then(collectRound(1, 1)).expect(multiSafety and joinedWitness)

  run agentRestartRebuildsReferencesAndResultsTest = partiallyReadInit.then(crashAgent(1)).then(restartAgent(1))
    .expect(agentLocals.get(1).refs.size() == 0 and agentLocals.get(1).results.size() == 0)
    .expect(callerRounds.get(1).dependencies == Set(dependencyA, dependencyB))
    .then(multiSend(1, request)).then(multiSubmit(1, request))
    .then(multiResolve(1, { request: request, result: ExistingIntent({ id: 1,
      outcomes: List({ kind: OutcomeSucceeded, exec: Current(1), value: 1 }) }) }))
    .then(multiSend(1, requestB)).then(multiSubmit(1, requestB))
    .then(multiResolve(1, { request: requestB, result: ExistingIntent({ id: 2, outcomes: List() }) }))
    .then(finishCallback(2, Success, 2)).then(readJoined).then(collectRound(1, 1))
    .expect(multiSafety and recoveredJoinWitness and multiStore.catalog.length() == 2)

  run lostSubmissionReplyThenAgentCrashReusesOriginalIntentTest = joinedInit
    .then(multiLoseSubmissionReply(1, { request: request, result: CreatedIntent(1) }))
    .then(crashAgent(1)).then(restartAgent(1)).then(multiSend(1, request)).then(multiSubmit(1, request))
    .then(multiResolve(1, { request: request, result: ExistingIntent({ id: 1, outcomes: List() }) }))
    .expect(multiSafety and agentLocals.get(1).refs.contains(refA) and multiStore.catalog.length() == 2)

  run completedToolCallSurvivesCallerRestartTest = completePairInit.then(resolveJoined).then(readJoined)
    .then(collectRound(1, 1)).then(crashAgent(1)).then(restartAgent(1))
    .expect(multiSafety and recoveredJoinWitness)
    .then(collectRound(1, 1).fail())

  run secondAgentCanReuseSameSubmissionIdentityTest = independentInit
    .then(multiSend(2, request)).then(multiSubmit(2, request)).expect(multiSafety)
    .expect(multiNetwork.replies.contains({ agent: 2,
      reply: { request: request, result: ExistingIntent({ id: 1, outcomes: List() }) } }))
    .expect(multiStore.catalog.length() == 2)

  run definitionConflictDoesNotRewriteEitherIntentTest = independentInit
    .then(multiSend(2, { ...request, definition: { ...definition, input: 2 } }))
    .then(multiSubmit(2, { ...request, definition: { ...definition, input: 2 } })).expect(multiSafety)
    .expect(multiNetwork.replies.contains({ agent: 2, reply: {
      request: { ...request, definition: { ...definition, input: 2 } }, result: DefinitionConflict(1) } }))
    .expect(focused(multiStore.intents.get(1).use).request == request)

  run reversedSubmissionArrivalResolvesByIdentityTest = multiInit
    .then(openRound(1, 1, Set(dependencyA, dependencyB)))
    .then(multiSend(1, request)).then(multiSend(1, requestB))
    .then(multiSubmit(1, requestB)).then(multiSubmit(1, request))
    .then(multiResolve(1, { request: request, result: CreatedIntent(2) }))
    .then(multiResolve(1, { request: requestB, result: CreatedIntent(1) })).expect(multiSafety)
    .expect(agentLocals.get(1).refs.contains({ ...refA, intent: 2 }))
    .expect(agentLocals.get(1).refs.contains({ ...refB, intent: 1 }))

  run unkeyedSubmissionsRemainIndependentTest = multiInit.then(multiSend(1, { ...request, identity: Unkeyed }))
    .then(multiSubmit(1, { ...request, identity: Unkeyed })).then(multiSend(2, { ...request, identity: Unkeyed }))
    .then(multiSubmit(2, { ...request, identity: Unkeyed })).expect(multiSafety)
    .expect(multiStore.catalog.length() == 2)

  run sameIntentStillRequiresBothExplicitSlotsToBeReadTest = multiInit
    .then(openRound(1, 1, Set(dependencyA, { ...dependencyA, slot: 2 })))
    .then(multiSend(1, request)).then(multiSubmit(1, request))
    .then(multiResolve(1, { request: request, result: CreatedIntent(1) }))
    .then(startFirst(1, 1, callbackHandler)).then(finishCallback(1, Success, 1))
    .then(readDependency(1, refA)).expect(multiSafety)
    .then(collectRound(1, 1).fail())

  run anotherAgentCannotCollectThisRoundTest = completePairInit.then(resolveJoined).expect(multiSafety)
    .then(collectRound(2, 1).fail())

  run unstableDependencyIdentityRejectedTest = multiInit.expect(multiSafety)
    .then(openRound(1, 1, Set({ ...dependencyA, request: { ...request, identity: Unkeyed } })).fail())

}
