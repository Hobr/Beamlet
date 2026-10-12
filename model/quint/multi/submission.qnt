// Submission identity is collection-wide, independent of Agent and Tool Call identity.
module multiIntentSubmission {
  import multiIntentLogic.* from "./logic"
  export multiIntentLogic.*

  action multiSend(a: int, r: SubmissionRequest): bool = all {
    agentLocals.get(a).alive, not(multiNetwork.requests.contains({ agent: a, request: r })),
    commitScope(0, multiStore, sharedWorkers, resources,
      { ...multiNetwork, requests: multiNetwork.requests.union(Set({ agent: a, request: r })) }),
  }
  action multiSubmit(a: int, r: SubmissionRequest): bool = {
    val id = existingId(multiStore.catalog, r)
    val fresh = multiStore.catalog.length() + 1
    val entry: SubmissionEntry = { id: fresh, request: r, context: fresh }
    val created: IntentData = { exists: true, ledger: initialLedger,
      use: { ...initialUse, entries: List(entry), creations: List(entry), contractTime: multiStore.contractTime } }
    val updated = if (id == 0 and INTENTS.contains(fresh)) { ...multiStore, catalog: multiStore.catalog.append(entry),
      intents: multiStore.intents.set(fresh, created) } else multiStore
    all {
      multiStore.online, multiNetwork.requests.contains({ agent: a, request: r }),
      id > 0 or INTENTS.contains(fresh),
      commitScope(if (id == 0) fresh else 0, updated, sharedWorkers, resources,
        { ...multiNetwork, requests: multiNetwork.requests.exclude(Set({ agent: a, request: r })),
          replies: multiNetwork.replies.union(Set({ agent: a, reply: multiReply(multiStore, r) })) }),
    }
  }
  action multiResolve(a: int, r: SubmissionReply): bool = all {
    agentLocals.get(a).alive, multiNetwork.replies.contains({ agent: a, reply: r }),
    multiStore' = multiStore, sharedWorkers' = sharedWorkers, resources' = resources,
    multiClock' = multiClock, callerRounds' = callerRounds,
    multiNetwork' = { ...multiNetwork, replies: multiNetwork.replies.exclude(Set({ agent: a, reply: r })) },
    agentLocals' = agentLocals.set(a, { ...agentLocals.get(a),
      refs: agentLocals.get(a).refs.union(resolvedFor(callerRounds, a, r)) }),
    scopeObservation' = { target: 0, before: multiStore, after: multiStore,
      workersBefore: sharedWorkers, workersAfter: sharedWorkers, resourcesBefore: resources,
      resourcesAfter: resources, workerSessionChanged: false, contractTimesChanged: false },
  }
  action openRound(a: int, c: int, ds: Set[Dependency]): bool = all {
    agentLocals.get(a).alive, not(callerRounds.get(c).exists), validDependencies(ds),
    holdRuntime, agentLocals' = agentLocals,
    callerRounds' = callerRounds.set(c, { exists: true, owner: a, dependencies: ds,
      completed: false, results: Set(), registered: { owner: a, dependencies: ds } }),
  }
  action readDependency(a: int, ref: ResolvedRef): bool = {
    val d = multiStore.intents.get(ref.intent)
    val result: CollectedResult = { call: ref.call, slot: ref.slot, intent: ref.intent,
      outcome: if (d.ledger.outcomes.length() > 0) d.ledger.outcomes.nth(0)
        else { kind: OutcomeFailed, exec: NoCurrent, value: 0 } }
    all {
      multiStore.online, agentLocals.get(a).alive, agentLocals.get(a).refs.contains(ref),
      callerRounds.get(ref.call).owner == a, d.ledger.outcomes.length() == 1,
      not(agentLocals.get(a).results.contains(result)), holdRuntime, callerRounds' = callerRounds,
      agentLocals' = agentLocals.set(a, { ...agentLocals.get(a),
        results: agentLocals.get(a).results.union(Set(result)) }),
    }
  }
  action collectRound(a: int, c: int): bool = {
    val round = callerRounds.get(c)
    val results = agentLocals.get(a).results.filter(r => r.call == c)
    all {
      agentLocals.get(a).alive, round.exists, round.owner == a, not(round.completed),
      allCollected(round, c, results), holdRuntime, agentLocals' = agentLocals,
      callerRounds' = callerRounds.set(c, { ...round, completed: true, results: results }),
    }
  }
  action crashAgent(a: int): bool = all {
    agentLocals.get(a).alive, holdRuntime, callerRounds' = callerRounds,
    agentLocals' = agentLocals.set(a, { ...initialAgent, alive: false, restarts: agentLocals.get(a).restarts }),
  }
  action restartAgent(a: int): bool = all {
    not(agentLocals.get(a).alive), agentLocals.get(a).restarts < MAX_INCARNATION,
    holdRuntime, callerRounds' = callerRounds,
    agentLocals' = agentLocals.set(a, { ...initialAgent, restarts: agentLocals.get(a).restarts + 1 }),
  }
}
