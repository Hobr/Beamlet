module tripleScenarios {
  import tripleProtocol.* from "../../contracts/triple"
  export tripleProtocol.*
  action readAllTriple = readDependency(1, tripleRef(1)).then(readDependency(1, tripleRef(2)))
    .then(readDependency(1, tripleRef(3)))
  run submittedIntentBeforeExecutionSurvivesCoordinatorRestartTest = tripleSubmittedInit
    .then(multiAvailability(false)).then(multiAvailability(true))
    .expect(tripleSafety and multiStore.catalog.length() == 3)
    .expect(INTENTS.forall(i => not(multiStore.intents.get(i).ledger.attempts.get(1).exists)))
    .then(startFirst(1, 1, callbackHandler)).then(tripleFinish(1, 1)).expect(tripleSafety)
    .expect(multiStore.intents.get(1).ledger.phase == Closed)
  run threeEffectsAreOriginallyConcurrentTest = tripleRunningInit.expect(tripleSafety and threeInvokedWitness)
    .expect(INTENTS.forall(i => multiStore.intents.get(i).ledger.phase == Open))
  run twoResultsDoNotCompleteTripleRoundTest = tripleTwoCompletedInit
    .expect(tripleSafety and twoCompletedWitness).then(collectRound(1, 1).fail())
  run restartPreservesAllThreeDependenciesTest = tripleRestartedInit.expect(tripleSafety)
    .expect(agentLocals.get(1).refs.size() == 0 and agentLocals.get(1).results.size() == 0)
    .expect(callerRounds.get(1).dependencies == tripleDependencies)
  run restartReusesCompletedResultsAndWaitsForThirdTest = tripleRestartedInit.then(rebuildTriple)
    .then(readDependency(1, tripleRef(1))).then(readDependency(1, tripleRef(2)))
    .expect(tripleSafety and recoveredTripleReadWitness and multiStore.catalog.length() == 3)
    .expect(resources.get(1).invocations.length() == 1 and resources.get(2).invocations.length() == 1)
    .then(collectRound(1, 1).fail())
  run thirdCompletesAfterCallerRecoveryTest = tripleRestartedInit.then(rebuildTriple)
    .then(tripleFinish(3, 3)).then(readAllTriple).then(collectRound(1, 1))
    .expect(tripleSafety and tripleJoinedWitness and recoveredTripleReadWitness)
  run thirdCompletesWhileCallerIsDownTest = tripleTwoCompletedInit.then(crashAgent(1))
    .then(tripleFinish(3, 3)).then(restartAgent(1)).then(rebuildTriple).then(readAllTriple)
    .then(collectRound(1, 1)).expect(tripleSafety and tripleJoinedWitness)
  run thirdUnknownCannotBeFilledByDuplicateResultTest = tripleTwoCompletedInit
    .then(multiClockMove(2)).then(multiExpire(3, 1)).then(crashAgent(1)).then(restartAgent(1))
    .then(rebuildTriple).then(readDependency(1, tripleRef(1))).then(readDependency(1, tripleRef(2)))
    .expect(tripleSafety and multiStore.intents.get(3).ledger.attempts.get(1).phase == Unknown)
    .then(collectRound(1, 1).fail())
  run explicitThirdCancellationCanCompleteRoundTest = tripleRestartedInit.then(rebuildTriple)
    .then(multiCancel(3)).then(readAllTriple).then(collectRound(1, 1)).expect(tripleSafety and tripleJoinedWitness)
  run lostThirdSubmissionReplyReusesOriginalIntentTest = tripleSubmittedInit
    .then(multiLoseSubmissionReply(1, { request: requestC, result: CreatedIntent(3) }))
    .then(crashAgent(1)).then(restartAgent(1)).then(tripleResubmit(requestC, 3, List()))
    .expect(tripleSafety and multiStore.catalog.length() == 3)
    .expect(agentLocals.get(1).refs.contains(tripleRef(3)))
}
