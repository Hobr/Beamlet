// Reconciliation, conflict, supersession and revision properties.
module corePropertiesReconciliation {
  import coreLogicRules.* from "../logic/rules"
  export coreLogicRules.*

  val reconciliationQualified = authority.durable.decisions.foldl(true, (ok, w) =>
    ok and w.openAtDecision and w.actorQualified and w.contractQualified
      and w.coverageQualified and w.evidenceQualified
      and w.decision.reviewedRevision == w.acceptedRevision
      and w.acceptedBase.current == w.acceptedCurrent and w.acceptedBase.reports == w.acceptedReports
      and w.acceptedReports.contains(w.decision.report))

  // Validate actual pinned versions and accepted definitions, independently of actorQualified.
  val automaticRuleVersionsSound = authority.durable.decisions.foldl(true, (ok, w) =>
    ok and registeredRuleQualified(w.rulesAtDecision, w.decision))

  val reconciledEvidencePreserved = authority.durable.decisions.foldl(true, (ok, w) =>
    ok and w.acceptedReports.forall(r => authority.durable.reports.contains(r)))

  val reconciliationAuditAtomic = authority.durable.decisions.length()
    == authority.durable.history.select(a => a.kind == EvidenceReconciled).length()

  val conflictCoverageSound = authority.durable.decisions.foldl(true, (ok, w) => {
    val required = w.acceptedReports.filter(r => w.acceptedBase.attempts.get(r.exec).conflict)
    ok and w.coverageQualified and w.evidenceQualified
      and (if (w.decision.evidence.size() == 0) required.size() == 0
        else evidenceReports(w.decision) == required.union(Set(w.decision.report))
          and evidenceReports(w.decision).size() == w.decision.evidence.size())
  })

  // Replay links against the accepted prefix, independently of the admission flag.
  val supersessionLinksSound = {
    val checked = authority.durable.decisions.foldl(
      { valid: true, bindings: Set(), index: 0 }, (s, w) => {
        val reports = decisionTreatments(w.decision).map(i => i.report)
        val refs = w.decision.supersedes
        val covered = s.bindings.forall(b => reports.contains(b.item.report) implies
          refs.exists(r => r.decisionIndex == b.decisionIndex and r.reports.contains(b.item.report)))
        val targets = refs.forall(r => r.decisionIndex >= 0 and r.decisionIndex < s.index
          and r.reports.size() > 0 and r.reports.forall(report =>
            reports.contains(report) and s.bindings.exists(b =>
              b.decisionIndex == r.decisionIndex and b.item.report == report)))
        {
          valid: s.valid and w.supersessionQualified and covered and targets
            and refs.map(r => r.decisionIndex).size() == refs.size(),
          bindings: advanceBindings(s.bindings, w.decision, s.index), index: s.index + 1,
        }
      })
    checked.valid
  }

  val decisionsImmutable = authority.durable.decisions.foldl(List(), (ds, w) => ds.append(w.decision))
    == authority.durable.decisionSnapshots

  val dispositionBindingsUnique = {
    val bindings = historicalBindings(authority.durable.decisions)
    bindings.forall(a => bindings.forall(b => a.item.report == b.item.report implies a == b))
  }

  val conflictHistoryPreserved = authority.durable.reports.forall(r =>
    authority.durable.reports.forall(s =>
      (r.exec == s.exec and r != s and
        (sameReportIdentity(r, s)
          or (r.kind == Success and (s.kind == Failure or s.kind == NotExecuted))
          or (s.kind == Success and (r.kind == Failure or r.kind == NotExecuted))))
        implies authority.durable.attempts.get(r.exec).conflict))

  val terminalConflictsResolved = authority.durable.commits.foldl(true, (ok, w) =>
    ok and (w.outcome.kind == OutcomeCancelled or not(w.conflictsAtCommit)))

  val excludedAllKnowledgeSound = EXECUTIONS.forall(e => {
    val l = authority.durable
    val items = judgmentItems(l).filter(i => i.report.exec == e)
    (items.size() > 0 and items.forall(i => i.treatment == ExcludeEvidence))
      implies judgmentKnowledge(l, e) == NoKnowledge
  })

  val allExcludedCommitSound = authority.durable.commands.foldl(true, (ok, r) =>
    ok and (r.command.decision.kind == ExcludeAllEvidence implies r.outcomes == List()))

  // Independent change-chain validation catches omitted increments and spurious bumps.
  val judgmentRevisionSound = {
    val l = authority.durable
    val checked = l.judgmentChanges.foldl(
      { valid: true, view: judgmentView(initialLedger), revision: 0 },
      (s, w) => {
        valid: s.valid and w.before == s.view and w.before != w.after
          and w.previous == s.revision and w.next == w.previous + 1,
        view: w.after, revision: w.next,
      })
    checked.valid and l.revision == checked.revision and judgmentView(l) == checked.view
  }
}
