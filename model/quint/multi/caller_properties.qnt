// A Tool Call joins identities and committed facts, never report/notification counts.
module multiIntentCallerProperties {
  import multiIntentProperties.* from "./properties"
  export multiIntentProperties.*

  pure def referenceSound(rounds: int -> ToolRound, s: MultiStore, a: int, ref: ResolvedRef): bool = {
    val round = rounds.get(ref.call)
    val entries = s.catalog.select(e => e.id == ref.intent)
    round.exists and round.owner == a and entries.length() == 1
      and round.dependencies.exists(d => d.slot == ref.slot
        and d.request == entries.nth(0).request)
  }
  pure def resultSound(rounds: int -> ToolRound, s: MultiStore, a: int, r: CollectedResult): bool =
    referenceSound(rounds, s, a, { call: r.call, slot: r.slot, intent: r.intent })
      and s.intents.get(r.intent).ledger.outcomes == List(r.outcome)
  pure def slotsUnique(rs: Set[CollectedResult]): bool = rs.forall(r => rs.forall(other =>
    (r.call == other.call and r.slot == other.slot) implies r == other))

  val callerFactsScoped = AGENTS.forall(a => {
    val local = agentLocals.get(a)
    local.refs.forall(ref => referenceSound(callerRounds, multiStore, a, ref))
      and local.results.forall(r => resultSound(callerRounds, multiStore, a, r))
      and slotsUnique(local.results)
      and (not(local.alive) implies local.refs.size() == 0 and local.results.size() == 0)
  })
  val toolRoundsSound = CALLS.forall(c => {
    val round = callerRounds.get(c)
    not(round.exists) or (AGENTS.contains(round.owner) and validDependencies(round.dependencies)
      and round.owner == round.registered.owner and round.dependencies == round.registered.dependencies
      and (if (round.completed) round.results.size() == round.dependencies.size()
        and slotsUnique(round.results) and round.results.forall(r => r.call == c
          and resultSound(callerRounds, multiStore, round.owner, r))
        and round.dependencies.forall(d => round.results.exists(r => r.slot == d.slot))
        else round.results.size() == 0))
  })
  val submissionRepliesSound = multiNetwork.replies.forall(envelope => {
    val r = envelope.reply
    match r.result {
      | DefinitionConflict(i) => existingId(multiStore.catalog, r.request) == i
          and multiStore.catalog.nth(i - 1).request.definition != r.request.definition
      | CreatedIntent(i) => multiStore.catalog.nth(i - 1).request == r.request
      | ExistingIntent(e) => multiStore.catalog.nth(e.id - 1).request == r.request
          and (e.outcomes.length() == 0 or e.outcomes == multiStore.intents.get(e.id).ledger.outcomes)
    }
  })
  val multiSafety = multiExecutionSafety and directoryScoped and sharedSessionsSafe and transportScoped
    and scopeIsolation and callerFactsScoped and toolRoundsSound and submissionRepliesSound
  val bothInvokedWitness = INTENTS.forall(i => resources.get(i).invocations.length() > 0)
  val bothClosedWitness = INTENTS.forall(i => multiStore.intents.get(i).ledger.phase == Closed)
  val sharedWorkerWitness = WORKERS.exists(w => INTENTS.forall(i => resources.get(i).invocations
    .select(c => c.token.worker == w).length() > 0))
  val joinedWitness = CALLS.exists(c => callerRounds.get(c).completed and callerRounds.get(c).dependencies.size() == 2)
  val independentWitness = CALLS.forall(c => callerRounds.get(c).completed)
    and callerRounds.get(1).owner != callerRounds.get(2).owner
  val partialJoinWitness = CALLS.exists(c => {
    val round = callerRounds.get(c)
    round.dependencies.size() == 2 and not(round.completed)
      and agentLocals.get(round.owner).results.filter(r => r.call == c).size() == 1
  })
  val recoveredJoinWitness = CALLS.exists(c => {
    val round = callerRounds.get(c)
    round.completed and round.dependencies.size() == 2 and agentLocals.get(round.owner).restarts > 0
  })
  val multiReleasedCompletionWitness = bothClosedWitness
    and INTENTS.forall(i => multiStore.intents.get(i).ledger.outcomes.nth(0).kind != OutcomeCancelled)
    and WORKERS.exists(w => not(sharedWorkers.get(w).alive) and INTENTS.forall(i =>
      resources.get(i).invocations.select(call => call.token.worker == w).length() > 0))
  val unknownIsolationWitness = INTENTS.exists(i => {
    val l = multiStore.intents.get(i).ledger
    l.phase == Open and EXECUTIONS.exists(e => l.attempts.get(e).phase == Unknown)
      and INTENTS.exists(other => other != i and multiStore.intents.get(other).ledger.phase == Closed)
  })
}
