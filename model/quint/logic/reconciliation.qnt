// Authority-checked decision qualification and durable reconciliation.
module coreLogicReconciliation {
  import coreLogicRules.* from "./rules"
  export coreLogicRules.*

  // 只在构造新提案时捕获当前 revision/取代引用;接收时不能替调用者刷新请求.
  pure def proposeDecision(l: Ledger, r: Report, kind: DecisionKind, actor: DecisionActor): Decision = withSupersessions(l, {
    kind: kind, report: r, actor: actor,
    basis: if (kind == AdoptSuccess or kind == AdoptFailure) VerifiedCompletion else ContractExclusion,
    reviewedRevision: l.revision, evidence: Set(), supersedes: Set(),
  })

  pure def decisionActorQualified(p: ReconciliationPolicy, d: Decision): bool = match d.actor {
    | Operator(id) => p.operators.contains(id)
    | AutomaticRule(_) => registeredRuleQualified(p.registeredRules, d)
  }

  // policy 是 Authority 已核验的主体/契约事实;集合成员关系抽象核验成立,不证明真实依据.
  pure def decisionContractQualified(p: ReconciliationPolicy, d: Decision): bool =
    if (d.kind == WithdrawDisposition) d.basis == VerifiedWithdrawal
      and p.withdrawals.contains(d.supersedes)
    else if (d.kind == AdoptSuccess) d.report.kind == Success and d.basis == VerifiedCompletion
    else if (d.kind == AdoptFailure) d.report.kind == Failure and d.basis == VerifiedCompletion
    else if (d.kind == ExcludeAllEvidence) d.basis == ContractExclusion and d.evidence.size() > 0
      and d.evidence.forall(i => i.treatment == ExcludeEvidence)
    else d.report.kind == Success and d.basis == ContractExclusion and p.excludable.contains(d.report)

  // 冲突处置保守覆盖全部历史冲突尝试的已存报告及主报告,每份恰好一项处置.
  // 撤销只移除明确范围,不负责解除冲突,因此不要求覆盖其他冲突报告.
  pure def decisionCoverageQualified(l: Ledger, d: Decision): bool = {
    val required = conflictReports(l)
    if (d.kind == WithdrawDisposition) d.evidence.size() == 0
      and decisionAffectedReports(d).forall(r => l.reports.contains(r) and reportSourceValid(l, r))
    else if (d.evidence.size() == 0) required.size() == 0
    else evidenceReports(d) == required.union(Set(d.report))
      and evidenceReports(d).size() == d.evidence.size()
      and d.evidence.forall(i => l.reports.contains(i.report) and reportSourceValid(l, i.report))
      and d.evidence.exists(i => i.report == d.report
        and i.treatment == (if (decisionIsTerminal(d)) KeepEvidence else ExcludeEvidence))
  }

  // 除整体契约输入外还独立检查逐项依据与保留证据的一致性,防止相互矛盾的结果同时被采用.
  pure def decisionEvidenceQualified(p: ReconciliationPolicy, d: Decision): bool =
    if (d.kind == WithdrawDisposition) d.evidence.size() == 0
    else if (d.evidence.size() == 0) d.kind != AdoptFailure and d.kind != ExcludeAllEvidence
    else p.resolutions.contains(d.evidence)
      and d.evidence.forall(i => i.basis ==
        (if (i.treatment == KeepEvidence) VerifiedCompletion else ContractExclusion))
      and d.evidence.forall(i => d.evidence.forall(j =>
        (i.report.exec == j.report.exec and i.treatment == KeepEvidence and j.treatment == KeepEvidence)
          implies (not(sameReportIdentity(i.report, j.report)) or i.report == j.report)
            and not((i.report.kind == Success and (j.report.kind == Failure or j.report.kind == NotExecuted))
              or (j.report.kind == Success and (i.report.kind == Failure or i.report.kind == NotExecuted))
              or (i.report.kind == j.report.kind and (i.report.kind == Success or i.report.kind == Failure)
                and i.report.value != j.report.value))))

      // All decisive reports may be excluded; judgmentKnowledge then remains unknown.

  pure def decisionOutcome(d: Decision): Outcome = {
    kind: if (d.kind == AdoptFailure) OutcomeFailed else OutcomeSucceeded,
    exec: Current(d.report.exec), value: d.report.value,
  }

  // 按处理当刻重验版本,主体,契约,覆盖和取代目标;终结提案还检查处置后的结果资格.
  pure def canReconcile(l: Ledger, p: ReconciliationPolicy, d: Decision): bool =
    l.phase == Open and decisionScopeCurrent(l, d)
      and l.reports.contains(d.report) and reportSourceValid(l, d.report)
      and (d.kind == WithdrawDisposition or l.current != Current(d.report.exec) or d.evidence.size() > 0)
      and decisionActorQualified(p, d) and decisionContractQualified(p, d)
      and decisionCoverageQualified(l, d) and decisionEvidenceQualified(p, d)
      and decisionSupersessionsQualified(l, d)
      and (not(decisionIsTerminal(d)) or canCommit(applyReconcile(l, p, d), decisionOutcome(d)))
      and (d.kind == WithdrawDisposition or l.decisions.select(w => dispositionScopeCurrent(l, w)
        and decisionTreatments(w.decision).forall(i => applicableBindings(l).exists(b =>
          b.item == i and l.decisions.nth(b.decisionIndex) == w))
        and w.decision.kind == d.kind and w.decision.report == d.report
        and w.decision.actor == d.actor and w.decision.basis == d.basis
        and w.decision.evidence == d.evidence).length() == 0)

  pure def applyReconcile(l: Ledger, p: ReconciliationPolicy, d: Decision): Ledger = {
    val w: DecisionWitness = {
      decision: d, acceptedCurrent: l.current, acceptedReports: l.reports,
      acceptedRevision: l.revision, acceptedBase: judgmentBase(l),
      openAtDecision: l.phase == Open,
      actorQualified: decisionActorQualified(p, d),
      contractQualified: decisionContractQualified(p, d),
      coverageQualified: decisionCoverageQualified(l, d), evidenceQualified: decisionEvidenceQualified(p, d),
      supersessionQualified: decisionSupersessionsQualified(l, d), rulesAtDecision: p.registeredRules,
      bindingsBefore: historicalBindings(l.decisions), withdrawalsAtDecision: p.withdrawals,
    }
    val updated = { ...l, decisions: l.decisions.append(w), decisionSnapshots: l.decisionSnapshots.append(d),
      history: l.history.append({ kind: EvidenceReconciled, exec: Current(d.report.exec) }) }
    advanceJudgment(l, updated)
  }

  // 采用结果时决定与终结在一次提交中完成;排除/撤销只改变判断,不制造 Outcome.
  pure def applyReconcileAndMaybeCommit(l: Ledger, p: ReconciliationPolicy, d: Decision): Ledger = {
    val recorded = applyReconcile(l, p, d)
    if (decisionIsTerminal(d))
      applyCommit(recorded, decisionOutcome(d))
    else recorded
  }
}
