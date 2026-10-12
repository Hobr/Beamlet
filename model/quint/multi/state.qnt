// Two full execution ledgers; Intent is the scope of every otherwise-local identity.
module multiIntentState {
  import normalUseLogic.* from "../normal/logic"
  export normalUseLogic.*
  const INTENTS: Set[int]
  const AGENTS: Set[int]
  const CALLS: Set[int]

  type IntentData = { exists: bool, ledger: Ledger, use: UseState }
  type SharedWorker = { alive: bool, incarnation: int, slots: int -> LocalState }
  type ScopedMessage = { intent: int, message: Message }
  type AgentRequest = { agent: int, request: SubmissionRequest }
  type AgentReply = { agent: int, reply: SubmissionReply }
  type Dependency = { slot: int, request: SubmissionRequest }
  type ResolvedRef = { call: int, slot: int, intent: int }
  type CollectedResult = { call: int, slot: int, intent: int, outcome: Outcome }
  type ToolRound = {
    exists: bool, owner: int, dependencies: Set[Dependency],
    completed: bool, results: Set[CollectedResult],
    // Independent registration snapshot; instrumentation, not an additional product field.
    registered: { owner: int, dependencies: Set[Dependency] },
  }
  type AgentLocal = { alive: bool, refs: Set[ResolvedRef], results: Set[CollectedResult], restarts: int }
  type MultiStore = { online: bool, contractTime: int, catalog: List[SubmissionEntry], intents: int -> IntentData }
  type MultiNetwork = {
    messages: Set[ScopedMessage], requests: Set[AgentRequest], replies: Set[AgentReply],
  }
  // Test instrumentation: one before/after observation suffices to check every transition.
  type ScopeObservation = {
    target: int, before: MultiStore, after: MultiStore,
    workersBefore: int -> SharedWorker, workersAfter: int -> SharedWorker,
    resourcesBefore: int -> ExternalState, resourcesAfter: int -> ExternalState,
    workerSessionChanged: bool, contractTimesChanged: bool,
  }
  var multiStore: MultiStore
  var sharedWorkers: int -> SharedWorker
  var multiNetwork: MultiNetwork
  var resources: int -> ExternalState
  var multiClock: int
  // These two variables belong to the caller, not to Beamlet's Authority.
  var callerRounds: int -> ToolRound
  var agentLocals: int -> AgentLocal
  var scopeObservation: ScopeObservation

  pure val emptyIntent: IntentData = { exists: false, ledger: initialLedger, use: initialUse }
  pure val emptyResource: ExternalState = {
    invocations: List(), effects: Set(), finished: EXECUTIONS.mapBy(_ => ResourceUnfinished),
    values: EXECUTIONS.mapBy(_ => 0), noFuture: Set(), emitted: Set(), marks: Set(),
  }
  pure val emptyRound: ToolRound = {
    exists: false, owner: 0, dependencies: Set(), completed: false, results: Set(),
    registered: { owner: 0, dependencies: Set() },
  }
  pure val initialAgent: AgentLocal = { alive: true, refs: Set(), results: Set(), restarts: 0 }
  pure val requestB: SubmissionRequest = {
    ...request, identity: StableKey({ namespace: 2, key: 1 }), definition: { ...definition, input: 2 },
  }
  pure val dependencyA: Dependency = { slot: 1, request: request }
  pure val dependencyB: Dependency = { slot: 2, request: requestB }
  // An injective opaque correlation in this bounded model, not a public encoding.
  pure def correlation(i: int, e: int): int = i * 10 + e

  action multiInit = {
    val intents = INTENTS.mapBy(_ => emptyIntent)
    val pool = WORKERS.mapBy(_ => { alive: true, incarnation: 1, slots: INTENTS.mapBy(_ => initialWorker) })
    val xs = INTENTS.mapBy(_ => emptyResource)
    all {
      multiStore' = { online: true, contractTime: 0, catalog: List(), intents: intents },
      sharedWorkers' = pool, resources' = xs, multiClock' = 0,
      multiNetwork' = { messages: Set(), requests: Set(), replies: Set() },
      callerRounds' = CALLS.mapBy(_ => emptyRound), agentLocals' = AGENTS.mapBy(_ => initialAgent),
      scopeObservation' = { target: 0,
        before: { online: true, contractTime: 0, catalog: List(), intents: intents },
        after: { online: true, contractTime: 0, catalog: List(), intents: intents },
        workersBefore: pool, workersAfter: pool, resourcesBefore: xs, resourcesAfter: xs,
        workerSessionChanged: false, contractTimesChanged: false },
    }
  }
}
