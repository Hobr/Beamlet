// Stable conflict test and mutation entry points; simulation imports only the fixture.
module conflictScenarios {
  import conflictCoverageTests.* from "./scenarios/conflicts/coverage_test"
  export conflictCoverageTests.*
  import conflictAllExcludedTests.* from "./scenarios/conflicts/all_excluded_test"
  export conflictAllExcludedTests.*
  import conflictSupersessionTests.* from "./scenarios/conflicts/supersession_test"
  export conflictSupersessionTests.*
  import conflictWithdrawalTests.* from "./scenarios/conflicts/withdrawal_test"
  export conflictWithdrawalTests.*
  import conflictMutations.* from "./mutations/conflicts"
  export conflictMutations.*
}

module conflictTests { import conflictScenarios(BUG = 0, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).* }

module incompleteConflictCoverage {
  import conflictScenarios(BUG = 1, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}

module uncheckedConflictBasis {
  import conflictScenarios(BUG = 2, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}

module erasedConflictHistory {
  import conflictScenarios(BUG = 3, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}

module terminalBeforeConflictResolution {
  import conflictScenarios(BUG = 4, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}

module permanentConflictDisposition {
  import conflictScenarios(BUG = 5, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}

module earlyConflictReply {
  import conflictScenarios(BUG = 6, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}

module excludedAllUsesCachedKnowledge {
  import conflictScenarios(BUG = 8, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}

module excludedAllCreatesOutcome {
  import conflictScenarios(BUG = 9, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}

module implicitSupersession {
  import conflictScenarios(BUG = 10, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}
module wrongSupersessionTarget {
  import conflictScenarios(BUG = 11, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}
module overbroadSupersession {
  import conflictScenarios(BUG = 12, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}
module supersessionRewritesOldDecision {
  import conflictScenarios(BUG = 13, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}
module supersessionLinksNotCommitted {
  import conflictScenarios(BUG = 14, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}

module deletedConflictReport {
  import conflictScenarios(BUG = 7, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
  run mutationCaughtTest = mutantInit.expect(conflictSafety)
    .then(mutantStep).expect(not(mutantInvariant) and not(conflictSafety))
}
