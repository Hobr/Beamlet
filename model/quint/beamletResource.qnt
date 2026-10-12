module resourceAnalysis {
  import resourceProtocol(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false) as model from "./contracts/resource"
  action init = model::resourceInit
  action boundInit = model::resourceBoundInit
  action alternateInit = model::resourceAlternateInit
  action step = model::resourceStep
  action healthyStep = model::resourceHealthyStep
  val safety = model::resourceSafety
  val boundWitness = model::boundWitness
  val calledWitness = model::resourceCalledWitness
  val changedWitness = model::changedWitness
  val migratedWorkerWitness = model::migratedWorkerWitness
  val completedWitness = model::resourceCompletedWitness
}
