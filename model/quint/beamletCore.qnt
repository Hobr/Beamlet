// Beamlet core Safety entry point. SQL commits remain atomic; transport and effects are separate.
// 阅读路径:base 定义状态 -> logic 定义守卫/纯更新 -> actions 定义转换 -> properties 检查独立见证.
// SQL 提交抽象为单步原子转换;不包含公平调度,最终交付或最终终结的活性保证.
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
  import corePropertiesWithdrawal.* from "./properties/withdrawal"
  export corePropertiesWithdrawal.*
  import corePropertiesWitnesses.* from "./properties/witnesses"
  export corePropertiesWitnesses.*

  // 直接验证协调领域原语;需要覆盖请求延迟,去重和读取权限时使用 stepWithCommands.
  action stepWithReconciliation(p: ReconciliationPolicy): bool =
    any { step, proposeAnyReconciliation(p) }

  action stepWithCommands(p: ReconciliationPolicy): bool =
    any { step, proposeAnyCommand, receiveAnyReconciliationCommand(p), resendCommittedCommand }

  // Safety 是每个可达状态都应满足的合取;历史资格用提交时快照检查,避免以当前状态误判过去.
  val safety = outcomeUnique and closedIffOutcome and outcomeImmutable and outcomeValuesEvidenced
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
    and automaticRuleVersionsSound and ordinaryRuleRetirementSound
    and withdrawalScopeSound and withdrawalCommandsNonterminal

  // 命令入口使用更强的合取,额外检查原请求/原结果,领域拒绝,重投与判断版本.
  val commandSafety = safety and judgmentRevisionSound and commandRecordsUnique and commandRecordsImmutable
    and commandExecutionMatchesRequest and commandEffectsAtomic
    and commandResultsOriginal and commandRepliesSound and commandHandlingSound
    and rejectedCommandsImmutable and rejectionQualified and rejectionEffectsAtomic and commandReadAuthorized

  // 每步非确定选择一个可执行动作,显式拆开许可,调用,完成,报告和保存的竞态窗口.
  // 不导入 mutations;故意错误规则只能从专用反例入口运行.
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

// 常量只在最外层绑定一次:Quint 0.32 中已绑定 fixture 再跨层导出可能出现 Uninitialized const.
// 以下实例分别覆盖单 Worker,禁止重复,接受重复风险和可信资源排除四种前提.
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
