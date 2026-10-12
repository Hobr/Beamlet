// Stable concrete test entry points. Bind core constants only here (Quint 0.32 re-export limitation).

// 场景共享未绑定 fixture 中的同一份状态;then 串联真实转换,expect 在各窗口检查 safety.
// 从根入口用 quint test --main strictTests / fencedTests / repeatingTests 选择对应风险前提.
module fencedTests {
  import fencedScenarios(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = true).* from "./scenarios/fenced/scenarios"
}

module strictTests {
  import strictScenarios(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).* from "./scenarios/strict/scenarios"
}

module repeatingTests {
  import repeatingScenarios(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).* from "./scenarios/repeating/scenarios"
}
