// Healthy profile: no forced cancellation/faults; terminal reads remain observable.
module normalUseProfile {
  import normalUseProperties.* from "./normal/properties"
  export normalUseProperties.*

  // Resource-contract time cannot be extended by an Authority wall-clock rollback.
  action normalClock(n: int): bool = all {
    moveClockTo(n), usage' = { ...usage, contractTime: if (n > usage.contractTime) n else usage.contractTime },
  }
  action normalCancel = all { cancelIntent, usage' = usage }
  action normalCrashCoordinator = all { crashCoordinator, usage' = usage }
  action normalRestartCoordinator = all { restartCoordinator, usage' = usage }
  action normalRestartWorker(w: int): bool = all { restartWorker(w), usage' = usage }
  action normalExpire(e: int): bool = all { expireLease(e), usage' = usage }
  action normalDuplicate(r: Report): bool = all { acknowledgeDuplicate(r), usage' = usage }
  action normalStep = {
    nondet e = EXECUTIONS.oneOf()
    nondet w = WORKERS.oneOf()
    nondet id = REPORT_IDS.oneOf()
    nondet kind = Set(Success, Failure).oneOf()
    nondet value = Set(1, 2).oneOf()
    nondet h = Set(syncHandler, callbackHandler, queryHandler, idempotentHandler).oneOf()
    // Follow the actual claimant; both Workers are legitimate in the healthy profile.
    val t = if (authority.durable.attempts.get(e).lease.claimed) tokenFor(authority.durable, e)
      else if (e == 1) t1 else t2
    val submission = if (usage.entries.length() > 0) focused(usage).request else request
    any {
      sendSubmission(submission), receiveSubmission(submission), normalCreate(e), normalClaim(e, w),
      normalRequest(t), normalAuthorize(t, h), normalGrant(t), normalCall(t),
      normalComplete(e, kind, value), normalPending(t), normalPublish(t), normalReceiveAny,
      emitCallback(callbackReport(external, e, e, id), true), normalQuery(e, id),
      normalReplace(1, 2), readFacts, discoverWork,
    }
  }
  action submittedInit = normalInit.then(sendSubmission(request)).then(receiveSubmission(request))
  action preparedInit = submittedInit.then(normalCreate(1)).then(normalClaim(1, 1)).then(normalRequest(t1))
  action callbackRunningInit = preparedInit.then(normalAuthorize(t1, callbackHandler))
    .then(normalGrant(t1)).then(normalCall(t1))
  action callbackReleasedInit = callbackRunningInit.then(normalPending(t1))
    .then(normalReceive(pendingReport(t1))).then(releaseWorker(1))
  action retryRunningInit = normalInit
    .then(sendSubmission({ ...request, definition: { ...definition, policy: RetryOnce } }))
    .then(receiveSubmission({ ...request, definition: { ...definition, policy: RetryOnce } }))
    .then(normalCreate(1)).then(normalClaim(1, 1)).then(normalRequest(t1))
    .then(normalAuthorize(t1, idempotentHandler)).then(normalGrant(t1)).then(normalCall(t1))
  action retryPendingInit = retryRunningInit.then(normalComplete(1, Failure, 2))
    .then(normalPublish(t1)).then(normalReceive(completionReport(external, t1)))
}

module normalUseAnalysis {
  import normalUseProfile(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false) as scenario
  action init = scenario::normalInit
  action normalInit = scenario::normalInit
  action callbackRunningInit = scenario::callbackRunningInit
  action callbackReleasedInit = scenario::callbackReleasedInit
  action retryPendingInit = scenario::retryPendingInit
  action step = scenario::normalStep
  action normalStep = scenario::normalStep
  val safety = scenario::normalSafety
  val normalSafety = scenario::normalSafety
  val submittedWitness = scenario::submittedWitness
  val reusedWitness = scenario::reusedWitness
  val callbackWitness = scenario::callbackWitness
  val releasedCompletionWitness = scenario::releasedCompletionWitness
  val readWitness = scenario::readWitness
  val retryWitness = scenario::retryWitness
  val failureAtomicWitness = scenario::failureAtomicWitness
  val discoveryWitness = scenario::discoveryWitness
  val succeededReached = scenario::succeededReached
  val failedReached = scenario::failedReached
  val waitingReached = scenario::waitingReached
}
