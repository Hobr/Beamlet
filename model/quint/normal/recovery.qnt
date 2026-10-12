// Recovery composes normal contracts with transport/fault windows; no governance actions.
module normalRecoveryActions {
  import normalUseProfile.* from "../beamletNormalUse"
  export normalUseProfile.*

  action normalResendGrant(t: Token): bool = all { resendGrant(t), usage' = usage }
  action normalRenew(t: Token): bool = all { renewLease(t), usage' = usage }
  action normalLoseMessage = all { loseAnyMessage, usage' = usage }
  action normalResendReport = all { resendAnyReport, usage' = usage }
  action normalReceipt = all { receiveAnyReceipt, usage' = usage }
  action normalAcknowledge = all { acknowledgeAnyDuplicate, usage' = usage }
  action normalDiscardOld(t: Token): bool = all { discardOldGrant(t), usage' = usage }
  action normalDiscardDuplicate(t: Token): bool = all { discardDuplicateGrant(t), usage' = usage }

  // A trusted callback sender retains the original verified report until durable acknowledgement.
  action redeliverCallback(r: Report): bool = all {
    external.emitted.contains(r), (match r.origin { | ByCallback(_) => true | _ => false }),
    not(network.contains(ResultReport(r))),
    network' = network.union(Set(ResultReport(r))),
    external' = { ...external, marks: external.marks.union(Set("callbackResent")) },
    authority' = authority, workers' = workers, clock' = clock, usage' = usage,
  }
  action normalStop(e: int): bool = {
    val o: Outcome = { kind: OutcomeFailed, exec: Current(e), value: knownResultValue(authority.durable, e, Failure) }
    val after = applyCommit(authority.durable, o)
    all {
      authority.online, usage.entries.length() > 0, stopRequired(usage, authority.durable),
      canCommit(authority.durable, o),
      authority' = { ...authority, durable: after },
      usage' = { ...usage, stops: usage.stops.append({ before: authority.durable, after: after,
        definition: focused(usage).request.definition, binding: usage.bindings.get(e), at: usage.contractTime }) },
      workers' = workers, network' = network, external' = external, clock' = clock,
    }
  }

  action recoveryFaultStep = {
    nondet e = EXECUTIONS.oneOf()
    nondet w = WORKERS.oneOf()
    nondet n = CLOCK_VALUES.oneOf()
    val known = knownTokens(workers, network)
    val fallback: Token = { exec: e, worker: w, incarnation: workers.get(w).incarnation, generation: 1 }
    nondet t = (if (known.size() > 0) known else Set(fallback)).oneOf()
    val callbacks = external.emitted.filter(r => match r.origin { | ByCallback(_) => true | _ => false })
    val fallbackReport: Report = { id: 1, exec: e, kind: Success, value: 0, origin: ByCallback(e) }
    nondet r = (if (callbacks.size() > 0) callbacks else Set(fallbackReport)).oneOf()
    any {
      normalClock(n), normalExpire(e), normalRenew(t), normalResendGrant(t),
      releaseWorker(w), normalRestartWorker(w), normalCrashCoordinator, normalRestartCoordinator,
      normalLoseMessage, loseSubmissionReply, normalResendReport, redeliverCallback(r),
      normalReceipt, normalAcknowledge, normalDiscardOld(t), normalDiscardDuplicate(t), normalStop(e),
    }
  }
  action retryAuthorizedInit = retryPendingInit.then(normalReplace(1, 2))
    .then(normalClaim(2, 2)).then(normalRequest(t2)).then(normalAuthorize(t2, idempotentHandler))
    .then(normalGrant(t2))

  // Give execution and faults separate choices so early faults do not erase normal coverage.
  action recoveryStep = any { normalStep, recoveryFaultStep }
  val callbackRedeliveryWitness = external.marks.contains("callbackResent")
  val recoveryCompletionWitness = coordinatorRestartReached and (succeededReached or failedReached)
  val policyStopWitness = usage.stops.length() > 0
}
