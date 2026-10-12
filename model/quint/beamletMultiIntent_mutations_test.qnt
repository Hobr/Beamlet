module multiCrossIntentReport {
  import multiIntentMutations(BUG = 1, INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/multi"
}
module multiCrossIntentGrant {
  import multiIntentMutations(BUG = 2, INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/multi"
}
module multiSharedIdempotencyContext {
  import multiIntentMutations(BUG = 3, INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/multi"
}
module multiSiblingHistoryErased {
  import multiIntentMutations(BUG = 4, INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/multi"
}
module multiPrematureToolJoin {
  import multiIntentMutations(BUG = 5, INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/multi"
}
module multiJoinByNotificationCount {
  import multiIntentMutations(BUG = 6, INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/multi"
}
module multiCallbackCorrelationCollision {
  import multiIntentMutations(BUG = 7, INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/multi"
}
module multiLostDependencyManifest {
  import multiIntentMutations(BUG = 8, INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/multi"
}
