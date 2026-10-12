// Submission/reads are separate from transport; execution reuses the shared core ledger.
module normalUseActions {
  import normalUseLogic.* from "./logic"
  export normalUseLogic.*

  action sendSubmission(r: SubmissionRequest): bool = all {
    not(usage.requests.contains(r)), usage' = { ...usage, requests: usage.requests.union(Set(r)) },
    authority' = authority, workers' = workers, network' = network, external' = external, clock' = clock,
  }
  action receiveSubmission(r: SubmissionRequest): bool = all {
    authority.online, usage.requests.contains(r), canSubmit(usage, r),
    usage' = applySubmission(usage, authority.durable, r),
    authority' = authority, workers' = workers, network' = network, external' = external, clock' = clock,
  }
  action loseSubmissionReply = all {
    usage.replies.size() > 0, usage' = { ...usage, replies: Set() },
    authority' = authority, workers' = workers, network' = network, external' = external, clock' = clock,
  }
  action readFacts = all {
    authority.online, usage.entries.length() > 0,
    usage' = { ...usage, reads: usage.reads.append({ reports: authority.durable.reports,
      outcomes: authority.durable.outcomes, ledger: authority.durable }), marks: usage.marks.union(Set(ReadMark)) },
    authority' = authority, workers' = workers, network' = network, external' = external, clock' = clock,
  }
  // Recover candidates by durable facts; discovery conveys no startup authorization.
  action discoverWork = all {
    authority.online, usage.entries.length() > 0, authority.durable.phase == Open,
    usage' = { ...usage, discovered: EXECUTIONS.filter(e => {
      val a = authority.durable.attempts.get(e)
      a.exists and authority.durable.current == Current(e)
        and (a.phase == Prepared or a.phase == Unknown or a.phase == Waiting)
    }), marks: usage.marks.union(Set(DiscoveredMark)) },
    authority' = authority, workers' = workers, network' = network, external' = external, clock' = clock,
  }
  action normalCreate(e: int): bool = all { usage.entries.length() > 0, createExecution(e), usage' = usage }
  action normalClaim(e: int, w: int): bool = all { claimExecution(e, w), usage' = usage }
  action normalRequest(t: Token): bool = all { requestStart(t), usage' = usage }
  action normalGrant(t: Token): bool = all { receiveGrant(t), usage' = usage }

  // Correlation and the actual Handler contract are committed with Start Authorization.
  action normalAuthorize(t: Token, h: Handler): bool = {
    val authorized = applyAuthorize(authority.durable, t, clock)
    val a = authorized.attempts.get(t.exec)
    all {
      authority.online, network.contains(StartRequest(t)), compatible(usage, h),
      canAuthorize(authority.durable, t, clock), usage.bindings.get(t.exec) == NoHandler,
      retryHandlerQualified(usage, t.exec, h, usage.contractTime),
      authority' = { ...authority, durable: { ...authorized, attempts: authorized.attempts.set(t.exec,
        { ...a, completion: if (h.pending) CallbackBinding(t.exec) else NoCompletion }) } },
      usage' = { ...usage, bindings: usage.bindings.set(t.exec, bindingFor(usage, h)) },
      workers' = workers, network' = network.exclude(Set(StartRequest(t))).union(Set(StartReply(t))),
      external' = external, clock' = clock,
    }
  }
  action normalCall(t: Token): bool = all {
    usage.bindings.get(t.exec) != NoHandler,
    (match usage.bindings.get(t.exec) {
      | NoHandler => false
      | BoundHandler(b) => retryHandlerQualified(usage, t.exec, b.handler, usage.contractTime)
    }), callExternal(t),
    usage' = { ...usage, launches: usage.launches.append({ token: t, binding: usage.bindings.get(t.exec),
      completion: authority.durable.attempts.get(t.exec).completion,
      authorizationStored: authority.durable.attempts.get(t.exec).grant == StartGrant(t), at: usage.contractTime }) },
  }
  action normalComplete(e: int, kind: ReportKind, value: int): bool = all {
    external.effects.contains(e), external.finished.get(e) == ResourceUnfinished,
    kind == Success or kind == Failure,
    authority' = authority, workers' = workers, network' = network, clock' = clock, usage' = usage,
    external' = applyExternalCompletionValue(external, e, kind, value),
  }
  action normalPending(t: Token): bool = all {
    supportsPending(usage, t.exec), publishPending(t),
    usage' = { ...usage, marks: usage.marks.union(Set(PendingMark)) },
  }
  action normalPublish(t: Token): bool = all { publishCompletion(t), usage' = usage }
  action normalReceive(r: Report): bool = {
    val after = receiveWithPolicy(usage, authority.durable, r)
    all {
      authority.online, network.contains(ResultReport(r)), reportSourceValid(authority.durable, r),
      r.kind != Pending or supportsPending(usage, r.exec), not(authority.durable.reports.contains(r)),
      authority' = { ...authority, durable: after },
      usage' = { ...usage, acceptances: usage.acceptances.append({ report: r,
        before: authority.durable, after: after, stop: stopRequired(usage, authority.durable),
        definition: focused(usage).request.definition }),
        marks: if (r.kind == Failure and after.outcomes.length() > authority.durable.outcomes.length())
          usage.marks.union(Set(AtomicFailureMark)) else usage.marks },
      workers' = workers, network' = network.union(Set(StoredReceipt(r))), external' = external, clock' = clock,
    }
  }
  action normalReceiveAny = {
    val rs = network.filter(m => match m { | ResultReport(_) => true | _ => false })
    all { rs.size() > 0, nondet m = rs.oneOf()
      match m { | ResultReport(r) => normalReceive(r) | _ => all { invalidMessageVariant, usage' = usage } },
    }
  }
  action emitCallback(r: Report, verified: bool): bool = all {
    canCallback(usage, authority.durable, external, r, verified),
    usage' = { ...usage, marks: usage.marks.union(Set(CallbackMark)) },
    authority' = authority, workers' = workers, clock' = clock,
    network' = network.union(Set(ResultReport(r))),
    external' = { ...external, emitted: external.emitted.union(Set(r)) },
  }
  action normalQuery(e: int, id: int): bool = all {
    supportsQuery(usage, e), queryExternal(e, id),
    usage' = { ...usage, marks: usage.marks.union(Set(QueriedMark)) },
  }
  action releaseWorker(w: int): bool = all {
    crashWorker(w), usage' = { ...usage, marks: usage.marks.union(Set(ReleasedMark)) },
  }
  action normalReplace(oldExec: int, newExec: int): bool = all {
    authority.online, focused(usage).request.definition.policy == RetryOnce,
    canReplaceWithEvidence(authority.durable, oldExec, newExec, idempotencyValid(usage, oldExec, usage.contractTime)),
    authority' = { ...authority, durable: applyReplaceWithEvidence(authority.durable, oldExec, newExec,
      idempotencyValid(usage, oldExec, usage.contractTime)) },
    usage' = { ...usage, retries: usage.retries.append({ oldExec: oldExec, newExec: newExec,
      binding: usage.bindings.get(oldExec), at: usage.contractTime, repeatAccepted: ALLOW_REPEAT,
      before: authority.durable,
      definition: focused(usage).request.definition, context: focused(usage).context }),
      marks: usage.marks.union(Set(RetriedMark)) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }
}
