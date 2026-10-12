// Independent checks must reject these mistakes; none is in the production step.
module multiIntentMutations {
  import multiIntentFixtures.* from "../scenarios/multi/fixtures"
  export multiIntentFixtures.*
  const BUG: int

  action mutantInit = if (BUG == 1) joinedInit.then(startFirst(1, 1, syncHandler))
      .then(startFirst(2, 1, syncHandler)).then(multiComplete(1, 1, Success, 1)).then(multiPublish(1, t1, false))
    else if (BUG == 2) joinedInit.then(multiCreate(1, 1)).then(multiClaim(1, 1, 1))
      .then(multiRequest(1, t1)).then(multiAuthorize(1, t1, syncHandler))
      .then(multiCreate(2, 1)).then(multiClaim(2, 1, 1))
    else if (BUG == 3) joinedInit.then(startFirst(1, 1, idempotentHandler))
      .then(multiCreate(2, 1)).then(multiClaim(2, 1, 1)).then(multiRequest(2, t1))
      .then(multiAuthorize(2, t1, idempotentHandler)).then(multiGrant(2, scoped(2, StartReply(t1)), t1))
    else if (BUG == 5) partiallyReadInit
    else if (BUG == 6) completePairInit.then(resolveJoined).then(readDependency(1, refA))
    else if (BUG == 8) joinedInit.then(crashAgent(1))
    else bothRunningInit

  action mutantStep = if (BUG == 1) {
    val d = multiStore.intents.get(2)
    val r = workerValue(t1, Success, 1)
    all {
      multiNetwork.messages.contains(scoped(1, ResultReport(r))), reportSourceValid(d.ledger, r),
      // Deliberately project another Intent's authenticated envelope without its scope check.
      writeIntent(2, { ...d, ledger: receiveWithPolicy(d.use, d.ledger, r) }, sharedWorkers,
        resources.get(2), multiNetwork.messages.union(Set(scoped(2, StoredReceipt(r))))),
    }
  } else if (BUG == 2) writeIntent(2, multiStore.intents.get(2),
    withLocal(sharedWorkers, 2, 1, applyReceiveGrant(localFor(2, 1), t1)), resources.get(2),
    multiNetwork.messages.exclude(Set(scoped(1, StartReply(t1)))))
  else if (BUG == 3) {
    val d = multiStore.intents.get(2)
    val b = bindingFor(d.use, idempotentHandler)
    val wrong = match b { | NoHandler => NoHandler | BoundHandler(s) => BoundHandler({ ...s, context: 1 }) }
    writeIntent(2, { ...d, use: { ...d.use, launches: d.use.launches.append({ token: t1,
      binding: wrong, completion: NoCompletion, authorizationStored: true, at: d.use.contractTime }) } },
      withLocal(sharedWorkers, 2, 1, { ...localFor(2, 1), started: Set(1) }),
      applyCall(resources.get(2), t1, 1), multiNetwork.messages)
  } else if (BUG == 4) {
    val other = multiStore.intents.get(2)
    commitScope(1, { ...multiStore, intents: multiStore.intents.set(2,
      { ...other, ledger: { ...other.ledger, history: List() } }) }, sharedWorkers, resources, multiNetwork)
  } else if (BUG == 7) {
    val d = multiStore.intents.get(2)
    writeIntent(2, { ...d, ledger: { ...d.ledger, attempts: d.ledger.attempts.set(1,
      { ...d.ledger.attempts.get(1), completion: CallbackBinding(correlation(1, 1)) }) } },
      sharedWorkers, resources.get(2), multiNetwork.messages)
  } else {
    val round = callerRounds.get(1)
    val correct = agentLocals.get(1).results.filter(r => r.call == 1)
    val duplicatedSlot: CollectedResult = { call: 1, slot: 1, intent: 2,
      outcome: multiStore.intents.get(2).ledger.outcomes.foldl(
        { kind: OutcomeFailed, exec: NoCurrent, value: 0 }, (_, o) => o) }
    all {
      holdRuntime, agentLocals' = agentLocals,
      callerRounds' = callerRounds.set(1, if (BUG == 8) { ...round, dependencies: Set(dependencyA) }
        else { ...round, completed: true,
          results: if (BUG == 6) correct.union(Set(duplicatedSlot)) else correct }),
    }
  }
  // Isolate the relevant property so unrelated instrumentation cannot mask a weak check.
  val mutantInvariant = if (BUG == 1) INTENTS.forall(i => multiStore.intents.get(i).ledger.reports
      .forall(r => resources.get(i).emitted.contains(r)))
    else if (BUG == 2) sharedSessionsSafe
    else if (BUG == 3 or BUG == 7) multiExecutionSafety
    else if (BUG == 4) scopeIsolation else toolRoundsSound
  run mutationCaughtTest = mutantInit.expect(multiSafety).then(mutantStep).expect(not(mutantInvariant))
}
