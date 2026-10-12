// Test-only bridge: compare ordinary execution with the preserved composition reference.
// Production execution/normal/recovery entries never import this module.
module executionProjection {
  import normalRecoveryActions.* from "../../normal/recovery"
  export normalRecoveryActions.*
  import coreLogicLeases as leaseReference from "../../logic/leases"
  import coreLogicOutcomes as outcomeReference from "../../logic/outcomes"
  import coreLogicRecovery as recoveryReference from "../../logic/recovery"

  pure def lift(l: Ledger): outcomeReference::Ledger = {
    ...outcomeReference::initialLedger, phase: l.phase, current: l.current, attempts: l.attempts,
    reports: l.reports, outcomes: l.outcomes, firstOutcome: l.firstOutcome,
    commits: l.commits, starts: l.starts, invalidLeases: l.invalidLeases,
    retries: l.retries, history: l.history,
  }
  pure def project(l: outcomeReference::Ledger): Ledger = {
    phase: l.phase, current: l.current, attempts: l.attempts, reports: l.reports,
    outcomes: l.outcomes, firstOutcome: l.firstOutcome, commits: l.commits,
    starts: l.starts, invalidLeases: l.invalidLeases, retries: l.retries, history: l.history,
  }
  pure def leaseEquivalent(l: Ledger, e: int, now: int): bool = {
    val r = lift(l)
    val t = tokenFor(l, e)
    canCreate(l, e) == leaseReference::canCreate(r, e)
      and canClaim(l, e, now) == leaseReference::canClaim(r, e, now)
      and canAuthorize(l, t, now) == leaseReference::canAuthorize(r, t, now)
      and canExpire(l, e, now) == leaseReference::canExpire(r, e, now)
      and canRenew(l, t, now) == leaseReference::canRenew(r, t, now)
      and project(leaseReference::applyCreate(r, e)) == applyCreate(l, e)
      and project(leaseReference::applyClaim(r, e, 1, 1, now)) == applyClaim(l, e, 1, 1, now)
      and project(leaseReference::applyAuthorize(r, t, now)) == applyAuthorize(l, t, now)
      and project(leaseReference::applyExpire(r, e)) == applyExpire(l, e)
      and project(leaseReference::applyRenew(r, t, now)) == applyRenew(l, t, now)
  }
  pure def resultEquivalent(l: Ledger, o: Outcome): bool = {
    val r = lift(l)
    sourceEligible(l, o) == outcomeReference::sourceEligible(r, o)
      and canCommit(l, o) == outcomeReference::canCommit(r, o)
      and project(outcomeReference::applyCommit(r, o)) == applyCommit(l, o)
  }
  pure def reportEquivalent(l: Ledger, r: Report): bool =
    reportSourceValid(l, r) == outcomeReference::reportSourceValid(lift(l), r)
      and project(outcomeReference::recordAndMaybeCommit(lift(l), r)) == recordAndMaybeCommit(l, r)
  pure def replacementEquivalent(l: Ledger, old: int, destination: int, proof: bool): bool =
    canReplaceWithEvidence(l, old, destination, proof)
      == recoveryReference::canReplaceWithEvidence(lift(l), old, destination, proof)
      and project(recoveryReference::applyReplaceWithEvidence(lift(l), old, destination, proof))
        == applyReplaceWithEvidence(l, old, destination, proof)

  val projectionEquivalent = EXECUTIONS.forall(e => {
    val l = authority.durable
    val t = tokenFor(l, e)
    leaseEquivalent(l, e, clock)
      and resultEquivalent(l, { kind: OutcomeSucceeded, exec: Current(e), value: 1 })
      and resultEquivalent(l, { kind: OutcomeFailed, exec: Current(e), value: 2 })
      and reportEquivalent(l, { id: 1, exec: e, kind: Success, value: 1, origin: ByWorker(t) })
      and reportEquivalent(l, { id: 1, exec: e, kind: Failure, value: 2, origin: ByQuery })
      and EXECUTIONS.forall(destination => replacementEquivalent(l, e, destination, false)
        and replacementEquivalent(l, e, destination, true))
  }) and resultEquivalent(authority.durable, { kind: OutcomeCancelled, exec: NoCurrent, value: 0 })
  val projectionSafety = normalSafety and projectionEquivalent

  run initialProjectionTest = normalInit.expect(projectionSafety)
  run callbackProjectionTest = callbackReleasedInit.expect(projectionSafety)
    .then(normalComplete(1, Success, 2)).then(emitCallback(callbackReport(external, 1, 1, 3), true))
    .then(normalReceive(callbackReport(external, 1, 1, 3))).expect(projectionSafety)
  run retryProjectionTest = retryPendingInit.expect(projectionSafety)
    .then(normalReplace(1, 2)).expect(projectionSafety)
  run expiryProjectionTest = preparedInit.then(normalAuthorize(t1, callbackHandler))
    .then(normalClock(2)).then(normalExpire(1)).expect(projectionSafety)
  run conflictProjectionTest = callbackRunningInit.then(normalComplete(1, Success, 1))
    .then(emitCallback(callbackReport(external, 1, 1, 3), true))
    .then(normalReceive(callbackReport(external, 1, 1, 3)))
    .then(all { network' = network.union(Set(ResultReport({ ...callbackReport(external, 1, 1, 3), value: 2 }))),
      authority' = authority, workers' = workers, external' = external, clock' = clock, usage' = usage })
    .then(normalReceive({ ...callbackReport(external, 1, 1, 3), value: 2 })).expect(projectionSafety)
}
