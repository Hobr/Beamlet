// Beamlet core Safety entry point. SQL commits remain atomic; transport and effects are separate.
module beamletCore {
  import coreActionsEvidence.* from "./actions/evidence"
  export coreActionsEvidence.*
  import coreActionsLeases.* from "./actions/leases"
  export coreActionsLeases.*
  import coreActionsReconciliation.* from "./actions/reconciliation"
  export coreActionsReconciliation.*
  import coreActionsRecovery.* from "./actions/recovery"
  export coreActionsRecovery.*
  import coreActionsWorkers.* from "./actions/workers"
  export coreActionsWorkers.*
  import corePropertiesCommands.* from "./properties/commands"
  export corePropertiesCommands.*
  import corePropertiesCore.* from "./properties/core"
  export corePropertiesCore.*
  import corePropertiesReconciliation.* from "./properties/reconciliation"
  export corePropertiesReconciliation.*
  import corePropertiesWitnesses.* from "./properties/witnesses"
  export corePropertiesWitnesses.*

  action stepWithReconciliation(p: ReconciliationPolicy): bool =
    any { step, proposeAnyReconciliation(p) }

  action stepWithCommands(p: ReconciliationPolicy): bool =
    any { step, proposeAnyCommand, receiveAnyReconciliationCommand(p), resendCommittedCommand }

  val safety = outcomeUnique and closedIffOutcome and outcomeImmutable
    and startupsQualified and oneStartPerExecution and expirySticky
    and invocationsAuthorized and oneCallPerExecution and commitsQualified and outcomeAuditAtomic
    and replacementsSafe and notExecutedProofSound
    and receiptsOnlyForStored and reportAuditAtomic and resolvedKnowledgeCoherent
    and grantsPersist and knowledgeEvidenced and reportsAuthenticated and commitSnapshotsMatch
    and failureRespectsOldSuccess and reconciliationQualified
    and reconciledEvidencePreserved and reconciliationAuditAtomic
    and conflictCoverageSound and conflictHistoryPreserved and terminalConflictsResolved
    and excludedAllKnowledgeSound and allExcludedCommitSound
    and supersessionLinksSound and dispositionBindingsUnique and decisionsImmutable

  val commandSafety = safety and judgmentRevisionSound and commandRecordsUnique and commandRecordsImmutable
    and commandExecutionMatchesRequest and commandEffectsAtomic
    and commandResultsOriginal and commandRepliesSound and commandHandlingSound
    and rejectedCommandsImmutable and rejectionQualified and rejectionEffectsAtomic and commandReadAuthorized

  action step = {
    nondet e = EXECUTIONS.oneOf()
    nondet dst = EXECUTIONS.oneOf()
    nondet w = WORKERS.oneOf()
    nondet id = REPORT_IDS.oneOf()
    nondet kind = Set(Success, Failure).oneOf()
    val tokens = knownTokens(workers, network)
    val fallback: Token = { exec: e, worker: w, incarnation: workers.get(w).incarnation, generation: 1 }
    nondet t = (if (tokens.size() > 0) tokens else Set(fallback)).oneOf()
    any {
      createExecution(e), claimExecution(e, w), moveClock, expireLease(e),
      completeAtResource(e, kind), receiveAnyReport, cancelIntent, finishFailure(e),
      replaceExecution(e, dst), queryExternal(e, id), fenceAtResource(e, id),
      requestStart(t), authorizeStart(t), receiveGrant(t), resendGrant(t), renewLease(t),
      callExternal(t), publishPending(t), publishCompletion(t),
      crashWorker(w), restartWorker(w), crashCoordinator, restartCoordinator,
      loseAnyMessage, discardDuplicateGrant(t), discardOldGrant(t),
      receiveAnyReceipt, acknowledgeAnyDuplicate, resendAnyReport,
    }
  }
}

module singleWorker {
  import beamletCore(WORKERS = Set(1), EXECUTIONS = Set(1), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).*
}
module beamletCoreAnalysis {
  import beamletCore(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).*
}
module repeatAllowed {
  import beamletCore(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = true, CAN_FENCE = false).*
}
module fenced {
  import beamletCore(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = true).*
}
