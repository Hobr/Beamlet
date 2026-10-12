// Reference-model adapters: shared execution rules plus judgment revision bookkeeping.
module coreLogicReports {
  import coreLogicJudgment.* from "./judgment"
  export coreLogicJudgment.*
  import executionReportLogic as shared from "./execution_reports"

  pure def reportSourceValid(l: Ledger, r: Report): bool =
    shared::reportSourceValid(l, r)

  pure def sameReportIdentity(a: Report, b: Report): bool =
    shared::sameReportIdentity(a, b)

  pure def reportConflicts(l: Ledger, r: Report): bool =
    shared::reportConflicts(l, r)

  pure def knowledgeOf(kind: ReportKind): Knowledge =
    shared::knowledgeOf(kind)

  pure def applyReport(l: Ledger, r: Report): Ledger =
    advanceJudgment(l, shared::applyReport(l, r))
}
