// Three Intents, two caller manifests and one durable partial-result decision.
module continuationAnalysis {
  import continuationProfiles(INTENTS = Set(1, 2, 3), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false) as scenario from "./continuation/profiles"
  action init = scenario::progressInit
  action partialInit = scenario::partialProgressInit
  action decidedInit = scenario::decidedProgressInit
  action submittedInit = scenario::submittedProgressInit
  action closedInit = scenario::closedProgressInit
  action step = scenario::continuationStep
  action healthyStep = scenario::continuationHealthyStep
  val safety = scenario::continuationSafety
  val decisionWitness = scenario::decisionWitness
  val partialDecisionWitness = scenario::partialDecisionWitness
  val manifestWitness = scenario::manifestWitness
  val partialSubmissionWitness = scenario::partialSubmissionWitness
  val successorSubmittedWitness = scenario::successorSubmittedWitness
  val recoveredManifestWitness = scenario::recoveredManifestWitness
  val recoveredReadWitness = scenario::recoveredReadWitness
  val recoveredSuccessorWitness = scenario::recoveredSuccessorWitness
  val successorCompletedWitness = scenario::successorCompletedWitness
}
