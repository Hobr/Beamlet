module tripleAnalysis {
  import tripleProtocol(INTENTS = Set(1, 2, 3), AGENTS = Set(1), CALLS = Set(1),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false) as model from "./contracts/triple"
  action init = model::tripleInit
  action restartedInit = model::tripleRestartedInit
  action step = model::tripleStep
  action healthyStep = model::tripleHealthyStep
  val safety = model::tripleSafety
  val invokedWitness = model::threeInvokedWitness
  val twoCompletedWitness = model::twoCompletedWitness
  val recoveredReadWitness = model::recoveredTripleReadWitness
  val joinedWitness = model::tripleJoinedWitness
}
