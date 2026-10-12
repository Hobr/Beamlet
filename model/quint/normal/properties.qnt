// Independent checks over submission, actual launch snapshots and atomic acceptance effects.
module normalUseProperties {
  import normalUseActions.* from "./actions"
  export normalUseActions.*

  pure def boundCorrect(b: HandlerBinding, entry: SubmissionEntry): bool = match b {
    | NoHandler => false
    | BoundHandler(s) => s.definition == entry.request.definition and s.context == entry.context
        and s.handler.operation == entry.request.definition.operation
  }
  pure def submissionSound(w: SubmissionObservation): bool = {
    val id = existingId(w.before, w.request)
    w.beforeLedger == w.afterLedger and w.outcomes == w.beforeLedger.outcomes
      and w.reply.request == w.request and (match w.reply.result {
      | CreatedIntent(created) => id == 0 and created == w.before.length() + 1
          and w.after == w.before.append({ id: created, request: w.request, context: created })
      | DefinitionConflict(conflict) => id == conflict and id > 0 and w.after == w.before
          and w.before.nth(id - 1).request.definition != w.request.definition
      | ExistingIntent(existing) => id == existing.id and id > 0 and w.after == w.before
          and w.before.nth(id - 1).request.definition == w.request.definition
          and existing.outcomes == (if (id == 1) w.outcomes else List())
    })
  }
  val submissionIdentitySound = usage.entries == usage.creations
    and usage.entries.foldl(true, (ok, e) => ok and usage.entries.foldl(true, (unique, other) =>
      unique and ((e.id != other.id and e.request.identity != Unkeyed)
        implies e.request.identity != other.request.identity)))
    and usage.submissions.foldl(true, (ok, w) => ok and submissionSound(w))

  val handlerLaunchesSound = external.invocations.length() == usage.launches.length()
    and usage.launches.foldl(true, (ok, w) => ok
    and w.authorizationStored and boundCorrect(w.binding, focused(usage))
    and usage.bindings.get(w.token.exec) == w.binding
    and (match w.binding {
      | NoHandler => false
      | BoundHandler(b) => retryHandlerQualified(usage, w.token.exec, b.handler, w.at)
          and w.completion == (if (b.handler.pending) CallbackBinding(w.token.exec) else NoCompletion)
    }))
    and EXECUTIONS.forall(e => match usage.bindings.get(e) {
      | NoHandler => authority.durable.attempts.get(e).grant == NoGrant
      | BoundHandler(b) => boundCorrect(BoundHandler(b), focused(usage))
          and authority.durable.attempts.get(e).grant != NoGrant
          and authority.durable.attempts.get(e).completion == (if (b.handler.pending) CallbackBinding(e) else NoCompletion)
    })
  val retryContractsSound = usage.retries.foldl(true, (ok, w) => ok
    and w.repeatAccepted == ALLOW_REPEAT and w.definition == focused(usage).request.definition
    and w.context == focused(usage).context and (safeToReplace(w.before, w.oldExec) or w.repeatAccepted or (match w.binding {
      | NoHandler => false
      | BoundHandler(b) => b.handler.idempotent and w.at <= b.handler.validThrough
          and b.definition == w.definition and b.context == w.context
    })))
  // Check the original window independently of retryHandlerQualified and the new declaration.
  val retryCallsOriginalContract = usage.retries.foldl(true, (ok, r) => ok
    and ((not(r.repeatAccepted) and not(safeToReplace(r.before, r.oldExec))) implies (match r.binding {
      | NoHandler => false
      | BoundHandler(old) => usage.launches.foldl(true, (valid, call) => valid
          and (call.token.exec == r.newExec implies call.at <= old.handler.validThrough))
    })))
  // Recompute from the original definition, grant/knowledge and accepted contract window.
  pure def observedStopRequired(d: Definition, l: Ledger, b: HandlerBinding, at: int): bool =
    d.policy == StopOnFailure or EXECUTIONS.filter(e => l.attempts.get(e).exists).size() >= 2
      or (match l.current {
        | NoCurrent => false
        | Current(e) => not(l.attempts.get(e).grant == NoGrant
            or l.attempts.get(e).knowledge == NotExecutedKnown or ALLOW_REPEAT
            or (match b {
              | NoHandler => false
              | BoundHandler(s) => s.handler.idempotent and at <= s.handler.validThrough
            }))
      })
  pure def acceptanceSound(w: AcceptanceObservation): bool = {
    val recorded = applyReport(w.before, w.report)
    val o: Outcome = { kind: if (w.report.kind == Success) OutcomeSucceeded else OutcomeFailed,
      exec: Current(w.report.exec), value: w.report.value }
    val shouldStop = observedStopRequired(w.definition, w.before, w.binding, w.at)
    val terminal = (w.report.kind == Success or (w.report.kind == Failure and shouldStop)) and canCommit(recorded, o)
    w.stop == shouldStop and w.after.reports.contains(w.report)
      and w.after.history.length() >= w.before.history.length() + 1
      and (if (terminal) w.after.outcomes == w.before.outcomes.append(o) and w.after.phase == Closed
        and w.after.history.length() == recorded.history.length() + 1
        else w.after.outcomes == w.before.outcomes)
  }
  val normalAcceptanceAtomic = usage.acceptances.foldl(true, (ok, w) => ok
    and w.definition == focused(usage).request.definition and acceptanceSound(w))
  val factReadsSound = usage.reads.foldl(true, (ok, w) => ok
    and w.reports == w.ledger.reports and w.outcomes == w.ledger.outcomes)
  val policyStopsSound = usage.stops.foldl(true, (ok, w) => ok
    and w.definition == focused(usage).request.definition
    and observedStopRequired(w.definition, w.before, w.binding, w.at)
    and w.after.phase == Closed and w.before.phase == Open
    and w.after.outcomes.length() == w.before.outcomes.length() + 1
    and w.after.reports == w.before.reports and w.after.history.length() == w.before.history.length() + 1)
  val normalSafety = safety and submissionIdentitySound and handlerLaunchesSound
    and retryContractsSound and normalAcceptanceAtomic and factReadsSound and policyStopsSound
    and retryCallsOriginalContract

  val submittedWitness = usage.marks.contains(SubmittedMark)
  val reusedWitness = usage.marks.contains(ReusedMark)
  val identityConflictWitness = usage.marks.contains(DefinitionConflictMark)
  val callbackWitness = usage.marks.contains(CallbackMark)
  val releasedCompletionWitness = usage.marks.contains(ReleasedMark) and usage.marks.contains(CallbackMark) and succeededReached
  val readWitness = usage.marks.contains(ReadMark)
  val retryWitness = usage.marks.contains(RetriedMark)
  val failureAtomicWitness = usage.marks.contains(AtomicFailureMark)
  val discoveryWitness = usage.marks.contains(DiscoveredMark) and usage.discovered.size() > 0
}
