// Terminal qualification and atomic outcome/evidence updates.
module executionOutcomeLogic {
  import executionEvidenceLogic.* from "./execution_evidence"
  export executionEvidenceLogic.*

  // Success/Failure 要求当前且证据合格;Failed 还须排除授权未知风险和未协调的旧成功.
  // 显式取消使用 NoCurrent,不依赖创建 Execution 或解决结果冲突.
  pure def ordinarySourceEligible(l: Ledger, o: Outcome): bool = match o.exec {
    | NoCurrent => o.kind == OutcomeCancelled and o.value == 0
    | Current(e) => l.current == Current(e) and noConflicts(l) and {
        if (o.kind == OutcomeSucceeded)
          judgmentKnowledge(l, e) == SuccessKnown and hasOutcomeEvidence(l, e, Success, o.value)
        else if (o.kind == OutcomeFailed)
          judgmentKnowledge(l, e) == FailureKnown and hasOutcomeEvidence(l, e, Failure, o.value)
            and noUnresolvedRisk(l) and not(oldSuccessNeedsReconciliation(l, e))
        else false
      }
  }

  pure def sourceEligible(l: Ledger, o: Outcome): bool = ordinarySourceEligible(l, o)

  pure def canCommit(l: Ledger, o: Outcome): bool =
    l.phase == Open and l.outcomes.length() == 0 and sourceEligible(l, o)

  // 调用方先核验 canCommit;Outcome,Closed,首结果见证和 History 由同一原子动作保存.
  pure def applyCommit(l: Ledger, o: Outcome): Ledger = {
    val witness: CommitWitness = {
      outcome: o, openAtCommit: l.phase == Open, sourceEligible: sourceEligible(l, o),
      oldSuccessAtCommit: oldSuccessForOutcome(l, o), conflictsAtCommit: not(noConflicts(l)),
    }
    val updated = { ...l, phase: Closed, outcomes: l.outcomes.append(o),
      firstOutcome: if (l.outcomes.length() == 0) List(o) else l.firstOutcome,
      commits: l.commits.append(witness),
      history: l.history.append({ kind: OutcomeStored, exec: o.exec }) }
    updated
  }

  // 普通合格成功随证据接收一起终结;失败仅存事实,是否停止尝试由独立 finishFailure 决定.
  pure def recordAndMaybeCommit(l: Ledger, r: Report): Ledger = {
    val recorded = applyReport(l, r)
    val outcome: Outcome = { kind: OutcomeSucceeded, value: r.value, exec: Current(r.exec) }
    if (r.kind == Success and canCommit(recorded, outcome)) applyCommit(recorded, outcome)
    else recorded
  }

  pure def isLate(l: Ledger, r: Report): bool =
    l.phase == Closed or l.current != Current(r.exec) or l.attempts.get(r.exec).lease.invalidated
}
