module historyState {
  import beamletExecution.* from "../beamletExecution"
  export beamletExecution.*
  type HistoryCommand = HistoryCreate | HistoryClaim | HistoryAuthorize | HistoryReport(Report)
  type HistoryDraft = NoHistoryDraft | HistoryDrafted({ base: Ledger, updated: Ledger,
    command: HistoryCommand, at: int })
  type HistoryGroup = { sequence: int, actor: int, at: int, version: int,
    command: HistoryCommand, before: Ledger, after: Ledger, events: List[Audit] }
  type HistoryStore = { groups: List[HistoryGroup], committed: List[HistoryGroup],
    rollbacks: int, duplicateReads: int }
  var historyStore: HistoryStore
  var historyDrafts: int -> HistoryDraft
  action historyInit = all { init, historyStore' = {
    groups: List(), committed: List(), rollbacks: 0, duplicateReads: 0 },
    historyDrafts' = Set(1, 2).mapBy(_ => NoHistoryDraft) }
  action holdHistory = all { historyStore' = historyStore, historyDrafts' = historyDrafts }
}
