// Only a committed Success of an original dependency can drive this one-step example.
module continuationLogic {
  import continuationState.* from "./state"
  export continuationState.*
  pure def nextDependencyFor(r: CollectedResult): Dependency = {
    slot: 1, request: { ...request, identity: StableKey({ namespace: 3, key: 1 }),
      definition: { ...definition, input: r.outcome.value } },
  }
  pure def recordFor(r: CollectedResult): ProgressRecord = {
    owner: 1, sourceCall: 1, stepKey: 1, ruleVersion: 1, consumed: Set(r),
    nextCall: 2, nextDependency: nextDependencyFor(r),
  }
  pure def sourceQualified(rounds: int -> ToolRound, s: MultiStore, r: ProgressRecord): bool =
    r.owner == 1 and r.sourceCall == 1 and r.stepKey == 1 and r.ruleVersion == 1
      and r.nextCall == 2 and r.consumed.size() == 1 and r.consumed.forall(result =>
        result.call == r.sourceCall and result.outcome.kind == OutcomeSucceeded
          and resultSound(rounds, s, r.owner, result) and r.nextDependency == nextDependencyFor(result))
  pure def canDecide(p: ProgressState, rounds: int -> ToolRound, s: MultiStore,
    locals: int -> AgentLocal, result: CollectedResult): bool =
    p.decision == NoProgress and locals.get(1).alive and locals.get(1).results.contains(result)
      and sourceQualified(rounds, s, recordFor(result))
  pure def applyDecide(p: ProgressState, r: ProgressRecord): ProgressState =
    { ...p, decision: ProgressCommitted(r), commits: p.commits.append(r) }
  pure def manifestMatches(rounds: int -> ToolRound, r: ProgressRecord): bool = {
    val round = rounds.get(r.nextCall)
    round.exists and round.owner == r.owner and round.dependencies == Set(r.nextDependency)
  }
  pure def canRegister(p: ProgressState, rounds: int -> ToolRound, locals: int -> AgentLocal): bool =
    match p.decision {
      | NoProgress => false
      | ProgressCommitted(r) => locals.get(r.owner).alive and not(rounds.get(r.nextCall).exists)
    }
  pure def applyRegister(rounds: int -> ToolRound, r: ProgressRecord): int -> ToolRound =
    rounds.set(r.nextCall, { ...emptyRound, exists: true, owner: r.owner,
      dependencies: Set(r.nextDependency), registered: { owner: r.owner, dependencies: Set(r.nextDependency) } })
  pure def requestReady(p: ProgressState, rounds: int -> ToolRound, req: SubmissionRequest): bool =
    req == request or req == requestB or match p.decision {
      | NoProgress => false
      | ProgressCommitted(r) => req == r.nextDependency.request and manifestMatches(rounds, r)
    }
}
