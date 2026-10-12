module continuationRecoveryTests {
  import continuationProtocolTests.* from "./protocol_test"
  export continuationProtocolTests.*
  action resubmitSourceA = all { multiSend(1, request), holdProgress }
    .then(all { multiSubmit(1, request), holdProgress })
    .then(resolveProgressReply({ request: request, result: ExistingIntent({ id: 1, outcomes: List(resultA.outcome) }) }))
    .then(readProgressResult(sourceRefA))
  action resolveCreatedSuccessor = resolveProgressReply({ request: nextRequest, result: CreatedIntent(3) })
  action resolveReusedSuccessor(outcomes: List[Outcome]): bool = resolveProgressReply({ request: nextRequest,
    result: ExistingIntent({ id: 3, outcomes: outcomes }) })

  run crashBeforeDecisionCanRebuildSourceReadTest = partialProgressInit.then(crashProgressAgent)
    .then(restartProgressAgent).then(resubmitSourceA).then(decideA)
    .expect(continuationSafety and progress.decision == ProgressCommitted(recordFor(resultA)))
  run restartCannotUseLostLocalReadBeforeRebuildingTest = partialProgressInit.then(crashProgressAgent)
    .then(restartProgressAgent).expect(continuationSafety).then(decide(resultA).fail())
  run crashAfterDecisionReconstructsManifestWithoutLocalCacheTest = decidedProgressInit
    .then(crashProgressAgent).then(restartProgressAgent).then(registerNext)
    .expect(continuationSafety and recoveredManifestWitness)
    .expect(agentLocals.get(1).results.size() == 0 and agentLocals.get(1).refs.size() == 0)
  run crashAfterManifestStillSubmitsSameRequestTest = registeredProgressInit.then(crashProgressAgent)
    .then(restartProgressAgent).then(sendNext).then(submitNext)
    .expect(continuationSafety and multiStore.catalog.length() == 3 and multiStore.catalog.nth(2).request == nextRequest)
  run lostSuccessorReplyAndRestartReuseOriginalIntentTest = submittedProgressInit
    .then(all { multiLoseSubmissionReply(1, { request: nextRequest, result: CreatedIntent(3) }), holdProgress })
    .then(crashProgressAgent).then(restartProgressAgent).then(sendNext).then(submitNext)
    .then(resolveReusedSuccessor(List())).expect(continuationSafety)
    .expect(multiStore.catalog.length() == 3 and agentLocals.get(1).refs.contains(successorRef))
  run closedSuccessorReusedWithoutNewInvocationTest = closedProgressInit.then(crashProgressAgent)
    .then(restartProgressAgent).then(sendNext).then(submitNext).then(resolveReusedSuccessor(List(resultA.outcome)))
    .then(readProgressResult(successorRef)).then(collectProgressRound(2))
    .expect(continuationSafety and recoveredSuccessorWitness and resources.get(3).invocations.length() == 1)
    .expect(not(callerRounds.get(1).completed) and multiStore.intents.get(2).ledger.phase == Open)
  run siblingCanFinishDuringRestartWithoutChangingNextDefinitionTest = decidedProgressInit
    .then(crashProgressAgent).then(finishProgressIntent(2, Success, 2)).then(restartProgressAgent)
    .then(registerNext).then(sendNext).then(submitNext).expect(continuationSafety)
    .expect(progress.decision == ProgressCommitted(recordFor(resultA)) and multiStore.catalog.nth(2).request == nextRequest)
  run successorCompletionAfterWorkerLossUsesOriginalBindingTest = submittedProgressInit
    .then(resolveCreatedSuccessor).then(startProgressIntent(3, 2))
    .then(all { sharedWorkerCrash(2), holdProgress }).then(finishProgressIntent(3, Success, 1))
    .then(readProgressResult(successorRef)).then(collectProgressRound(2)).expect(continuationSafety and successorCompletedWitness)
  run originalRoundCanStillJoinIndependentlyTest = closedProgressInit.then(resolveCreatedSuccessor)
    .then(readProgressResult(successorRef)).then(collectProgressRound(2))
    .then(finishProgressIntent(2, Success, 2)).then(readProgressResult(sourceRefB)).then(collectProgressRound(1))
    .expect(continuationSafety and callerRounds.get(1).completed and callerRounds.get(2).completed)
  run registerReplayDoesNotRewriteCompletedManifestTest = closedProgressInit.then(resolveCreatedSuccessor)
    .then(readProgressResult(successorRef)).then(collectProgressRound(2))
    .expect(continuationSafety).then(registerNext.fail())
}
