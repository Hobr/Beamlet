// Single owner of parameters, state variables, initial values and disabled fallback.
module coreBaseState {
  import coreBaseTypes.* from "./types"
  export coreBaseTypes.*
  import executionValues.* from "./execution_values"
  export executionValues.*

  // 五组 var 只在这里声明.动作必须赋值全部五组,x' = x 表示该组保持原值.
  // Authority 离线只改变 online,durable 的已提交事务按模型前提保留.
  var authority: AuthorityState

  var workers: int -> LocalState

  // Set 抽象无序消息,可延迟/丢失/重投;不统计相同消息同时在途的份数.
  var network: Set[Message]

  var external: ExternalState

  // Authority 墙钟允许前跳和后跳;已持久失效的租约不能因回拨重新有效.
  var clock: int

  pure val initialLedger: Ledger = {
    phase: Open, current: NoCurrent, attempts: EXECUTIONS.mapBy(_ => emptyAttempt),
    revision: 0, judgmentChanges: List(),
    reports: Set(), outcomes: List(), firstOutcome: List(), commits: List(),
    starts: List(), decisions: List(), decisionSnapshots: List(), commands: List(), commandCommits: List(),
    rejections: List(), rejectionCommits: List(),
    invalidLeases: Set(), retries: List(), history: List(),
  }

  // 初始 Intent 为 Open 且尚无 Execution;所有场景从此经合法动作构造前缀.
  action init = all {
    authority' = { online: true, durable: initialLedger },
    workers' = WORKERS.mapBy(_ => initialWorker),
    network' = Set(),
    external' = {
      invocations: List(), effects: Set(), finished: EXECUTIONS.mapBy(_ => ResourceUnfinished),
      values: EXECUTIONS.mapBy(_ => 0), noFuture: Set(), emitted: Set(), marks: Set(), commandHandling: List(), ruleRetirements: List(),
    },
    clock' = 0,
  }

  // Disabled, frame-complete branch: never a stuttering transition.
  action invalidMessageVariant = all {
    false, authority' = authority, workers' = workers, network' = network,
    external' = external, clock' = clock,
  }
}
