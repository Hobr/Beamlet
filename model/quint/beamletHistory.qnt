module historyAnalysis {
  import historyProtocol(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false) as model from "./contracts/history"
  action init = model::historyInit
  action runningInit = model::historyRunningInit
  action step = model::historyStep
  action healthyStep = model::historyHealthyStep
  val safety = model::historySafety
  val committedWitness = model::historyCommittedWitness
  val outcomeWitness = model::historyOutcomeWitness
  val rollbackWitness = model::historyRollbackWitness
  val duplicateWitness = model::historyDuplicateWitness
}
