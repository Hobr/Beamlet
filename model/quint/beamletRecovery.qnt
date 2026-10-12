// Random crash/recovery composition over the independent normal-use model.
module recoveryAnalysis {
  import normalRecoveryActions(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false) as scenario from "./normal/recovery"
  action init = scenario::normalInit
  action step = scenario::recoveryStep
  action callbackRunningInit = scenario::callbackRunningInit
  action callbackReleasedInit = scenario::callbackReleasedInit
  action retryPendingInit = scenario::retryPendingInit
  action retryAuthorizedInit = scenario::retryAuthorizedInit
  val safety = scenario::normalSafety
  val callbackRedeliveryWitness = scenario::callbackRedeliveryWitness
  val recoveryCompletionWitness = scenario::recoveryCompletionWitness
  val policyStopWitness = scenario::policyStopWitness
  val succeededReached = scenario::succeededReached
  val failedReached = scenario::failedReached
  val workerRestartReached = scenario::workerRestartReached
  val coordinatorRestartReached = scenario::coordinatorRestartReached
  val messageLossReached = scenario::messageLossReached
  val expiryReached = scenario::expiryReached
  val clockBackwardReached = scenario::clockBackwardReached
  val retryWitness = scenario::retryWitness
}
