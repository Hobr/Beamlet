module continuationSendBeforeCommit {
  import continuationMutations(BUG = 1, INTENTS = Set(1, 2, 3), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/continuation"
}

module continuationReplayChangesKey {
  import continuationMutations(BUG = 2, INTENTS = Set(1, 2, 3), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/continuation"
}

module continuationLostDecision {
  import continuationMutations(BUG = 3, INTENTS = Set(1, 2, 3), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/continuation"
}

module continuationConsumesWrongIntent {
  import continuationMutations(BUG = 4, INTENTS = Set(1, 2, 3), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/continuation"
}

module continuationLaterResultReplacesDecision {
  import continuationMutations(BUG = 5, INTENTS = Set(1, 2, 3), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/continuation"
}

module continuationReplayChangesDefinition {
  import continuationMutations(BUG = 6, INTENTS = Set(1, 2, 3), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./mutations/continuation"
}
