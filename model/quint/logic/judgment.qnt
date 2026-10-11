// Conservative judgment projection and revision bookkeeping.
module coreLogicJudgment {
  import coreBaseState.* from "../base/state"
  export coreBaseState.*

  // Conservative model projection, not an approved SQL field list.
  // Temporary lease controls, transport, pure rejection audit, and command caches are excluded.
  pure def judgmentBase(l: Ledger): JudgmentBase = {
    phase: l.phase, current: l.current, reports: l.reports,
    attempts: EXECUTIONS.mapBy(e => {
      val a = l.attempts.get(e)
      { exists: a.exists, phase: a.phase, grant: a.grant, knowledge: a.knowledge, conflict: a.conflict }
    }),
  }

  pure def judgmentView(l: Ledger): JudgmentView = {
    base: judgmentBase(l), decisions: l.decisions.foldl(List(), (ds, w) => ds.append(w.decision)),
  }

  pure def advanceJudgment(before: Ledger, after: Ledger): Ledger = {
    val oldView = judgmentView(before)
    val newView = judgmentView(after)
    if (oldView == newView) after
    else {
      val change: JudgmentChange = {
        before: oldView, after: newView, previous: before.revision, next: before.revision + 1,
      }
      { ...after, revision: change.next, judgmentChanges: before.judgmentChanges.append(change) }
    }
  }
}
