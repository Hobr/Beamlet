// Defensive simulation entry point: no test or mutation module is imported.
module beamletConflicts {
  import conflictFixtures(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false) as scenario from "./scenarios/conflicts/fixtures"

  action conflictInit = scenario::conflictInit
  action queriedConflictInit = scenario::queriedConflictInit
  action bothConflictsInit = scenario::bothConflictsInit
  action resolvedConflictInit = scenario::resolvedConflictInit
  action allExcludedInit = scenario::allExcludedInit
  action partiallySupersededInit = scenario::partiallySupersededInit
  action conflictStep = scenario::conflictStep
  val conflictSafety = scenario::conflictSafety
  val conflictDispositionWitness = scenario::conflictDispositionWitness
  val conflictSuccessWitness = scenario::conflictSuccessWitness
  val conflictFailureWitness = scenario::conflictFailureWitness
  val allExcludedWitness = scenario::allExcludedWitness
  val supersessionWitness = scenario::supersessionWitness

  action init = conflictInit
  action step = conflictStep
  val safety = conflictSafety
}
