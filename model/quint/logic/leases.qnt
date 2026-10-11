// Creation, lease validity, claiming, startup authorization and renewal.
module coreLogicLeases {
  import coreLogicJudgment.* from "./judgment"
  export coreLogicJudgment.*

  pure def canCreate(l: Ledger, e: int): bool =
    l.phase == Open and l.current == NoCurrent and not(l.attempts.get(e).exists)

  pure def applyCreate(l: Ledger, e: int): Ledger = {
    val attempt = { ...emptyAttempt, exists: true }
    val updated = { ...l, current: Current(e), attempts: l.attempts.set(e, attempt),
      history: l.history.append({ kind: Created, exec: Current(e) }) }
    advanceJudgment(l, updated)
  }

  pure def leaseKey(t: Token): LeaseKey =
    { exec: t.exec, generation: t.generation }

  pure def tokenFor(l: Ledger, e: int): Token = {
    val lease = l.attempts.get(e).lease
    { exec: e, worker: lease.worker, incarnation: lease.incarnation, generation: lease.generation }
  }

  pure def leaseValid(l: Ledger, t: Token, now: int): bool = {
    val lease = l.attempts.get(t.exec).lease
    lease.claimed and lease.worker == t.worker and lease.incarnation == t.incarnation
      and lease.generation == t.generation and not(lease.invalidated)
      and now < lease.expiresAt
  }

  pure def canClaim(l: Ledger, e: int, now: int): bool = {
    val attempt = l.attempts.get(e)
    val lease = attempt.lease
    l.phase == Open and l.current == Current(e) and attempt.exists
      and attempt.phase == Prepared and attempt.grant == NoGrant
      and lease.generation < MAX_GENERATION
      and (not(lease.claimed) or lease.invalidated or now >= lease.expiresAt)
  }

  pure def applyClaim(l: Ledger, e: int, w: int, inc: int, now: int): Ledger = {
    val attempt = l.attempts.get(e)
    val old = attempt.lease
    val invalid = if (old.claimed)
      l.invalidLeases.union(Set({ exec: e, generation: old.generation }))
      else l.invalidLeases
    val history = if (old.claimed and not(old.invalidated))
      l.history.append({ kind: Expired, exec: Current(e) }) else l.history
    val lease: Lease = { claimed: true, worker: w, incarnation: inc,
      generation: old.generation + 1, expiresAt: now + TTL, invalidated: false }
    { ...l, attempts: l.attempts.set(e, { ...attempt, lease: lease }),
      invalidLeases: invalid, history: history.append({ kind: Claimed, exec: Current(e) }) }
  }

  pure def canAuthorize(l: Ledger, t: Token, now: int): bool = {
    val attempt = l.attempts.get(t.exec)
    l.phase == Open and l.current == Current(t.exec) and attempt.exists
      and attempt.phase == Prepared and attempt.grant == NoGrant
      and leaseValid(l, t, now)
  }

  pure def applyAuthorize(l: Ledger, t: Token, now: int): Ledger = {
    val attempt = l.attempts.get(t.exec)
    val witness: StartWitness = {
      token: t, openAtGrant: l.phase == Open, currentAtGrant: l.current == Current(t.exec),
      leaseValidAtGrant: leaseValid(l, t, now),
    }
    val updated = { ...l, attempts: l.attempts.set(t.exec,
        { ...attempt, phase: StartAuthorized, grant: StartGrant(t) }),
      starts: l.starts.append(witness),
      history: l.history.append({ kind: Authorized, exec: Current(t.exec) }) }
    advanceJudgment(l, updated)
  }

  pure def canExpire(l: Ledger, e: int, now: int): bool = {
    val lease = l.attempts.get(e).lease
    lease.claimed and not(lease.invalidated) and now >= lease.expiresAt
  }

  pure def applyExpire(l: Ledger, e: int): Ledger = {
    val attempt = l.attempts.get(e)
    val lease = { ...attempt.lease, invalidated: true }
    val phase = if (attempt.phase == StartAuthorized) Unknown else attempt.phase
    val updated = { ...l, attempts: l.attempts.set(e, { ...attempt, lease: lease, phase: phase }),
      invalidLeases: l.invalidLeases.union(Set({ exec: e, generation: lease.generation })),
      history: l.history.append({ kind: Expired, exec: Current(e) }) }
    advanceJudgment(l, updated)
  }

  pure def stickyLease(l: Ledger, e: int): bool = {
    val lease = l.attempts.get(e).lease
    val active = lease.claimed and not(lease.invalidated)
    active implies not(l.invalidLeases.contains({ exec: e, generation: lease.generation }))
  }

  pure def canRenew(l: Ledger, t: Token, now: int): bool =
    l.phase == Open and l.current == Current(t.exec) and leaseValid(l, t, now)
      and now + TTL > l.attempts.get(t.exec).lease.expiresAt

  pure def applyRenew(l: Ledger, t: Token, now: int): Ledger = {
    val attempt = l.attempts.get(t.exec)
    { ...l, attempts: l.attempts.set(t.exec,
      { ...attempt, lease: { ...attempt.lease, expiresAt: now + TTL } }) }
  }
}
