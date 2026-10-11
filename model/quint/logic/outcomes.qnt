// Terminal qualification and atomic outcome/evidence updates.
module coreLogicOutcomes {
  import coreLogicDispositions.* from "./dispositions"
  export coreLogicDispositions.*

  pure def ordinarySourceEligible(l: Ledger, o: Outcome): bool = match o.exec {
    | NoCurrent => o.kind == OutcomeCancelled
    | Current(e) => l.current == Current(e) and noConflicts(l) and {
        if (o.kind == OutcomeSucceeded)
          judgmentKnowledge(l, e) == SuccessKnown and hasEvidence(l, e, Success)
        else if (o.kind == OutcomeFailed)
          judgmentKnowledge(l, e) == FailureKnown and hasEvidence(l, e, Failure)
            and noUnresolvedRisk(l) and not(oldSuccessNeedsReconciliation(l, e))
        else false
      }
  }

  pure def adoptedResultEligible(l: Ledger, o: Outcome): bool =
    noConflicts(l) and l.decisions.select(w =>
      o.exec == Current(w.decision.report.exec) and applicableBindings(l).exists(b =>
        b.item.report == w.decision.report and l.decisions.nth(b.decisionIndex) == w) and (
          (o.kind == OutcomeSucceeded and w.decision.kind == AdoptSuccess and w.decision.report.kind == Success)
          or (o.kind == OutcomeFailed and w.decision.kind == AdoptFailure and w.decision.report.kind == Failure
            and l.current == o.exec and noUnresolvedRisk(l) and not(oldSuccessForOutcome(l, o)))
        )).length() > 0

  pure def sourceEligible(l: Ledger, o: Outcome): bool =
    ordinarySourceEligible(l, o) or adoptedResultEligible(l, o)

  pure def canCommit(l: Ledger, o: Outcome): bool =
    l.phase == Open and l.outcomes.length() == 0 and sourceEligible(l, o)

  pure def applyCommit(l: Ledger, o: Outcome): Ledger = {
    val witness: CommitWitness = {
      outcome: o, openAtCommit: l.phase == Open, sourceEligible: sourceEligible(l, o),
      oldSuccessAtCommit: oldSuccessForOutcome(l, o), conflictsAtCommit: not(noConflicts(l)),
    }
    val updated = { ...l, phase: Closed, outcomes: l.outcomes.append(o),
      firstOutcome: if (l.outcomes.length() == 0) List(o) else l.firstOutcome,
      commits: l.commits.append(witness),
      history: l.history.append({ kind: OutcomeStored, exec: o.exec }) }
    advanceJudgment(l, updated)
  }

  pure def recordAndMaybeCommit(l: Ledger, r: Report): Ledger = {
    val recorded = applyReport(l, r)
    val outcome: Outcome = { kind: OutcomeSucceeded, exec: Current(r.exec) }
    if (r.kind == Success and canCommit(recorded, outcome)) applyCommit(recorded, outcome)
    else recorded
  }

  pure def isLate(l: Ledger, r: Report): bool =
    l.phase == Closed or l.current != Current(r.exec) or l.attempts.get(r.exec).lease.invalidated
}
