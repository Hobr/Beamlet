// Execution domain types: no decisions, commands, rule registry or disposition chain.
module executionTypes {
  type IntentPhase = Open | Closed
  // 生命周期表示 Authority 的协议进度;Unknown 是已授权但结果不明,不等同于失败.
  type ExecutionPhase = Prepared | StartAuthorized | Waiting | Unknown | Resolved

  type CurrentExecution = NoCurrent | Current(int)
  // Knowledge 来自已保存证据;NotFound 只表示查询未找到,不能推出 NotExecutedKnown.
  type Knowledge = NoKnowledge | SuccessKnown | FailureKnown | NotExecutedKnown

  type ReportKind = Pending | Success | Failure | NotFound | NotExecuted
  type OutcomeKind = OutcomeSucceeded | OutcomeFailed | OutcomeCancelled
  type ResourceResult = ResourceUnfinished | ResourceSucceeded | ResourceFailed

  // incarnation 隔离 Worker 重启,generation 隔离同一 Execution 的再次领取.
  type Token = { exec: int, worker: int, incarnation: int, generation: int }

  type LeaseKey = { exec: int, generation: int }

  type GrantPermission = NoGrant | StartGrant(Token)

  // Opaque correlation, established durably before calling; not a callback credential.
  type CompletionBinding = NoCompletion | CallbackBinding(int)

  type Lease = {
    claimed: bool, worker: int, incarnation: int,
    generation: int, expiresAt: int, invalidated: bool,
  }

  type Attempt = {
    exists: bool, phase: ExecutionPhase, lease: Lease, grant: GrantPermission, completion: CompletionBinding,
    // Conflict is orthogonal to the last supported lifecycle projection.
    knowledge: Knowledge, negativeSeen: bool, conflict: bool,
  }

  type Origin = ByWorker(Token) | ByQuery | ByCallback(int)
  // Integers are opaque logical contents: only equality matters, not serialization.
  type Report = { id: int, exec: int, kind: ReportKind, value: int, origin: Origin }

  type Outcome = { kind: OutcomeKind, exec: CurrentExecution, value: int }

  type AuditKind = Created | Claimed | Expired | Authorized | EvidenceStored
                 | OutcomeStored | AttemptReplaced | ConflictStored | EvidenceReconciled | CommandRejectionStored

  type Audit = { kind: AuditKind, exec: CurrentExecution }

  // Independent snapshots make protocol violations observable, not type tautologies.
  type StartWitness = {
    token: Token, openAtGrant: bool, currentAtGrant: bool, leaseValidAtGrant: bool,
  }

  type CommitWitness = {
    outcome: Outcome, openAtCommit: bool, sourceEligible: bool,
    oldSuccessAtCommit: bool, conflictsAtCommit: bool,
  }

  type RetryWitness = { oldExec: int, newExec: int, safeAtReplacement: bool }

  // Worker 局部状态全部易失;重启通过新 incarnation 拒绝旧许可,已发消息仍可在网络中.
  type LocalState = {
    alive: bool, incarnation: int, leases: Set[Token], grants: Set[Token],
    started: Set[int], reports: Set[Report], receipts: Set[Report],
  }

  type Invocation = { token: Token, incarnationAtCall: int }

}
