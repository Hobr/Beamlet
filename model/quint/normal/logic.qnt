// Submission lookup, compatible Handler snapshots, bounded retry and failure policy.
module normalUseLogic {
  import normalUseState.* from "./state"
  export normalUseState.*

  pure def existingId(entries: List[SubmissionEntry], r: SubmissionRequest): int = match r.identity {
    | Unkeyed => 0
    | StableKey(_) => entries.foldl(0, (id, entry) =>
        if (entry.request.identity == r.identity) entry.id else id)
  }
  pure def focused(u: UseState): SubmissionEntry =
    if (u.entries.length() > 0) u.entries.nth(0) else { id: 0, request: request, context: 0 }

  pure def submissionReply(u: UseState, l: Ledger, r: SubmissionRequest): SubmissionReply = {
    val id = existingId(u.entries, r)
    val result = if (id == 0) CreatedIntent(u.entries.length() + 1)
      else if (u.entries.nth(id - 1).request.definition != r.definition) DefinitionConflict(id)
      else ExistingIntent({ id: id, outcomes: if (id == 1) l.outcomes else List() })
    { request: r, result: result }
  }
  pure def canSubmit(u: UseState, r: SubmissionRequest): bool =
    existingId(u.entries, r) != 0 or u.entries.length() < 2

  pure def applySubmission(u: UseState, l: Ledger, r: SubmissionRequest): UseState = {
    val reply = submissionReply(u, l, r)
    val entry: SubmissionEntry = { id: u.entries.length() + 1, request: r, context: u.entries.length() + 1 }
    val entries = if (existingId(u.entries, r) == 0) u.entries.append(entry) else u.entries
    val mark = match reply.result {
      | CreatedIntent(_) => SubmittedMark | ExistingIntent(_) => ReusedMark | DefinitionConflict(_) => DefinitionConflictMark
    }
    { ...u, entries: entries,
      creations: if (existingId(u.entries, r) == 0) u.creations.append(entry) else u.creations,
      requests: u.requests.exclude(Set(r)), replies: u.replies.union(Set(reply)),
      submissions: u.submissions.append({ request: r, before: u.entries, after: entries,
        reply: reply, outcomes: l.outcomes, beforeLedger: l, afterLedger: l }),
      marks: u.marks.union(Set(mark)) }
  }

  pure def compatible(u: UseState, h: Handler): bool =
    u.entries.length() > 0 and h.operation == focused(u).request.definition.operation
  // A replacement relying on idempotency must retain the same external key protocol.
  pure def retryHandlerQualified(u: UseState, e: int, h: Handler, now: int): bool =
    u.retries.foldl(true, (ok, w) => ok and ((w.newExec == e and not(w.repeatAccepted)
      and not(safeToReplace(w.before, w.oldExec))) implies (match w.binding {
        | NoHandler => false
        | BoundHandler(b) => h.protocol == b.handler.protocol and h.idempotent and now <= h.validThrough
      })))

  pure def bindingFor(u: UseState, h: Handler): HandlerBinding = BoundHandler({
    handler: h, definition: focused(u).request.definition, context: focused(u).context,
  })
  pure def supportsPending(u: UseState, e: int): bool = match u.bindings.get(e) {
    | NoHandler => false | BoundHandler(b) => b.handler.pending
  }
  pure def supportsQuery(u: UseState, e: int): bool = match u.bindings.get(e) {
    | NoHandler => false | BoundHandler(b) => b.handler.query
  }
  // Authority checks current trusted contract facts against the original launch snapshot.
  // A static idempotent declaration alone is insufficient; time and input/context must agree.
  pure def idempotencyValid(u: UseState, e: int, now: int): bool = match u.bindings.get(e) {
    | NoHandler => false
    | BoundHandler(b) => b.handler.idempotent and now <= b.handler.validThrough
        and b.definition == focused(u).request.definition and b.context == focused(u).context
  }
  pure def stopRequired(u: UseState, l: Ledger): bool =
    focused(u).request.definition.policy == StopOnFailure
      or EXECUTIONS.filter(e => l.attempts.get(e).exists).size() >= 2

  pure def receiveWithPolicy(u: UseState, l: Ledger, r: Report): Ledger = {
    val recorded = recordAndMaybeCommit(l, r)
    val o: Outcome = { kind: OutcomeFailed, exec: Current(r.exec), value: r.value }
    if (r.kind == Failure and stopRequired(u, l) and canCommit(recorded, o)) applyCommit(recorded, o)
    else recorded
  }
  pure def callbackReport(x: ExternalState, e: int, c: int, id: int): Report = {
    id: id, exec: e, kind: if (x.finished.get(e) == ResourceSucceeded) Success else Failure,
    value: x.values.get(e), origin: ByCallback(c),
  }
  pure def canCallback(u: UseState, l: Ledger, x: ExternalState, r: Report, verified: bool): bool =
    verified and supportsPending(u, r.exec) and reportSourceValid(l, r)
      and x.finished.get(r.exec) != ResourceUnfinished
      and r.value == x.values.get(r.exec)
      and r.kind == (if (x.finished.get(r.exec) == ResourceSucceeded) Success else Failure)
      and (match r.origin { | ByCallback(_) => true | _ => false })
      and not(x.emitted.contains(r))
}
