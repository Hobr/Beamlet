module tripleProtocol {
  import multiIntentProfiles.* from "../multi/profiles"
  export multiIntentProfiles.*
  pure val requestC: SubmissionRequest = { ...request, identity: StableKey({ namespace: 3, key: 1 }),
    definition: { ...definition, input: 3 } }
  pure val dependencyC: Dependency = { slot: 3, request: requestC }
  pure val tripleDependencies = Set(dependencyA, dependencyB, dependencyC)
  pure def tripleRef(i: int): ResolvedRef = { call: 1, slot: i, intent: i }
  pure def tripleCallback(i: int, value: int): Report = {
    id: 3, exec: 1, kind: Success, value: value, origin: ByCallback(correlation(i, 1)),
  }
  action tripleInit = multiInit.then(openRound(1, 1, tripleDependencies))
  action tripleSubmittedInit = tripleInit.then(multiSend(1, request)).then(multiSubmit(1, request))
    .then(multiSend(1, requestB)).then(multiSubmit(1, requestB))
    .then(multiSend(1, requestC)).then(multiSubmit(1, requestC))
  action tripleRunningInit = tripleSubmittedInit.then(startFirst(1, 1, callbackHandler))
    .then(startFirst(2, 2, callbackHandler)).then(startFirst(3, 1, callbackHandler))
  action tripleFinish(i: int, value: int): bool = multiComplete(i, 1, Success, value)
    .then(multiEmitCallback(i, tripleCallback(i, value), true))
    .then(multiReceive(i, scoped(i, ResultReport(tripleCallback(i, value))), tripleCallback(i, value)))
  action tripleResolve = multiResolve(1, { request: request, result: CreatedIntent(1) })
    .then(multiResolve(1, { request: requestB, result: CreatedIntent(2) }))
    .then(multiResolve(1, { request: requestC, result: CreatedIntent(3) }))
  action tripleTwoCompletedInit = tripleRunningInit.then(tripleResolve)
    .then(tripleFinish(1, 1)).then(tripleFinish(2, 2))
    .then(readDependency(1, tripleRef(1))).then(readDependency(1, tripleRef(2)))
  action tripleRestartedInit = tripleTwoCompletedInit.then(crashAgent(1)).then(restartAgent(1))
  action tripleResubmit(r: SubmissionRequest, i: int, outcomes: List[Outcome]): bool =
    multiSend(1, r).then(multiSubmit(1, r))
      .then(multiResolve(1, { request: r, result: ExistingIntent({ id: i, outcomes: outcomes }) }))
  action rebuildTriple = tripleResubmit(request, 1, multiStore.intents.get(1).ledger.outcomes)
    .then(tripleResubmit(requestB, 2, multiStore.intents.get(2).ledger.outcomes))
    .then(tripleResubmit(requestC, 3, multiStore.intents.get(3).ledger.outcomes))
  val tripleManifestSound = callerRounds.get(1).exists and callerRounds.get(1).owner == 1
    and callerRounds.get(1).dependencies == tripleDependencies
  val tripleCompletionSound = not(callerRounds.get(1).completed) or
    callerRounds.get(1).results.map(r => r.slot) == Set(1, 2, 3)
  val tripleSafety = multiSafety and tripleManifestSound and tripleCompletionSound
  val threeInvokedWitness = INTENTS.forall(i => resources.get(i).invocations.length() > 0)
  val twoCompletedWitness = INTENTS.filter(i => multiStore.intents.get(i).ledger.phase == Closed).size() == 2
    and not(callerRounds.get(1).completed)
  val recoveredTripleReadWitness = agentLocals.get(1).restarts > 0
    and agentLocals.get(1).results.filter(r => r.call == 1).size() >= 2
  val tripleJoinedWitness = callerRounds.get(1).completed and callerRounds.get(1).results.size() == 3
  action tripleHealthyStep = any { scheduleSubmission, scheduleReply, scheduleRead, scheduleCollect,
    scheduleExecution, scheduleCompletion, scheduleResourceReport, scheduleDelivery }
  action tripleStep = any { tripleHealthyStep, multiFaultStep }
}
