// Replacement, external queries, token discovery and clock observations.
module coreLogicRecovery {
  import coreLogicDispositions.* from "./dispositions"
  export coreLogicDispositions.*

  pure def applyClockMove(x: ExternalState, old: int, nextTime: int): ExternalState =
    if (nextTime < old) { ...x, marks: x.marks.union(Set("clockBackward")) } else x

  // 安全替代需要未授权,可靠且仍适用的未执行证据,或显式接受重复风险.
  // 到期,Unknown,查询 NotFound 都不能单独证明旧尝试不会继续调用.
  pure def safeToReplace(l: Ledger, e: int): bool = {
    val attempt = l.attempts.get(e)
    attempt.grant == NoGrant or judgmentKnowledge(l, e) == NotExecutedKnown or ALLOW_REPEAT
  }

  // 有恢复理由与替代安全是两个条件;新的 Execution 身份必须尚未使用.
  pure def canReplace(l: Ledger, oldExec: int, newExec: int): bool = {
    val attempt = l.attempts.get(oldExec)
    val recoveryReason = attempt.grant == NoGrant or attempt.phase == Unknown
      or judgmentKnowledge(l, oldExec) == FailureKnown or judgmentKnowledge(l, oldExec) == NotExecutedKnown
    l.phase == Open and l.current == Current(oldExec)
      and not(l.attempts.get(newExec).exists) and recoveryReason and safeToReplace(l, oldExec)
  }

  // 原子切换 current,保留旧 grant/证据;使旧租约失效不等于撤销旧外部调用的可能性.
  pure def applyReplace(l: Ledger, oldExec: int, newExec: int): Ledger = {
    val old = l.attempts.get(oldExec)
    val updatedOld = { ...old, lease: { ...old.lease, invalidated: true } }
    val fresh = { ...emptyAttempt, exists: true }
    val invalid = if (old.lease.claimed)
      l.invalidLeases.union(Set({ exec: oldExec, generation: old.lease.generation }))
      else l.invalidLeases
    val decision: RetryWitness = {
      oldExec: oldExec, newExec: newExec, safeAtReplacement: safeToReplace(l, oldExec),
    }
    val updated = { ...l, current: Current(newExec),
      attempts: l.attempts.set(oldExec, updatedOld).set(newExec, fresh),
      invalidLeases: invalid, retries: l.retries.append(decision),
      history: l.history.append({ kind: AttemptReplaced, exec: Current(newExec) }) }
    advanceJudgment(l, updated)
  }

  pure def freshQueryId(x: ExternalState, e: int, id: int): bool =
    not(x.emitted.exists(r => r.exec == e and r.origin == ByQuery and r.id == id))

  // 未完成时只生成 NotFound;可靠 NotExecuted 必须由 fenceAtResource 另行建立.
  pure def queryReport(x: ExternalState, e: int, id: int): Report = {
    val result = x.finished.get(e)
    val kind = if (result == ResourceSucceeded) Success
      else if (result == ResourceFailed) Failure else NotFound
    { id: id, exec: e, kind: kind, origin: ByQuery }
  }

  pure def reportTokens(r: Report): Set[Token] = match r.origin {
    | ByWorker(t) => Set(t) | ByQuery => Set()
  }

  pure def messageTokens(m: Message): Set[Token] = match m {
    | StartRequest(t) => Set(t)
    | StartReply(t) => Set(t)
    | ResultReport(r) => reportTokens(r)
    | StoredReceipt(r) => reportTokens(r)
    | ReconcileRequest(_) => Set()
    | ReconcileReply(_) => Set()
  }

  pure def knownTokens(localWorkers: int -> LocalState, messages: Set[Message]): Set[Token] = {
    val localTokens: Set[Token] = WORKERS.fold(Set(),
      (acc, w) => acc.union(localWorkers.get(w).leases).union(localWorkers.get(w).grants))
    messages.fold(localTokens, (acc, m) => acc.union(messageTokens(m)))
  }
}
