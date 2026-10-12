// Shared parameters and immutable defaults; this module owns no protocol variables.
module executionValues {
  import executionTypes.* from "./execution_types"
  export executionTypes.*

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

}
