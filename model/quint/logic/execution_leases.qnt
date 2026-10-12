// Creation, lease validity, claiming, startup authorization and renewal.
module executionLeaseLogic {
  import executionValues.* from "../base/execution_values"
  export executionValues.*

  pure def canCreate(l, e) =
    l.phase == Open and l.current == NoCurrent and not(l.attempts.get(e).exists)

  pure def applyCreate(l, e) = {
    val attempt = { ...emptyAttempt, exists: true }
    val updated = { ...l, current: Current(e), attempts: l.attempts.set(e, attempt),
      history: l.history.append({ kind: Created, exec: Current(e) }) }
    updated
  }

  pure def leaseKey(t) =
    { exec: t.exec, generation: t.generation }

  pure def tokenFor(l, e) = {
    val lease = l.attempts.get(e).lease
    { exec: e, worker: lease.worker, incarnation: lease.incarnation, generation: lease.generation }
  }

  // 相等即到期;invalidated 是持久屏障.invalidLeases 仅作历史见证,不参与此守卫.
  pure def leaseValid(l, t, now) = {
    val lease = l.attempts.get(t.exec).lease
    lease.claimed and lease.worker == t.worker and lease.incarnation == t.incarnation
      and lease.generation == t.generation and not(lease.invalidated)
      and now < lease.expiresAt
  }

  // 同一 Execution 只能在从未授权的 Prepared 阶段重新领取;已授权未知须走替代尝试协议.
  pure def canClaim(l, e, now) = {
    val attempt = l.attempts.get(e)
    val lease = attempt.lease
    l.phase == Open and l.current == Current(e) and attempt.exists
      and attempt.phase == Prepared and attempt.grant == NoGrant
      and lease.generation < MAX_GENERATION
      and (not(lease.claimed) or lease.invalidated or now >= lease.expiresAt)
  }

  // 再次领取原子记下旧代失效并分配新 generation;不能通过回拨时钟重用旧 token.
  pure def applyClaim(l, e, w, inc, now) = {
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

  // 启动许可提交时同时核验 Open,current 和有效租约;许可持久化不代表已经外部调用.
  pure def canAuthorize(l, t, now) = {
    val attempt = l.attempts.get(t.exec)
    l.phase == Open and l.current == Current(t.exec) and attempt.exists
      and attempt.phase == Prepared and attempt.grant == NoGrant
      and leaseValid(l, t, now)
  }

  // apply* 仅构造新值,不自带准入守卫;调用方必须先检查 can*(mutation 有意绕过).
  pure def applyAuthorize(l, t, now) = {
    val attempt = l.attempts.get(t.exec)
    val witness: StartWitness = {
      token: t, openAtGrant: l.phase == Open, currentAtGrant: l.current == Current(t.exec),
      leaseValidAtGrant: leaseValid(l, t, now),
    }
    val updated = { ...l, attempts: l.attempts.set(t.exec,
        { ...attempt, phase: StartAuthorized, grant: StartGrant(t) }),
      starts: l.starts.append(witness),
      history: l.history.append({ kind: Authorized, exec: Current(t.exec) }) }
    updated
  }

  pure def canExpire(l, e, now) = {
    val lease = l.attempts.get(e).lease
    lease.claimed and not(lease.invalidated) and now >= lease.expiresAt
  }

  // 到期终止租约控制权,不撤回已经持久化的 grant;Waiting/Resolved 的既有投影保留.
  pure def applyExpire(l, e) = {
    val attempt = l.attempts.get(e)
    val lease = { ...attempt.lease, invalidated: true }
    val phase = if (attempt.phase == StartAuthorized) Unknown else attempt.phase
    val updated = { ...l, attempts: l.attempts.set(e, { ...attempt, lease: lease, phase: phase }),
      invalidLeases: l.invalidLeases.union(Set({ exec: e, generation: lease.generation })),
      history: l.history.append({ kind: Expired, exec: Current(e) }) }
    updated
  }

  pure def stickyLease(l, e) = {
    val lease = l.attempts.get(e).lease
    val active = lease.claimed and not(lease.invalidated)
    active implies not(l.invalidLeases.contains({ exec: e, generation: lease.generation }))
  }

  pure def canRenew(l, t, now) =
    l.phase == Open and l.current == Current(t.exec) and leaseValid(l, t, now)
      and now + TTL > l.attempts.get(t.exec).lease.expiresAt

  // 心跳只改租约控制信息,不改变 judgmentView,因此不推进审查 revision.
  pure def applyRenew(l, t, now) = {
    val attempt = l.attempts.get(t.exec)
    { ...l, attempts: l.attempts.set(t.exec,
      { ...attempt, lease: { ...attempt.lease, expiresAt: now + TTL } }) }
  }
}
