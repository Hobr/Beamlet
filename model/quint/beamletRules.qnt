// Version coexistence/retirement simulation; only the unbound shared fixture is imported.
module beamletRules {
  import repeatingRuleFixtures(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2),
    REPORT_IDS = Set(1, 2, 3, 4), CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2,
    MAX_GENERATION = 3, TTL = 2, ALLOW_REPEAT = true, CAN_FENCE = false) as scenario
    from "./scenarios/repeating/rules_fixtures"

  action automaticRulePendingInit = scenario::automaticRulePendingInit
  action automaticRuleCommittedInit = scenario::automaticRuleCommittedInit
  action retiredRuleRejectedInit = scenario::retiredRuleRejectedInit
  action ruleVersionStep = scenario::ruleVersionStep
  val commandSafety = scenario::commandSafety
  val pinnedV1Witness = scenario::pinnedV1Witness
  val pinnedV2Witness = scenario::pinnedV2Witness
  val commandReplayReached = scenario::commandReplayReached
  val rejectedCommandStoredReached = scenario::rejectedCommandStoredReached
  action init = automaticRulePendingInit
  action step = ruleVersionStep
  val safety = commandSafety
}
