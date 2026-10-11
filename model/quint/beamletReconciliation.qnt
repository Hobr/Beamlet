// Bounded Q63/Q64 extension. Policy inputs represent authoritative, checked
// Operation facts; they are not parameters supplied by an untrusted command.
module beamletReconciliation {
  import beamletCore(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).* from "./beamletCore"

  pure val firstToken: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }
  pure val firstSuccess: Report = { id: 2, exec: 1, kind: Success, origin: ByWorker(firstToken) }
  // Checked-contract premise for this example, not proof of real irrelevance.
  pure val policy: ReconciliationPolicy = {
    operators: Set(1), registeredRules: Set(1, 2), excludable: Set(firstSuccess), resolutions: Set(),
  }

  action reconciliationStep = stepWithReconciliation(policy)
  action commandStep = stepWithCommands(policy)
}
