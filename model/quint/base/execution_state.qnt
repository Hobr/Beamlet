// Standalone execution ledger. No judgment versions, decisions, commands or rule state.
module executionState {
  import executionValues.* from "./execution_values"
  export executionValues.*

  type Message = StartRequest(Token) | StartReply(Token) | ResultReport(Report) | StoredReceipt(Report)
  type Ledger = {
    phase: IntentPhase, current: CurrentExecution, attempts: int -> Attempt,
    reports: Set[Report], outcomes: List[Outcome], firstOutcome: List[Outcome],
    commits: List[CommitWitness], starts: List[StartWitness], invalidLeases: Set[LeaseKey],
    retries: List[RetryWitness], history: List[Audit],
  }
  type AuthorityState = { online: bool, durable: Ledger }
  type ExternalState = {
    invocations: List[Invocation], effects: Set[int], finished: int -> ResourceResult,
    values: int -> int, noFuture: Set[int], emitted: Set[Report], marks: Set[str],
  }

  var authority: AuthorityState

  var workers: int -> LocalState

  // Set 抽象无序消息,可延迟/丢失/重投;不统计相同消息同时在途的份数.
  var network: Set[Message]

  var external: ExternalState

  // Authority 墙钟允许前跳和后跳;已持久失效的租约不能因回拨重新有效.
  var clock: int

  pure val initialLedger: Ledger = {
    phase: Open, current: NoCurrent, attempts: EXECUTIONS.mapBy(_ => emptyAttempt),
    reports: Set(), outcomes: List(), firstOutcome: List(), commits: List(), starts: List(),
    invalidLeases: Set(), retries: List(), history: List(),
  }

  // 初始 Intent 为 Open 且尚无 Execution;所有场景从此经合法动作构造前缀.
  action init = all {
    authority' = { online: true, durable: initialLedger },
    workers' = WORKERS.mapBy(_ => initialWorker),
    network' = Set(),
    external' = {
      invocations: List(), effects: Set(), finished: EXECUTIONS.mapBy(_ => ResourceUnfinished),
      values: EXECUTIONS.mapBy(_ => 0), noFuture: Set(), emitted: Set(), marks: Set(),
    },
    clock' = 0,
  }

  // Disabled, frame-complete branch: never a stuttering transition.
  action invalidMessageVariant = all {
    false, authority' = authority, workers' = workers, network' = network,
    external' = external, clock' = clock,
  }
}
