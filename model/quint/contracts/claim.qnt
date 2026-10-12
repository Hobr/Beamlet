module claimProtocol {
  import claimState.* from "./claim_state"
  export claimState.*
  pure def freshClaim(l: Ledger, r: ClaimRequest, now: int): bool =
    l.attempts.get(r.exec).lease.generation == r.expected and canClaim(l, r.exec, now)
  pure def replayClaim(l: Ledger, journal: Set[ClaimReply], r: ClaimRequest, now: int): bool =
    journal.exists(a => a.request == r and leaseValid(l, a.token, now))
  pure def allocated(l: Ledger, r: ClaimRequest, now: int): ClaimReply =
    { request: r, token: tokenFor(applyClaim(l, r.exec, r.worker, r.incarnation, now), r.exec) }
  action sendClaim(r: ClaimRequest): bool = all {
    workers.get(r.worker).alive, r.incarnation == workers.get(r.worker).incarnation,
    not(claimWire.requests.contains(r)), holdCore, claimJournal' = claimJournal,
    claimWire' = { ...claimWire, requests: claimWire.requests.union(Set(r)) },
  }
  action commitClaim(r: ClaimRequest): bool = {
    val fresh = not(claimJournal.exists(a => a.request == r)) and freshClaim(authority.durable, r, clock)
      and workers.get(r.worker).alive and workers.get(r.worker).incarnation == r.incarnation
    val replay = replayClaim(authority.durable, claimJournal, r, clock)
    val response = if (fresh) Set(allocated(authority.durable, r, clock))
      else claimJournal.filter(a => a.request == r and replay)
    all {
      authority.online, claimWire.requests.contains(r),
      authority' = if (fresh) { ...authority,
        durable: applyClaim(authority.durable, r.exec, r.worker, r.incarnation, clock) } else authority,
      claimJournal' = claimJournal.union(if (fresh) response else Set()),
      claimWire' = { ...claimWire, requests: claimWire.requests.exclude(Set(r)),
        replies: claimWire.replies.union(response), replays: claimWire.replays + (if (replay) 1 else 0) },
      workers' = workers, network' = network, external' = external, clock' = clock,
    }
  }
  action receiveClaim(a: ClaimReply): bool = all {
    claimWire.replies.contains(a), workers.get(a.token.worker).alive,
    workers.get(a.token.worker).incarnation == a.token.incarnation,
    not(claimWire.received.contains(a)), authority' = authority,
    workers' = workers.set(a.token.worker, { ...workers.get(a.token.worker),
      leases: workers.get(a.token.worker).leases.union(Set(a.token)) }),
    network' = network, external' = external, clock' = clock, claimJournal' = claimJournal,
    claimWire' = { ...claimWire, replies: claimWire.replies.exclude(Set(a)), received: claimWire.received.union(Set(a)) },
  }
  action loseClaim(a: ClaimReply): bool = all { claimWire.replies.contains(a), holdCore,
    claimJournal' = claimJournal, claimWire' = { ...claimWire,
      replies: claimWire.replies.exclude(Set(a)), losses: claimWire.losses + 1 } }
  val allocationSound = claimJournal.forall(a =>
    a.token.exec == a.request.exec and a.token.worker == a.request.worker
      and a.token.incarnation == a.request.incarnation and a.token.generation == a.request.expected + 1
      and claimJournal.filter(b => b.request == a.request).size() == 1
      and claimJournal.filter(b => b.token.exec == a.token.exec and b.token.generation == a.token.generation).size() == 1)
    and EXECUTIONS.forall(e => authority.durable.attempts.get(e).lease.generation ==
      claimJournal.filter(a => a.token.exec == e).size())
  val claimDeliverySound = claimWire.replies.union(claimWire.received).forall(a => claimJournal.contains(a))
    and WORKERS.forall(w => workers.get(w).leases.forall(t =>
      claimWire.received.exists(a => a.token == t)))
  val claimSessionsSound = WORKERS.forall(w => workers.get(w).leases.forall(t =>
    t.worker == w and t.incarnation == workers.get(w).incarnation))
  val claimSafety = safety and allocationSound and claimDeliverySound and claimSessionsSound
  val allocatedWitness = claimJournal.size() > 0
  val replayWitness = claimWire.replays > 0 and claimWire.losses > 0
  val deliveredWitness = claimWire.received.size() > 0
  val calledWitness = external.invocations.length() > 0
  action claimHealthyStep = {
    nondet e = EXECUTIONS.oneOf()
    nondet w = WORKERS.oneOf()
    val generation = authority.durable.attempts.get(e).lease.generation
    nondet expected = Set(generation, if (generation > 0) generation - 1 else 0).oneOf()
    val r: ClaimRequest = { exec: e, worker: w, incarnation: workers.get(w).incarnation, expected: expected }
    val fallback: ClaimReply = { request: r, token: {
      exec: e, worker: w, incarnation: r.incarnation, generation: expected + 1 } }
    nondet pending = (if (claimWire.requests.size() > 0) claimWire.requests else Set(r)).oneOf()
    nondet reply = (if (claimWire.replies.size() > 0) claimWire.replies else Set(fallback)).oneOf()
    val tokens = knownTokens(workers, network)
    nondet t = (if (tokens.size() > 0) tokens else Set(fallback.token)).oneOf()
    any {
      sendClaim(r), commitClaim(pending), receiveClaim(reply),
      all { any { createExecution(e), requestStart(t), authorizeStart(t), receiveGrant(t),
        callExternal(t), completeAtResource(e, Success), publishCompletion(t), receiveAnyReport }, holdClaims },
    }
  }
  action claimStep = {
    nondet e = EXECUTIONS.oneOf()
    nondet w = WORKERS.oneOf()
    any { claimHealthyStep,
      all { claimWire.replies.size() > 0, nondet reply = claimWire.replies.oneOf() loseClaim(reply) },
      all { any { moveClock, expireLease(e), crashWorker(w), restartWorker(w),
        crashCoordinator, restartCoordinator }, holdClaims } }
  }
  pure val r1: ClaimRequest = { exec: 1, worker: 1, incarnation: 1, expected: 0 }
  pure val a1: ClaimReply = { request: r1, token: { exec: 1, worker: 1, incarnation: 1, generation: 1 } }
  action claimPreparedInit = claimInit.then(all { createExecution(1), holdClaims })
  action claimCommittedInit = claimPreparedInit.then(sendClaim(r1)).then(commitClaim(r1))
  action claimLostInit = claimCommittedInit.then(loseClaim(a1))
}
