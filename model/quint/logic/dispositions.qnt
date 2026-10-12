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

  // 检查本次判断是否仍受冲突阻塞;解除阻塞不清除历史 conflict 标志或矛盾原报告.
  pure def noConflicts(l: Ledger): bool =
    EXECUTIONS.forall(e => not(l.attempts.get(e).conflict) or conflictResolved(l, e))

  // 撤销产生空处置集;旧式无 evidence 决定仍按主报告解释,兼容早期协调场景.
  pure def decisionTreatments(d: Decision): Set[EvidenceDisposition] =
    if (d.kind == WithdrawDisposition) Set()
    else if (d.evidence.size() > 0) d.evidence
    else Set({ report: d.report,
      treatment: if (decisionIsTerminal(d)) KeepEvidence else ExcludeEvidence, basis: d.basis })

  pure def decisionAffectedReports(d: Decision): Set[Report] =
    if (d.kind == WithdrawDisposition) d.supersedes.fold(Set(), (rs, s) => rs.union(s.reports))
    else decisionTreatments(d).map(i => i.report)

  // 只删除显式引用的"决定 + 报告"绑定,再加入新处置;撤销只删除,不恢复更早的绑定.
  pure def advanceBindings(bindings: Set[DispositionBinding], d: Decision, index: int): Set[DispositionBinding] =
    bindings.filter(b => not(d.supersedes.exists(s =>
      s.decisionIndex == b.decisionIndex and s.reports.contains(b.item.report))))
      .union(decisionTreatments(d).map(i => { decisionIndex: index, item: i }))

  // 按显式边折叠得到历史链的当前所有者;这不规定产品必须靠事件重放恢复状态.
  pure def historicalBindings(ds: List[DecisionWitness]): Set[DispositionBinding] = {
    val folded = ds.foldl({ bindings: Set(), index: 0 }, (s, w) =>
      { bindings: advanceBindings(s.bindings, w.decision, s.index), index: s.index + 1 })
    folded.bindings
  }

  // 历史所有权与当前适用性分开:新证据可使处置暂不适用,但不删除它的取代关系.
  pure def applicableBindings(l: Ledger): Set[DispositionBinding] =
    historicalBindings(l.decisions).filter(b => dispositionScopeCurrent(l, l.decisions.nth(b.decisionIndex)))

  // 对已处置报告引用历史链上当前所有者,即使其处置已因新证据不再适用,也不能跳过.
  pure def requiredSupersessions(l: Ledger, d: Decision): Set[Supersession] = {
    val bindings = historicalBindings(l.decisions)
    val reports = decisionAffectedReports(d)
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
      and (d.kind != WithdrawDisposition or (d.supersedes.size() > 0
        and decisionAffectedReports(d).contains(d.report)
        and decisionAffectedReports(d).forall(r => applicableBindings(l).exists(b => b.item.report == r))))

  pure def judgmentItems(l: Ledger): Set[EvidenceDisposition] =
    applicableBindings(l).filter(b => l.decisions.nth(b.decisionIndex).decision.evidence.size() > 0)
      .map(b => b.item)

  // 逐报告处置只改变当前判断;全部排除后返回未知,不能退回缓存的原 Knowledge.
  pure def judgmentKnowledge(l: Ledger, e: int): Knowledge = {
    val classified = judgmentItems(l).filter(i => i.report.exec == e)
    val kept = classified.filter(i => i.treatment == KeepEvidence).map(i => i.report)
    if (kept.exists(r => r.kind == Success)) SuccessKnown
    else if (kept.exists(r => r.kind == Failure)) FailureKnown
    else if (kept.exists(r => r.kind == NotExecuted)) NotExecutedKnown
    else if (classified.size() > 0) NoKnowledge
    else l.attempts.get(e).knowledge
  }

  // 已授权且没有确定判断的尝试仍可能执行;全部排除证据也不会消除该风险.
  pure def noUnresolvedRisk(l: Ledger): bool = EXECUTIONS.forall(e => {
    val attempt = l.attempts.get(e)
    not(attempt.exists) or attempt.grant == NoGrant or judgmentKnowledge(l, e) != NoKnowledge
  })

  pure def hasEvidence(l: Ledger, e: int, kind: ReportKind): bool =
    l.reports.exists(r => r.exec == e and r.kind == kind and reportSourceValid(l, r)
      and not(excludedForJudgment(l, r)))

  pure def hasOutcomeEvidence(l: Ledger, e: int, kind: ReportKind, value: int): bool =
    l.reports.exists(r => r.exec == e and r.kind == kind and r.value == value
      and reportSourceValid(l, r) and not(excludedForJudgment(l, r)))

  pure def knownResultValue(l: Ledger, e: int, kind: ReportKind): int =
    l.reports.filter(r => r.exec == e and r.kind == kind and not(excludedForJudgment(l, r)))
      .fold(0, (_, r) => r.value)

  // 新请求必须匹配审查 revision;已接受处置按 acceptedBase 判断范围,避免被自身增版失效.
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
