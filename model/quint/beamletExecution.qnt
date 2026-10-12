// First-release execution core; governance remains in beamletCore as a composition reference.
module beamletExecution {
  import executionActionsEvidence.* from "./actions/execution_evidence"
  export executionActionsEvidence.*
  import executionActionsLeases.* from "./actions/execution_leases"
  export executionActionsLeases.*
  import executionActionsRecovery.* from "./actions/execution_recovery"
  export executionActionsRecovery.*
  import executionActionsWorkers.* from "./actions/execution_workers"
  export executionActionsWorkers.*
  import executionProperties.* from "./properties/execution"
  export executionProperties.*
  import executionWitnesses.* from "./properties/execution_witnesses"
  export executionWitnesses.*

  val safety = outcomeUnique and closedIffOutcome and outcomeImmutable and outcomeValuesEvidenced
    and startupsQualified and oneStartPerExecution and expirySticky
    and invocationsAuthorized and oneCallPerExecution and commitsQualified and outcomeAuditAtomic
    and replacementsSafe and notExecutedProofSound and receiptsOnlyForStored and reportAuditAtomic
    and resolvedKnowledgeCoherent and grantsPersist and knowledgeEvidenced and reportsAuthenticated
    and commitSnapshotsMatch and failureRespectsOldSuccess and conflictHistoryPreserved and terminalConflictsResolved

  action step = {
    nondet e = EXECUTIONS.oneOf()
    nondet dst = EXECUTIONS.oneOf()
    nondet w = WORKERS.oneOf()
    nondet id = REPORT_IDS.oneOf()
    nondet kind = Set(Success, Failure).oneOf()
    val tokens = knownTokens(workers, network)
    // 空候选集时避免 oneOf() 无定义;fallback 仍须通过各动作守卫,不凭空授予许可.
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


module executionAnalysis {
  import beamletExecution(WORKERS = Set(1, 2), EXECUTIONS = Set(1, 2), REPORT_IDS = Set(1, 2, 3, 4),
    CLOCK_VALUES = 0.to(6), MAX_INCARNATION = 2, MAX_GENERATION = 3, TTL = 2,
    ALLOW_REPEAT = false, CAN_FENCE = false).*
}
