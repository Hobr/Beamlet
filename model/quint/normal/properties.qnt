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
  pure def acceptanceSound(w: AcceptanceObservation): bool = {
    val recorded = applyReport(w.before, w.report)
    val o: Outcome = { kind: if (w.report.kind == Success) OutcomeSucceeded else OutcomeFailed,
      exec: Current(w.report.exec), value: w.report.value }
    val shouldStop = w.definition.policy == StopOnFailure
      or EXECUTIONS.filter(e => w.before.attempts.get(e).exists).size() >= 2
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
  val normalSafety = commandSafety and submissionIdentitySound and handlerLaunchesSound
    and retryContractsSound and normalAcceptanceAtomic and factReadsSound

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
