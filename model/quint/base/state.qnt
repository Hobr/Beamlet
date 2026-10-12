// Single owner of parameters, state variables, initial values and disabled fallback.
module coreBaseState {
  import coreBaseTypes.* from "./types"
  export coreBaseTypes.*

  // 身份域和计数上界用于控制探索成本;达到上界禁用新动作,不循环复用身份.
  // 列表仍可随重投增长,因此有界参与者不等于有限状态空间或穷尽证明.
  const WORKERS: Set[int]

  const EXECUTIONS: Set[int]

  const REPORT_IDS: Set[int]

  const CLOCK_VALUES: Set[int]

  const MAX_INCARNATION: int

  const MAX_GENERATION: int

  const TTL: int

  // 显式接受替代执行的重复风险,不抽象为"外部效果恰好一次"或可靠幂等.
  const ALLOW_REPEAT: bool

  // 可信资源协议能同时证明尚未调用并永久阻止旧执行;能力强于单纯递增 fencing token.
  const CAN_FENCE: bool

  // 五组 var 只在这里声明.动作必须赋值全部五组,x' = x 表示该组保持原值.
  // Authority 离线只改变 online,durable 的已提交事务按模型前提保留.
  var authority: AuthorityState

  var workers: int -> LocalState

  // Set 抽象无序消息,可延迟/丢失/重投;不统计相同消息同时在途的份数.
  var network: Set[Message]

  var external: ExternalState

  // Authority 墙钟允许前跳和后跳;已持久失效的租约不能因回拨重新有效.
  var clock: int

  pure val emptyLease: Lease = {
    claimed: false, worker: 0, incarnation: 0,
    generation: 0, expiresAt: 0, invalidated: true,
  }

  // 预填充所有 Execution 键使 get/set 有定义;exists=false 的占位不是实际尝试.
  pure val emptyAttempt: Attempt = {
    exists: false, phase: Prepared, lease: emptyLease, grant: NoGrant, completion: NoCompletion,
    knowledge: NoKnowledge, negativeSeen: false, conflict: false,
  }

  pure val initialWorker: LocalState = {
    alive: true, incarnation: 1, leases: Set(), grants: Set(),
    started: Set(), reports: Set(), receipts: Set(),
  }

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
