// Pure adapters retain single-Intent rules and add global identity/routing scopes.
module multiIntentLogic {
  import multiIntentState.* from "./state"
  export multiIntentState.*

  pure def scoped(i: int, m: Message): ScopedMessage = { intent: i, message: m }
  def messagesFor(i: int): Set[Message] =
    multiNetwork.messages.filter(m => m.intent == i).map(m => m.message)
  def localFor(i: int, w: int): LocalState = sharedWorkers.get(w).slots.get(i)
  pure def withLocal(pool: int -> SharedWorker, i: int, w: int, local: LocalState): int -> SharedWorker =
    pool.set(w, { ...pool.get(w), slots: pool.get(w).slots.set(i, local) })
  pure def multiReply(s: MultiStore, r: SubmissionRequest): SubmissionReply = {
    val id = existingId(s.catalog, r)
    { request: r, result: if (id == 0) CreatedIntent(s.catalog.length() + 1)
      else if (s.catalog.nth(id - 1).request.definition != r.definition) DefinitionConflict(id)
      else ExistingIntent({ id: id, outcomes: s.intents.get(id).ledger.outcomes }) }
  }
  pure def replyId(r: SubmissionReply): int = match r.result {
    | CreatedIntent(i) => i | ExistingIntent(e) => e.id | DefinitionConflict(_) => 0
  }
  pure def validDependencies(ds: Set[Dependency]): bool = ds.size() > 0
    and ds.forall(d => d.request.identity != Unkeyed and ds.forall(other =>
      (d.slot == other.slot) implies d == other))
  pure def resolvedFor(rounds: int -> ToolRound, a: int, r: SubmissionReply): Set[ResolvedRef] =
    CALLS.fold(Set(), (refs, c) => refs.union(
      if (rounds.get(c).exists and rounds.get(c).owner == a and replyId(r) > 0)
        rounds.get(c).dependencies.filter(d => d.request == r.request)
          .map(d => { call: c, slot: d.slot, intent: replyId(r) })
      else Set()))
  pure def allCollected(round: ToolRound, c: int, results: Set[CollectedResult]): bool =
    round.dependencies.forall(d => results.exists(r => r.call == c and r.slot == d.slot))

  // A frame adapter, not a new execution rule. The observation checks its actual effects.
  action commitScope(i: int, s: MultiStore, pool: int -> SharedWorker,
    xs: int -> ExternalState, net: MultiNetwork): bool = all {
    multiStore' = s, sharedWorkers' = pool, resources' = xs, multiNetwork' = net,
    multiClock' = multiClock, callerRounds' = callerRounds, agentLocals' = agentLocals,
    scopeObservation' = { target: i, before: multiStore, after: s,
      workersBefore: sharedWorkers, workersAfter: pool, resourcesBefore: resources,
      resourcesAfter: xs, workerSessionChanged: false, contractTimesChanged: false },
  }
  action writeIntent(i: int, d: IntentData, pool: int -> SharedWorker,
    x: ExternalState, ms: Set[ScopedMessage]): bool =
    commitScope(i, { ...multiStore, intents: multiStore.intents.set(i, d) },
      pool, resources.set(i, x), { ...multiNetwork, messages: ms })
  action holdRuntime = all {
    multiStore' = multiStore, sharedWorkers' = sharedWorkers, resources' = resources,
    multiNetwork' = multiNetwork, multiClock' = multiClock,
    scopeObservation' = { target: 0, before: multiStore, after: multiStore,
      workersBefore: sharedWorkers, workersAfter: sharedWorkers, resourcesBefore: resources,
      resourcesAfter: resources, workerSessionChanged: false, contractTimesChanged: false },
  }
}
