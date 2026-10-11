module retirementClearsDisposition {
  import ruleRetirementMutations(RETIREMENT_BUG = 1, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2),
    REPORT_IDS = Set(1, 2, 3, 4), CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2,
    MAX_GENERATION = 3, TTL = 2, ALLOW_REPEAT = true, CAN_FENCE = false).*
    from "./mutations/retirement"
}

module retirementBumpsJudgmentRevision {
  import ruleRetirementMutations(RETIREMENT_BUG = 2, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2),
    REPORT_IDS = Set(1, 2, 3, 4), CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2,
    MAX_GENERATION = 3, TTL = 2, ALLOW_REPEAT = true, CAN_FENCE = false).*
    from "./mutations/retirement"
}

module ruleVersionIgnored {
  import ruleVersionMutations(RULE_BUG = 1, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2),
    REPORT_IDS = Set(1, 2, 3, 4), CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2,
    MAX_GENERATION = 3, TTL = 2, ALLOW_REPEAT = true, CAN_FENCE = false).*
    from "./mutations/rules"
}

module ruleConditionsFromOtherVersion {
  import ruleVersionMutations(RULE_BUG = 2, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2),
    REPORT_IDS = Set(1, 2, 3, 4), CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2,
    MAX_GENERATION = 3, TTL = 2, ALLOW_REPEAT = true, CAN_FENCE = false).*
    from "./mutations/rules"
}

module automaticRequestVersionRefreshed {
  import ruleVersionMutations(RULE_BUG = 3, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2),
    REPORT_IDS = Set(1, 2, 3, 4), CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2,
    MAX_GENERATION = 3, TTL = 2, ALLOW_REPEAT = true, CAN_FENCE = false).*
    from "./mutations/rules"
}

module historicalRuleReinterpreted {
  import ruleVersionMutations(RULE_BUG = 4, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2),
    REPORT_IDS = Set(1, 2, 3, 4), CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2,
    MAX_GENERATION = 3, TTL = 2, ALLOW_REPEAT = true, CAN_FENCE = false).*
    from "./mutations/rules"
}

module replayBlockedByRuleRetirement {
  import ruleVersionMutations(RULE_BUG = 5, WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2),
    REPORT_IDS = Set(1, 2, 3, 4), CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2,
    MAX_GENERATION = 3, TTL = 2, ALLOW_REPEAT = true, CAN_FENCE = false).*
    from "./mutations/rules"
}
