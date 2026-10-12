// Caller commits its own decision, then reconstructs a manifest before submitting C.
module continuationActions {
  import continuationLogic.* from "./logic"
  export continuationLogic.*
  action decide(result: CollectedResult): bool = all {
    canDecide(progress, callerRounds, multiStore, agentLocals, result),
    holdRuntime, callerRounds' = callerRounds, agentLocals' = agentLocals,
    progress' = applyDecide(progress, recordFor(result)),
  }
  action registerNext: bool = all {
    canRegister(progress, callerRounds, agentLocals),
    holdRuntime, agentLocals' = agentLocals,
    progress' = { ...progress, registrations: progress.registrations.append(agentLocals.get(1).restarts) },
    callerRounds' = match progress.decision {
      | NoProgress => callerRounds
      | ProgressCommitted(r) => applyRegister(callerRounds, r)
    },
  }
  action scheduleDecision = all {
    agentLocals.get(1).results.size() > 0,
    nondet result = agentLocals.get(1).results.oneOf()
    decide(result)
  }
  action readContinuation(ref: ResolvedRef): bool = {
    val d = multiStore.intents.get(ref.intent)
    val result: CollectedResult = { call: ref.call, slot: ref.slot, intent: ref.intent,
      outcome: d.ledger.outcomes.foldl({ kind: OutcomeFailed, exec: NoCurrent, value: 0 }, (_, o) => o) }
    all { readDependency(1, ref), progress' = { ...progress,
      recoveredReads: if (agentLocals.get(1).restarts > 0) progress.recoveredReads.union(Set(result))
        else progress.recoveredReads } }
  }
  action collectContinuation(c: int): bool = all { collectRound(1, c),
    progress' = { ...progress, collections: progress.collections.append({ call: c,
      restarts: agentLocals.get(1).restarts }) } }
  action scheduleProgressRead = all { agentLocals.get(1).refs.size() > 0,
    nondet ref = agentLocals.get(1).refs.oneOf()
    readContinuation(ref)
  }
  action scheduleProgressCollect = { nondet c = CALLS.oneOf() collectContinuation(c) }
  action continuationHealthyStep = any { progressRuntimeStep, scheduleDecision, registerNext,
    scheduleProgressRead, scheduleProgressCollect }
  action continuationFaultStep = all { multiFaultStep, holdProgress }
  action continuationStep = any { continuationHealthyStep, continuationFaultStep }
}
