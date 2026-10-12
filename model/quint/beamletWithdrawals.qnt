// Q76 scoped withdrawal simulation. Normal entry imports only the unbound shared fixture.
module beamletWithdrawals {
  import conflictWithdrawalFixtures(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2),
    REPORT_IDS = Set(1, 2, 3, 4), CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2,
    MAX_GENERATION = 3, TTL = 2, ALLOW_REPEAT = true, CAN_FENCE = false) as scenario
    from "./scenarios/conflicts/withdrawal_fixtures"

  action init = scenario::withdrawalPendingInit
  action withdrawalPendingInit = scenario::withdrawalPendingInit
  action withdrawnInit = scenario::withdrawnInit
  action partiallyWithdrawnInit = scenario::partiallyWithdrawnInit
  action step = scenario::withdrawalStep
  val safety = scenario::commandSafety
  val withdrawalWitness = scenario::withdrawalWitness
  val renewedJudgmentWitness = scenario::renewedJudgmentWitness
  val commandReplayWitness = scenario::commandReplayReached
  val conflictFailureWitness = scenario::conflictFailureWitness
}
