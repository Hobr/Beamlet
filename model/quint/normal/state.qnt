// Normal-use contracts are abstract logical values, not approved SQL/API fields.
module normalUseState {
  import beamletExecution.* from "../beamletExecution"
  export beamletExecution.*

  type RetryPolicy = StopOnFailure | RetryOnce
  type Definition = { operation: int, input: int, constraint: int, policy: RetryPolicy }
  type SubmissionIdentity = StableKey({ namespace: int, key: int }) | Unkeyed
  type SubmissionRequest = { identity: SubmissionIdentity, definition: Definition }
  type SubmissionEntry = { id: int, request: SubmissionRequest, context: int }
  type SubmissionResult = CreatedIntent(int) | ExistingIntent({ id: int, outcomes: List[Outcome] })
    | DefinitionConflict(int)
  type SubmissionReply = { request: SubmissionRequest, result: SubmissionResult }
  type SubmissionObservation = {
    request: SubmissionRequest, before: List[SubmissionEntry], after: List[SubmissionEntry],
    reply: SubmissionReply, outcomes: List[Outcome], beforeLedger: Ledger, afterLedger: Ledger,
  }
  type Handler = {
    id: int, operation: int, protocol: int, pending: bool, query: bool, idempotent: bool, validThrough: int,
  }
  type HandlerBinding = NoHandler | BoundHandler({ handler: Handler, definition: Definition, context: int })
  type LaunchObservation = {
    token: Token, binding: HandlerBinding, completion: CompletionBinding, authorizationStored: bool, at: int,
  }
  type RetryObservation = {
    oldExec: int, newExec: int, binding: HandlerBinding, at: int, repeatAccepted: bool,
    before: Ledger, definition: Definition, context: int,
  }
  type AcceptanceObservation = {
    report: Report, before: Ledger, after: Ledger, stop: bool, definition: Definition,
    binding: HandlerBinding, at: int,
  }
  type StopObservation = { before: Ledger, after: Ledger, definition: Definition, binding: HandlerBinding, at: int }
  type ReadObservation = { reports: Set[Report], outcomes: List[Outcome], ledger: Ledger }
  type UseMark = SubmittedMark | ReusedMark | DefinitionConflictMark | ReadMark | ReleasedMark
    | CallbackMark | PendingMark | RetriedMark | QueriedMark | AtomicFailureMark | DiscoveredMark
  type UseState = {
    entries: List[SubmissionEntry], creations: List[SubmissionEntry],
    requests: Set[SubmissionRequest], replies: Set[SubmissionReply], submissions: List[SubmissionObservation],
    bindings: int -> HandlerBinding, launches: List[LaunchObservation], retries: List[RetryObservation],
    acceptances: List[AcceptanceObservation], stops: List[StopObservation], reads: List[ReadObservation], marks: Set[UseMark],
    discovered: Set[int], contractTime: int,
  }
  var usage: UseState

  pure val definition: Definition = { operation: 1, input: 1, constraint: 1, policy: StopOnFailure }
  pure val request: SubmissionRequest = { identity: StableKey({ namespace: 1, key: 1 }), definition: definition }
  pure val syncHandler: Handler = {
    id: 1, operation: 1, protocol: 1, pending: false, query: false, idempotent: false, validThrough: 0,
  }
  pure val callbackHandler: Handler = { ...syncHandler, id: 2, pending: true }
  pure val idempotentHandler: Handler = { ...syncHandler, id: 3, idempotent: true, validThrough: 3 }
  pure val queryHandler: Handler = { ...syncHandler, id: 4, query: true }
  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }
  pure val t2: Token = { exec: 2, worker: 2, incarnation: 1, generation: 1 }

  pure val initialUse: UseState = {
    entries: List(), creations: List(), requests: Set(), replies: Set(), submissions: List(),
    bindings: EXECUTIONS.mapBy(_ => NoHandler), launches: List(), retries: List(),
    acceptances: List(), stops: List(), reads: List(), marks: Set(), discovered: Set(), contractTime: 0,
  }
  // The core Open ledger is a dormant slot until submission creates focused Intent 1.
  // Slot 2 checks submission identity separation only; its executions are out of scope.
  action normalInit = all { init, usage' = initialUse }
}
