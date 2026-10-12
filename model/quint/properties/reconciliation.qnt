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

  // 仅检查退役边界的绑定/版本保持;随后新证据或显式取代仍可合法改变判断.
  val ordinaryRuleRetirementSound = external.ruleRetirements.foldl(true, (ok, w) =>
    ok and w.previousRules.exists(r => r.rule == w.rule)
      and w.nextRules == w.previousRules.filter(r => r.rule != w.rule)
      and w.durableUnchanged and w.previousRevision == w.nextRevision
      and w.previousBindings == w.nextBindings)

  val reconciledEvidencePreserved = authority.durable.decisions.foldl(true, (ok, w) =>
    ok and w.acceptedReports.forall(r => authority.durable.reports.contains(r)))

  val reconciliationAuditAtomic = authority.durable.decisions.length()
    == authority.durable.history.select(a => a.kind == EvidenceReconciled).length()

  // 从接受时报告/尝试快照重算覆盖范围,避免只信任 coverageQualified 这一摘要.
  val conflictCoverageSound = authority.durable.decisions.foldl(true, (ok, w) => {
    val required = w.acceptedReports.filter(r => w.acceptedBase.attempts.get(r.exec).conflict)
    ok and w.coverageQualified and w.evidenceQualified
      and (if (w.decision.kind == WithdrawDisposition) w.decision.evidence.size() == 0
        else if (w.decision.evidence.size() == 0) required.size() == 0
        else evidenceReports(w.decision) == required.union(Set(w.decision.report))
          and evidenceReports(w.decision).size() == w.decision.evidence.size())
  })

  // Replay links against the accepted prefix, independently of the admission flag.
  val supersessionLinksSound = {
    val checked = authority.durable.decisions.foldl(
      { valid: true, bindings: Set(), index: 0 }, (s, w) => {
        val reports = decisionAffectedReports(w.decision)
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

  // 用仍保存的原报告重算历史矛盾;解除本次阻塞不允许擦除"曾经冲突"的事实.
  val conflictHistoryPreserved = authority.durable.reports.forall(r =>
    authority.durable.reports.forall(s =>
      (r.exec == s.exec and r != s and
        (sameReportIdentity(r, s)
          or (r.kind == Success and (s.kind == Failure or s.kind == NotExecuted))
          or (s.kind == Success and (r.kind == Failure or r.kind == NotExecuted))))
        implies authority.durable.attempts.get(r.exec).conflict))

  // 检查提交当刻的阻塞;之后到来的冲突不能追溯改写已有 Outcome,取消独立允许.
  val terminalConflictsResolved = authority.durable.commits.foldl(true, (ok, w) =>
    ok and (w.outcome.kind == OutcomeCancelled or not(w.conflictsAtCommit)))

  // 排除全部报告只消除当前可采用知识,不证明成功,失败或可靠未执行.
  val excludedAllKnowledgeSound = EXECUTIONS.forall(e => {
    val l = authority.durable
    val items = judgmentItems(l).filter(i => i.report.exec == e)
    (items.size() > 0 and items.forall(i => i.treatment == ExcludeEvidence))
      implies judgmentKnowledge(l, e) == NoKnowledge
  })

  val allExcludedCommitSound = authority.durable.commands.foldl(true, (ok, r) =>
    ok and (r.command.decision.kind == ExcludeAllEvidence implies r.outcomes == List()))

  // Independent change-chain validation catches omitted increments and spurious bumps.
  // 从初始判断连续折叠见证,并与实际当前投影比对;见证不作守卫,漏记变化仍会被检出.
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
