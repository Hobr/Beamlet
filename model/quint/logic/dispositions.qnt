// Evidence interpretation, conflict coverage and explicit supersession bindings.
module coreLogicDispositions {
  import coreLogicReports.* from "./reports"
  export coreLogicReports.*

  pure def evidenceReports(d: Decision): Set[Report] = d.evidence.map(i => i.report)

  // Conservative scope: every stored report on every historically conflicted attempt.
  pure def conflictReports(l: Ledger): Set[Report] =
    l.reports.filter(r => l.attempts.get(r.exec).conflict)

  pure def conflictResolved(l: Ledger, e: int): bool =
    l.reports.filter(r => r.exec == e).forall(r => applicableBindings(l).exists(b =>
      b.item.report == r and l.decisions.nth(b.decisionIndex).decision.evidence.size() > 0))

  pure def noConflicts(l: Ledger): bool =
    EXECUTIONS.forall(e => not(l.attempts.get(e).conflict) or conflictResolved(l, e))

  pure def decisionTreatments(d: Decision): Set[EvidenceDisposition] =
    if (d.evidence.size() > 0) d.evidence
    else Set({ report: d.report,
      treatment: if (decisionIsTerminal(d)) KeepEvidence else ExcludeEvidence, basis: d.basis })

  pure def advanceBindings(bindings: Set[DispositionBinding], d: Decision, index: int): Set[DispositionBinding] =
    bindings.filter(b => not(d.supersedes.exists(s =>
      s.decisionIndex == b.decisionIndex and s.reports.contains(b.item.report))))
      .union(decisionTreatments(d).map(i => { decisionIndex: index, item: i }))

  pure def historicalBindings(ds: List[DecisionWitness]): Set[DispositionBinding] = {
    val folded = ds.foldl({ bindings: Set(), index: 0 }, (s, w) =>
      { bindings: advanceBindings(s.bindings, w.decision, s.index), index: s.index + 1 })
    folded.bindings
  }

  pure def applicableBindings(l: Ledger): Set[DispositionBinding] =
    historicalBindings(l.decisions).filter(b => dispositionScopeCurrent(l, l.decisions.nth(b.decisionIndex)))

  pure def requiredSupersessions(l: Ledger, d: Decision): Set[Supersession] = {
    val bindings = historicalBindings(l.decisions)
    val reports = decisionTreatments(d).map(i => i.report)
    bindings.map(b => b.decisionIndex).map(index => {
      decisionIndex: index,
      reports: bindings.filter(b => b.decisionIndex == index and reports.contains(b.item.report)).map(b => b.item.report),
    }).filter(s => s.reports.size() > 0)
  }

  // Proposal construction only. Handling never fills in or refreshes caller references.
  pure def withSupersessions(l: Ledger, d: Decision): Decision =
    { ...d, supersedes: requiredSupersessions(l, d) }

  pure def decisionSupersessionsQualified(l: Ledger, d: Decision): bool =
    d.supersedes == requiredSupersessions(l, d)

  pure def judgmentItems(l: Ledger): Set[EvidenceDisposition] =
    applicableBindings(l).filter(b => l.decisions.nth(b.decisionIndex).decision.evidence.size() > 0)
      .map(b => b.item)

  pure def judgmentKnowledge(l: Ledger, e: int): Knowledge = {
    val classified = judgmentItems(l).filter(i => i.report.exec == e)
    val kept = classified.filter(i => i.treatment == KeepEvidence).map(i => i.report)
    if (kept.exists(r => r.kind == Success)) SuccessKnown
    else if (kept.exists(r => r.kind == Failure)) FailureKnown
    else if (kept.exists(r => r.kind == NotExecuted)) NotExecutedKnown
    else if (classified.size() > 0) NoKnowledge
    else l.attempts.get(e).knowledge
  }

  pure def noUnresolvedRisk(l: Ledger): bool = EXECUTIONS.forall(e => {
    val attempt = l.attempts.get(e)
    not(attempt.exists) or attempt.grant == NoGrant or judgmentKnowledge(l, e) != NoKnowledge
  })

  pure def hasEvidence(l: Ledger, e: int, kind: ReportKind): bool =
    l.reports.exists(r => r.exec == e and r.kind == kind and reportSourceValid(l, r)
      and not(excludedForJudgment(l, r)))

  pure def decisionScopeCurrent(l: Ledger, d: Decision): bool =
    d.reviewedRevision == l.revision

  pure def dispositionScopeCurrent(l: Ledger, w: DecisionWitness): bool =
    w.acceptedBase == judgmentBase(l)

  pure def excludedForJudgment(l: Ledger, r: Report): bool =
    applicableBindings(l).exists(b => b.item.report == r and b.item.treatment == ExcludeEvidence)

  // A disposition concerns this exact report and judgment, not future evidence.
  pure def oldSuccessNeedsReconciliation(l: Ledger, e: int): bool =
    l.reports.exists(r => r.exec != e and r.kind == Success and reportSourceValid(l, r)
      and not(excludedForJudgment(l, r)))

  pure def oldSuccessForOutcome(l: Ledger, o: Outcome): bool = match o.exec {
    | NoCurrent => false
    | Current(e) => oldSuccessNeedsReconciliation(l, e)
  }

  pure def decisionIsTerminal(d: Decision): bool = d.kind == AdoptSuccess or d.kind == AdoptFailure
}
