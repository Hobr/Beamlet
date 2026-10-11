// Shared domain types and independent observation records.
module coreBaseTypes {

  type IntentPhase = Open | Closed

  type ExecutionPhase = Prepared | StartAuthorized | Waiting | Unknown | Resolved

  type CurrentExecution = NoCurrent | Current(int)

  type Knowledge = NoKnowledge | SuccessKnown | FailureKnown | NotExecutedKnown

  type ReportKind = Pending | Success | Failure | NotFound | NotExecuted

  type OutcomeKind = OutcomeSucceeded | OutcomeFailed | OutcomeCancelled

  type ResourceResult = ResourceUnfinished | ResourceSucceeded | ResourceFailed

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

  type DecisionKind = AdoptSuccess | AdoptFailure | ExcludeFromJudgment | ExcludeAllEvidence

  type RuleReference = { id: int, version: int }

  // Checked semantic definitions; versions are not executable release numbers.
  type RuleRegistration = {
    rule: RuleReference, kinds: Set[DecisionKind], queryRequired: bool, evidenceRequired: bool,
  }

  type DecisionActor = Operator(int) | AutomaticRule(RuleReference)

  type DecisionBasis = VerifiedCompletion | ContractExclusion

  type EvidenceTreatment = KeepEvidence | ExcludeEvidence

  type EvidenceDisposition = { report: Report, treatment: EvidenceTreatment, basis: DecisionBasis }

  type ReconciliationPolicy = {
    operators: Set[int], registeredRules: Set[RuleRegistration], excludable: Set[Report],
    // Authority-checked, per-item Operation contract facts, not caller assertions.
    resolutions: Set[Set[EvidenceDisposition]],
  }

  // Stable Intent-local list positions abstract decision identity; not a SQL/public ID scheme.
  type Supersession = { decisionIndex: int, reports: Set[Report] }

  type DispositionBinding = { decisionIndex: int, item: EvidenceDisposition }

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

  type DecisionWitness = {
    decision: Decision, acceptedCurrent: CurrentExecution, acceptedReports: Set[Report],
    acceptedRevision: int, acceptedBase: JudgmentBase,
    openAtDecision: bool, actorQualified: bool, contractQualified: bool,
    coverageQualified: bool, evidenceQualified: bool, supersessionQualified: bool,
    rulesAtDecision: Set[RuleRegistration],
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

  type ExternalState = {
    invocations: List[Invocation], effects: Set[int], finished: int -> ResourceResult,
    noFuture: Set[int], emitted: Set[Report], marks: Set[str],
    commandHandling: List[CommandHandlingWitness], ruleRetirements: List[RuleRetirementWitness],
  }
}
