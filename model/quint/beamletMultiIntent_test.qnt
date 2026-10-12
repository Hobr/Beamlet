module multiIntentTests {
  import multiIntentAdditionalTests(INTENTS = Set(1, 2), AGENTS = Set(1, 2), CALLS = Set(1, 2),
    WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./scenarios/multi/additional_test"
}
