// Report authentication, conflict detection and durable evidence projection.
module coreLogicReports {
  import coreLogicJudgment.* from "./judgment"
  export coreLogicJudgment.*

  // 报告资格使用持久 grant 关联,不要求当前租约有效;旧 Worker 报告仍可作为历史证据.
  // ByQuery 抽象已通过受信入口核验的来源,不验证真实认证或外部正文真实性.
  pure def reportSourceValid(l: Ledger, r: Report): bool = {
    val attempt = l.attempts.get(r.exec)
    val originValid = match r.origin {
      | ByWorker(t) => t.exec == r.exec and attempt.grant == StartGrant(t)
          and (r.kind == Pending or r.kind == Success or r.kind == Failure)
      | ByQuery => r.kind != Pending
      | ByCallback(c) => attempt.grant != NoGrant and attempt.completion == CallbackBinding(c)
          and (r.kind == Success or r.kind == Failure)
    }
    attempt.exists and originValid
  }

  // 去重身份包含来源作用域;同一身份不同内容是冲突,而不是覆盖旧报告.
  pure def sameReportIdentity(a: Report, b: Report): bool =
    a.id == b.id and a.exec == b.exec and a.origin == b.origin

  pure def reportConflicts(l: Ledger, r: Report): bool = {
    val known = l.attempts.get(r.exec).knowledge
    val identityConflict = l.reports.exists(old => sameReportIdentity(old, r) and old != r)
    val resultConflict = (known == SuccessKnown and (r.kind == Failure or r.kind == NotExecuted))
      or (known == FailureKnown and r.kind == Success)
      or (known == NotExecutedKnown and r.kind == Success)
    val valueConflict = l.reports.exists(old => old.exec == r.exec and old.kind == r.kind
      and (r.kind == Success or r.kind == Failure) and old.value != r.value)
    identityConflict or resultConflict or valueConflict
  }

  // Pending/NotFound 都不提供确定结果;只有可靠的 NotExecuted 才证明未执行.
  pure def knowledgeOf(kind: ReportKind): Knowledge =
    if (kind == Success) SuccessKnown
    else if (kind == Failure) FailureKnown
    else if (kind == NotExecuted) NotExecutedKnown
    else NoKnowledge

  // 原始证据只增不删.冲突标志保持,同时保留最近有依据的生命周期与 Knowledge.
  // 迟到 Pending 不把 Resolved 回退为 Waiting,NotFound 只设置 negativeSeen.
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
