// Intentionally broken rules; each initializer follows real guarded transitions.
module coreMutations {

  const BUG: int

  import beamletCore.* from "../beamletCore"
  export beamletCore.*

  pure val t1: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }

  pure val success1: Report = { id: 2, exec: 1, kind: Success, origin: ByWorker(t1) }

  pure val notFound1: Report = { id: 3, exec: 1, kind: NotFound, origin: ByQuery }

  pure val cancelled: Outcome = { kind: OutcomeCancelled, exec: NoCurrent }

  action preparedInit = init.expect(safety)
    .then(createExecution(1)).expect(safety)
    .then(claimExecution(1, 1)).expect(safety)

  action authorizedInit = preparedInit
    .then(requestStart(t1)).expect(safety)
    .then(authorizeStart(t1)).expect(safety)

  action grantHeldInit = authorizedInit.then(receiveGrant(t1)).expect(safety)

  action reportInFlightInit = grantHeldInit
    .then(callExternal(t1)).expect(safety)
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)

  action closedInit = reportInFlightInit.then(receiveReport(success1)).expect(safety)

  action expiredPreparedInit = preparedInit
    .then(moveClockTo(2)).expect(safety)
    .then(expireLease(1)).expect(safety)
    .then(moveClockTo(0)).expect(safety)

  action negativeWindowInit = grantHeldInit
    .then(queryExternal(1, 3)).expect(safety)
    .then(receiveReport(notFound1)).expect(safety)
    .then(moveClockTo(2)).expect(safety)
    .then(expireLease(1)).expect(safety)

  action restartedInit = authorizedInit
    .then(crashWorker(1)).expect(safety)
    .then(restartWorker(1)).expect(safety)

  action closedPreparedInit = preparedInit.then(cancelIntent).expect(safety)

  action latePendingInit = grantHeldInit
    .then(callExternal(t1)).expect(safety)
    .then(publishPending(t1)).expect(safety)
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)

  action unknownInit = grantHeldInit
    .then(moveClockTo(2)).expect(safety)
    .then(expireLease(1)).expect(safety)

  action duplicateTerminalCommit = all {
    authority.online, authority.durable.phase == Closed,
    // Missing first-commit-wins check; append even though already terminal.
    authority' = { ...authority, durable: applyCommit(authority.durable, cancelled) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  action overwriteTerminalResult = all {
    authority.online, authority.durable.phase == Closed,
    // A last-write-wins outcome row silently replaces the accepted result.
    authority' = { ...authority, durable: { ...authority.durable, outcomes: List(cancelled) } },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  pure def reviveOldLease(l: Ledger): Ledger = {
    val attempt = l.attempts.get(1)
    { ...l, attempts: l.attempts.set(1,
      { ...attempt, lease: { ...attempt.lease, invalidated: false } }) }
  }

  action renewFromWallTimeOnly = all {
    authority.online, clock < authority.durable.attempts.get(1).lease.expiresAt,
    authority.durable.attempts.get(1).lease.invalidated,
    // Forget persisted invalidation while the independent historical witness remains.
    authority' = { ...authority, durable: reviveOldLease(authority.durable) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  action retryFromNotFoundOnly = all {
    authority.online, authority.durable.phase == Open,
    authority.durable.attempts.get(1).negativeSeen,
    // Ignore the still-live possibility of an old authorized invocation.
    authority' = { ...authority, durable: applyReplace(authority.durable, 1, 2) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  action inheritOldIncarnationGrant = {
    val local = workers.get(1)
    all {
      local.alive, local.incarnation != t1.incarnation, network.contains(StartReply(t1)),
      authority' = authority,
      workers' = workers.set(1, { ...local, grants: local.grants.union(Set(t1)),
        started: local.started.union(Set(1)) }),
      network' = network.exclude(Set(StartReply(t1))),
      // Faulty restart handling lets the new incarnation use the old grant.
      external' = applyCall(external, t1, local.incarnation), clock' = clock,
    }
  }

  action authorizeAfterClose = all {
    authority.online, authority.durable.phase == Closed,
    authority.durable.attempts.get(1).grant == NoGrant,
    authority' = { ...authority, durable: applyAuthorize(authority.durable, t1, clock) },
    workers' = workers, network' = network.union(Set(StartReply(t1))),
    external' = external, clock' = clock,
  }

  pure def regressToWaiting(l: Ledger): Ledger = {
    val recorded = applyReport(l, pendingReport(t1))
    val attempt = recorded.attempts.get(1)
    { ...recorded, attempts: recorded.attempts.set(1, { ...attempt, phase: Waiting }) }
  }

  action regressOnLatePending = all {
    authority.online, network.contains(ResultReport(pendingReport(t1))),
    authority.durable.attempts.get(1).phase == Resolved,
    authority' = { ...authority, durable: regressToWaiting(authority.durable) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  action closeUnknownAsFailed = all {
    authority.online, authority.durable.attempts.get(1).phase == Unknown,
    // Expiry / a stop-retrying decision is incorrectly treated as failure evidence.
    authority' = { ...authority, durable: applyCommit(authority.durable,
      { kind: OutcomeFailed, exec: Current(1) }) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  action acknowledgeBeforeDurability = all {
    authority.online, network.contains(ResultReport(success1)),
    not(authority.durable.reports.contains(success1)),
    authority' = authority, workers' = workers,
    network' = network.union(Set(StoredReceipt(success1))),
    external' = external, clock' = clock,
  }

  // BUG 将合法窗口,一个故意错误动作和目标性质配成一组;只在最后一步制造违规.
  action mutantInit =
    if (BUG == 1 or BUG == 2) closedInit
    else if (BUG == 3) expiredPreparedInit
    else if (BUG == 4) negativeWindowInit
    else if (BUG == 5) restartedInit
    else if (BUG == 6) closedPreparedInit
    else if (BUG == 7) latePendingInit
    else if (BUG == 8) unknownInit
    else reportInFlightInit

  action mutantStep =
    if (BUG == 1) duplicateTerminalCommit
    else if (BUG == 2) overwriteTerminalResult
    else if (BUG == 3) renewFromWallTimeOnly
    else if (BUG == 4) retryFromNotFoundOnly
    else if (BUG == 5) inheritOldIncarnationGrant
    else if (BUG == 6) authorizeAfterClose
    else if (BUG == 7) regressOnLatePending
    else if (BUG == 8) closeUnknownAsFailed
    else acknowledgeBeforeDurability

  // 指向应检出的具体性质,避免把其他偶然失败误当作目标防线有效.
  val mutantInvariant =
    if (BUG == 1) outcomeUnique
    else if (BUG == 2) outcomeImmutable
    else if (BUG == 3) expirySticky
    else if (BUG == 4) replacementsSafe
    else if (BUG == 5) invocationsAuthorized
    else if (BUG == 6) startupsQualified
    else if (BUG == 7) resolvedKnowledgeCoherent
    else if (BUG == 8) commitsQualified
    else receiptsOnlyForStored

  // Tests pass precisely when the intentionally broken transition is detected.
  run mutationCaughtTest = mutantInit.expect(safety)
    .then(mutantStep).expect(not(mutantInvariant) and not(safety))
}
