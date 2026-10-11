// Report authentication, conflict detection and durable evidence projection.
module coreLogicReports {
  import coreLogicJudgment.* from "./judgment"
  export coreLogicJudgment.*

  pure def reportSourceValid(l: Ledger, r: Report): bool = {
    val attempt = l.attempts.get(r.exec)
    val originValid = match r.origin {
      | ByWorker(t) => t.exec == r.exec and attempt.grant == StartGrant(t)
          and (r.kind == Pending or r.kind == Success or r.kind == Failure)
      | ByQuery => r.kind != Pending
    }
    attempt.exists and originValid
  }

  pure def sameReportIdentity(a: Report, b: Report): bool =
    a.id == b.id and a.exec == b.exec and a.origin == b.origin

  pure def reportConflicts(l: Ledger, r: Report): bool = {
    val known = l.attempts.get(r.exec).knowledge
    val identityConflict = l.reports.exists(old => sameReportIdentity(old, r) and old != r)
    val resultConflict = (known == SuccessKnown and (r.kind == Failure or r.kind == NotExecuted))
      or (known == FailureKnown and r.kind == Success)
      or (known == NotExecutedKnown and r.kind == Success)
    identityConflict or resultConflict
  }

  pure def knowledgeOf(kind: ReportKind): Knowledge =
    if (kind == Success) SuccessKnown
    else if (kind == Failure) FailureKnown
    else if (kind == NotExecuted) NotExecutedKnown
    else NoKnowledge

  pure def applyReport(l: Ledger, r: Report): Ledger = {
    val attempt = l.attempts.get(r.exec)
    val conflict = attempt.conflict or reportConflicts(l, r)
    val incoming = knowledgeOf(r.kind)
    val known = if (attempt.knowledge == NoKnowledge and not(conflict))
      incoming else attempt.knowledge
    val phase = if (conflict or r.kind == NotFound) attempt.phase
      else if (r.kind == Pending) {
        if (attempt.phase == Resolved) Resolved else Waiting
      } else Resolved
    val updated = { ...attempt, phase: phase, knowledge: known, conflict: conflict,
      negativeSeen: attempt.negativeSeen or r.kind == NotFound }
    val history = l.history.append({ kind: EvidenceStored, exec: Current(r.exec) })
    val recorded = { ...l, attempts: l.attempts.set(r.exec, updated), reports: l.reports.union(Set(r)),
      history: if (conflict) history.append({ kind: ConflictStored, exec: Current(r.exec) }) else history }
    advanceJudgment(l, recorded)
  }
}
