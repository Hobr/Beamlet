// Bounded composition; caller rounds are observations, not a Beamlet workflow engine.
module multiIntentAnalysis {
  import multiIntentProfiles(INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false) as scenario from "./multi/profiles"
  action init = scenario::independentInit
  action emptyInit = scenario::multiInit
  action independentInit = scenario::independentInit
  action joinedInit = scenario::joinedInit
  action bothRunningInit = scenario::bothRunningInit
  action releasedPairInit = scenario::releasedPairInit
  action unknownPairInit = scenario::unknownPairInit
  action retryPairInit = scenario::retryPairInit
  action step = scenario::multiStep
  action healthyStep = scenario::healthyMultiStep
  val safety = scenario::multiSafety
  val bothInvokedWitness = scenario::bothInvokedWitness
  val bothClosedWitness = scenario::bothClosedWitness
  val sharedWorkerWitness = scenario::sharedWorkerWitness
  val joinedWitness = scenario::joinedWitness
  val independentWitness = scenario::independentWitness
  val partialJoinWitness = scenario::partialJoinWitness
  val recoveredJoinWitness = scenario::recoveredJoinWitness
  val releasedCompletionWitness = scenario::multiReleasedCompletionWitness
  val unknownIsolationWitness = scenario::unknownIsolationWitness
}
