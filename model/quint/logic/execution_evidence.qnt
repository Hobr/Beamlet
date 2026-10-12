// First-release evidence interpretation: raw conflicts and old successes keep blocking.
module executionEvidenceLogic {
  import executionState.* from "../base/execution_state"
  export executionState.*
  import executionReportLogic.* from "./execution_reports"
  export executionReportLogic.*

  pure def judgmentKnowledge(l: Ledger, e: int): Knowledge = l.attempts.get(e).knowledge
  pure def noConflicts(l: Ledger): bool = EXECUTIONS.forall(e => not(l.attempts.get(e).conflict))
  pure def noUnresolvedRisk(l: Ledger): bool = EXECUTIONS.forall(e => {
    val a = l.attempts.get(e)
    not(a.exists) or a.grant == NoGrant or a.knowledge != NoKnowledge
  })
  pure def hasEvidence(l: Ledger, e: int, kind: ReportKind): bool =
    l.reports.exists(r => r.exec == e and r.kind == kind and reportSourceValid(l, r))
  pure def hasOutcomeEvidence(l: Ledger, e: int, kind: ReportKind, value: int): bool =
    l.reports.exists(r => r.exec == e and r.kind == kind and r.value == value and reportSourceValid(l, r))
  pure def knownResultValue(l: Ledger, e: int, kind: ReportKind): int =
    l.reports.filter(r => r.exec == e and r.kind == kind).fold(0, (_, r) => r.value)
  pure def oldSuccessNeedsReconciliation(l: Ledger, e: int): bool =
    l.reports.exists(r => r.exec != e and r.kind == Success and reportSourceValid(l, r))
  pure def oldSuccessForOutcome(l: Ledger, o: Outcome): bool = match o.exec {
    | NoCurrent => false | Current(e) => oldSuccessNeedsReconciliation(l, e)
  }
}
