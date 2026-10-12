// Shared domain types and independent observation records.
module coreBaseTypes {

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

  type Lease = {
    claimed: bool, worker: int, incarnation: int,
    generation: int, expiresAt: int, invalidated: bool,
  }

  type Attempt = {
    exists: bool, phase: ExecutionPhase, lease: Lease, grant: GrantPermission,
    // Q61: conflict is orthogonal to the last supported lifecycle projection.
    knowledge: Knowledge, negativeSeen: bool, conflict: bool,
  }

  type Origin = ByWorker(Token) | ByQuery

  type Report = { id: int, exec: int, kind: ReportKind, origin: Origin }

  type Message = StartRequest(Token) | StartReply(Token)
               | ResultReport(Report) | StoredReceipt(Report)
               | ReconcileRequest(ReconciliationCommand) | ReconcileReply(CommandReply)

  type Outcome = { kind: OutcomeKind, exec: CurrentExecution }

  type DecisionKind = AdoptSuccess | AdoptFailure | ExcludeFromJudgment | ExcludeAllEvidence | WithdrawDisposition

  type RuleReference = { id: int, version: int }

  // Checked semantic definitions; versions are not executable release numbers.
  type RuleRegistration = {
    rule: RuleReference, kinds: Set[DecisionKind], queryRequired: bool, evidenceRequired: bool,
  }

  type DecisionActor = Operator(int) | AutomaticRule(RuleReference)

  type DecisionBasis = VerifiedCompletion | ContractExclusion | VerifiedWithdrawal

  type EvidenceTreatment = KeepEvidence | ExcludeEvidence

  type EvidenceDisposition = { report: Report, treatment: EvidenceTreatment, basis: DecisionBasis }

  type ReconciliationPolicy = {
    operators: Set[int], registeredRules: Set[RuleRegistration], excludable: Set[Report],
    // Authority-checked, per-item Operation contract facts, not caller assertions.
    resolutions: Set[Set[EvidenceDisposition]],
    // Checked authorization/grounds for exact withdrawal references; trusted Authority input.
    withdrawals: Set[Set[Supersession]],
  }

  // Stable Intent-local list positions abstract decision identity; not a SQL/public ID scheme.
  type Supersession = { decisionIndex: int, reports: Set[Report] }

  type DispositionBinding = { decisionIndex: int, item: EvidenceDisposition }

  // reviewedRevision 锁定审查视图;evidence 是逐报告处置,supersedes 显式引用被替代/撤销的范围.
  type Decision = {
    kind: DecisionKind, report: Report, actor: DecisionActor, basis: DecisionBasis,
    reviewedRevision: int, evidence: Set[EvidenceDisposition], supersedes: Set[Supersession],
  }

  type JudgmentAttempt = {
    exists: bool, phase: ExecutionPhase, grant: GrantPermission, knowledge: Knowledge, conflict: bool,
  }

  type JudgmentBase = {
    phase: IntentPhase, current: CurrentExecution, reports: Set[Report], attempts: int -> JudgmentAttempt,
  }

  // 接受当刻的独立快照供性质回查;后来的权限,规则或证据不能重解释这次决定.
  type DecisionWitness = {
    decision: Decision, acceptedCurrent: CurrentExecution, acceptedReports: Set[Report],
    acceptedRevision: int, acceptedBase: JudgmentBase,
    openAtDecision: bool, actorQualified: bool, contractQualified: bool,
    coverageQualified: bool, evidenceQualified: bool, supersessionQualified: bool,
    rulesAtDecision: Set[RuleRegistration], bindingsBefore: Set[DispositionBinding],
    withdrawalsAtDecision: Set[Set[Supersession]],
  }

  type JudgmentView = { base: JudgmentBase, decisions: List[Decision] }

  type JudgmentChange = { before: JudgmentView, after: JudgmentView, previous: int, next: int }

  type ReconciliationCommand = { id: int, decision: Decision }

  type CommandRecord = {
    command: ReconciliationCommand, outcomes: List[Outcome], decisionIndex: int,
  }

  // Authority-verified facts for the authenticated caller and Intent; not message fields.
  type CommandAccess = { maySubmit: bool, mayRead: bool }

  pure val fullCommandAccess: CommandAccess = { maySubmit: true, mayRead: true }

  type RejectionResult = ReviewStale({ revision: int, current: CurrentExecution, reports: Set[Report], view: JudgmentView }) | DecisionIneligible

  type RejectedCommandRecord = { command: ReconciliationCommand, result: RejectionResult }

  type RejectionWitness = {
    original: RejectedCommandRecord, admitted: bool, eligible: bool,
    revisionAtRejection: int, currentAtRejection: CurrentExecution, reportsAtRejection: Set[Report],
    viewAtRejection: JudgmentView,
    decisionsBefore: int, decisionsAfter: int, outcomesBefore: List[Outcome], outcomesAfter: List[Outcome],
    historyBefore: int, historyAfter: int,
  }

  type CommandReply = CommandCommitted(CommandRecord)
    | CommandStale({ command: ReconciliationCommand, revision: int, current: CurrentExecution, reports: Set[Report], view: JudgmentView })
    | CommandIdentityConflict(ReconciliationCommand) | CommandIneligible(ReconciliationCommand)
    | CommandForbidden(ReconciliationCommand)

  // Independent observations of commit effects, not proposed SQL fields.
  type CommandHandlingWitness = {
    request: ReconciliationCommand, previous: List[CommandRecord], rejectedPreviously: List[RejectedCommandRecord],
    reply: CommandReply, mayRead: bool, maySubmit: bool, eligible: bool, resolutionStored: bool,
    revisionAtHandling: int, currentAtHandling: CurrentExecution, reportsAtHandling: Set[Report],
    viewAtHandling: JudgmentView, durableUnchanged: bool,
  }

  type CommandCommitWitness = {
    original: CommandRecord, commandsBefore: int, commandsAfter: int,
    decisionsBefore: int, decisionsAfter: int, historyBefore: int, historyAfter: int,
  }

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

  // 规格账本混合协议状态和历史见证;firstOutcome,*Witness 等观察记录不代表产品表结构.
  type Ledger = {
    phase: IntentPhase, current: CurrentExecution, attempts: int -> Attempt,
    revision: int, judgmentChanges: List[JudgmentChange],
    reports: Set[Report], outcomes: List[Outcome], firstOutcome: List[Outcome],
    commits: List[CommitWitness], starts: List[StartWitness],
    decisions: List[DecisionWitness], decisionSnapshots: List[Decision], commands: List[CommandRecord], commandCommits: List[CommandCommitWitness],
    rejections: List[RejectedCommandRecord], rejectionCommits: List[RejectionWitness],
    // Historical invalidation witness, not another permission gate.
    invalidLeases: Set[LeaseKey], retries: List[RetryWitness], history: List[Audit],
  }

  type AuthorityState = { online: bool, durable: Ledger }

  // Worker 局部状态全部易失;重启通过新 incarnation 拒绝旧许可,已发消息仍可在网络中.
  type LocalState = {
    alive: bool, incarnation: int, leases: Set[Token], grants: Set[Token],
    started: Set[int], reports: Set[Report], receipts: Set[Report],
  }

  type Invocation = { token: Token, incarnationAtCall: int }

  // Independent before/after observations, not registry state or SQL fields.
  type RuleRetirementWitness = {
    rule: RuleReference, previousRules: Set[RuleRegistration], nextRules: Set[RuleRegistration],
    previousBindings: Set[DispositionBinding], nextBindings: Set[DispositionBinding],
    previousRevision: int, nextRevision: int, durableUnchanged: bool,
  }

  // 外部调用/结果与 Authority 知识分离;marks 和处理/退役见证仅用于验证与覆盖观察.
  type ExternalState = {
    invocations: List[Invocation], effects: Set[int], finished: int -> ResourceResult,
    noFuture: Set[int], emitted: Set[Report], marks: Set[str],
    commandHandling: List[CommandHandlingWitness], ruleRetirements: List[RuleRetirementWitness],
  }
}
