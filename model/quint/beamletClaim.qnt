module claimAnalysis {
  import claimProtocol(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false) as model from "./contracts/claim"
  action init = model::claimInit
  action lostInit = model::claimLostInit
  action step = model::claimStep
  action healthyStep = model::claimHealthyStep
  val safety = model::claimSafety
  val allocatedWitness = model::allocatedWitness
  val replayWitness = model::replayWitness
  val deliveredWitness = model::deliveredWitness
  val calledWitness = model::calledWitness
}
