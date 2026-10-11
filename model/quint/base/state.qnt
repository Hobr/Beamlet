// Single owner of parameters, state variables, initial values and disabled fallback.
module coreBaseState {
  import coreBaseTypes.* from "./types"
  export coreBaseTypes.*

  const WORKERS: Set[int]

  const EXECUTIONS: Set[int]

  const REPORT_IDS: Set[int]

  const CLOCK_VALUES: Set[int]

  const MAX_INCARNATION: int

  const MAX_GENERATION: int

  const TTL: int

  const ALLOW_REPEAT: bool

  const CAN_FENCE: bool

  var authority: AuthorityState

  var workers: int -> LocalState

  var network: Set[Message]

  var external: ExternalState

  var clock: int

  pure val emptyLease: Lease = {
    claimed: false, worker: 0, incarnation: 0,
    generation: 0, expiresAt: 0, invalidated: true,
  }

  pure val emptyAttempt: Attempt = {
    exists: false, phase: Prepared, lease: emptyLease, grant: NoGrant,
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

  action init = all {
    authority' = { online: true, durable: initialLedger },
    workers' = WORKERS.mapBy(_ => initialWorker),
    network' = Set(),
    external' = {
      invocations: List(), effects: Set(), finished: EXECUTIONS.mapBy(_ => ResourceUnfinished),
      noFuture: Set(), emitted: Set(), marks: Set(), commandHandling: List(), ruleRetirements: List(),
    },
    clock' = 0,
  }

  // Disabled, frame-complete branch: never a stuttering transition.
  action invalidMessageVariant = all {
    false, authority' = authority, workers' = workers, network' = network,
    external' = external, clock' = clock,
  }
}
