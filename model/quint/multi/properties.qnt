// Recheck execution safety against each Intent's own ledger and independent resource.
module multiIntentProperties {
  import multiIntentRecovery.* from "./recovery"
  export multiIntentRecovery.*
  import normalUseProperties.* from "../normal/properties"
  export normalUseProperties.*

  pure def ledgerScopedSafe(d: IntentData, x: ExternalState): bool = {
    val l = d.ledger
    l.outcomes.length() <= 1 and l.outcomes == l.firstOutcome
      and ((l.phase == Closed) iff l.outcomes.length() == 1)
      and l.outcomes.length() == l.commits.length()
      and l.outcomes.length() == l.history.select(a => a.kind == OutcomeStored).length()
      and l.outcomes == l.commits.foldl(List(), (os, c) => os.append(c.outcome))
      and l.commits.foldl(true, (ok, c) => ok and c.openAtCommit and c.sourceEligible
        and (c.outcome.kind == OutcomeCancelled or not(c.conflictsAtCommit))
        and (c.outcome.kind != OutcomeFailed or not(c.oldSuccessAtCommit)))
      and l.starts.foldl(true, (ok, s) => ok and s.openAtGrant and s.currentAtGrant and s.leaseValidAtGrant)
      and l.retries.foldl(true, (ok, r) => ok and r.safeAtReplacement)
      and l.reports.size() == l.history.select(a => a.kind == EvidenceStored).length()
      and l.reports.forall(r => reportSourceValid(l, r) and x.emitted.contains(r))
      and EXECUTIONS.forall(e => stickyLease(l, e) and grantMatchesHistory(l, e)
        and knowledgeHasEvidence(l, e) and l.starts.select(s => s.token.exec == e).length() <= 1
        and x.invocations.select(c => c.token.exec == e).length() <= 1)
      and x.invocations.foldl(true, (ok, c) => ok and c.incarnationAtCall == c.token.incarnation
        and l.starts.select(s => s.token == c.token).length() == 1)
      and l.outcomes.foldl(true, (ok, o) => ok and (match o.exec {
        | NoCurrent => o.kind == OutcomeCancelled and o.value == 0
        | Current(e) => l.reports.exists(r => r.exec == e and r.value == o.value
            and r.kind == (if (o.kind == OutcomeSucceeded) Success else Failure))
      }))
  }
  pure def handlersScopedSafe(d: IntentData, x: ExternalState, i: int): bool = {
    val u = d.use
    val l = d.ledger
    val entry = focused(u)
    u.launches.length() == x.invocations.length()
      and u.launches.foldl(true, (ok, call) => ok and call.authorizationStored
        and boundCorrect(call.binding, entry) and call.binding == u.bindings.get(call.token.exec)
        and (match call.binding {
          | NoHandler => false
          | BoundHandler(b) => retryHandlerQualified(u, call.token.exec, b.handler, call.at)
            and call.completion == (if (b.handler.pending) CallbackBinding(correlation(i, call.token.exec)) else NoCompletion)
        }))
      and EXECUTIONS.forall(e => match u.bindings.get(e) {
        | NoHandler => l.attempts.get(e).grant == NoGrant
        | BoundHandler(b) => boundCorrect(BoundHandler(b), entry) and b.context == i
          and l.attempts.get(e).grant != NoGrant
          and l.attempts.get(e).completion == (if (b.handler.pending) CallbackBinding(correlation(i, e)) else NoCompletion)
      })
      and u.acceptances.foldl(true, (ok, w) => ok and w.definition == entry.request.definition and acceptanceSound(w))
      and u.retries.foldl(true, (ok, r) => ok and r.context == i and r.definition == entry.request.definition
        and ((not(r.repeatAccepted) and not(safeToReplace(r.before, r.oldExec))) implies (match r.binding {
          | NoHandler => false
          | BoundHandler(old) => old.context == i and old.handler.idempotent and r.at <= old.handler.validThrough
            and u.launches.foldl(true, (valid, call) => valid
              and (call.token.exec == r.newExec implies call.at <= old.handler.validThrough))
        })))
  }
  val multiExecutionSafety = INTENTS.forall(i => {
    val d = multiStore.intents.get(i)
    ledgerScopedSafe(d, resources.get(i)) and handlersScopedSafe(d, resources.get(i), i)
  })
  val directoryScoped = multiStore.catalog.length() <= INTENTS.size()
    and INTENTS.forall(i => {
      val entries = multiStore.catalog.select(e => e.id == i)
      val d = multiStore.intents.get(i)
      (d.exists iff entries.length() == 1) and (d.exists implies
        d.use.entries == entries and entries.nth(0).context == i)
    }) and multiStore.catalog.foldl(true, (ok, e) => ok and INTENTS.contains(e.id)
      and multiStore.catalog.foldl(true, (unique, other) => unique and (e.id == other.id or
        e.context != other.context and (e.request.identity == Unkeyed or e.request.identity != other.request.identity))))
  val sharedSessionsSafe = WORKERS.forall(w => INTENTS.forall(i => {
    val local = localFor(i, w)
    val l = multiStore.intents.get(i).ledger
    local.alive == sharedWorkers.get(w).alive and local.incarnation == sharedWorkers.get(w).incarnation
      and local.grants.forall(t => l.attempts.get(t.exec).grant == StartGrant(t))
      and local.receipts.forall(r => l.reports.contains(r))
  }))
  val transportScoped = multiNetwork.messages.forall(envelope => INTENTS.contains(envelope.intent)
    and (match envelope.message {
      | ResultReport(r) => resources.get(envelope.intent).emitted.contains(r)
      | StoredReceipt(r) => multiStore.intents.get(envelope.intent).ledger.reports.contains(r)
      | StartReply(t) => multiStore.intents.get(envelope.intent).ledger.attempts.get(t.exec).grant == StartGrant(t)
      | StartRequest(_) => true
    }))
  // Compare actual post-state with the observation before checking non-target frames.
  val scopeIsolation = {
    val w = scopeObservation
    w.after == multiStore and w.workersAfter == sharedWorkers and w.resourcesAfter == resources
      and w.before.catalog.foldl(true, (ok, e) => ok and w.after.catalog.select(saved => saved == e).length() == 1)
      and w.after.contractTime >= w.before.contractTime
      and INTENTS.forall(i => {
        val before = w.before.intents.get(i)
        val after = w.after.intents.get(i)
        ((i != w.target) implies (if (w.contractTimesChanged)
          after == { ...before, use: { ...before.use, contractTime: after.use.contractTime } } else after == before))
          and after.use.contractTime == multiStore.contractTime
          and (before.ledger.outcomes.length() > 0 implies after.ledger.outcomes == before.ledger.outcomes)
          and ((i != w.target) implies w.resourcesAfter.get(i) == w.resourcesBefore.get(i))
          and WORKERS.forall(worker =>
            (i != w.target and not(w.workerSessionChanged)) implies
              w.workersAfter.get(worker).slots.get(i) == w.workersBefore.get(worker).slots.get(i))
      })
  }
}
