// Intentionally broken reconciliation, command and revision rules.
module coreReconciliationMutations {
  import reconciliationMutationFixtures.* from "./reconciliation_fixtures"
  export reconciliationMutationFixtures.*

  action mutantInit =
    if (BUG >= 17) readyInit
    else if (BUG == 11) rejectedConditionPendingInit
    else if (BUG == 12) rejectedStalePendingInit
    else if (BUG == 13 or BUG == 14) replayPendingInit
    else if (BUG == 15 or BUG == 16) earlyReplyInit
    else if (BUG == 5) newEvidencePendingInit
    else if (BUG == 6 or BUG == 7) replayPendingInit
    else if (BUG == 8) laterFailurePendingInit
    else if (BUG == 9) earlyReplyInit
    else if (BUG == 10) staleReplayPendingInit
    else if (BUG == 4) invalidatedDispositionInit
    else if (BUG == 3) newEvidenceInit
    else readyInit

  action bypassDecisionGuard = all {
    authority.online, authority.durable.phase == Open,
    authority' = { ...authority, durable: applyReconcile(authority.durable, policy, invalidProposal) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  action treatDecisionAsPermanent = all {
    authority.online, authority.durable.phase == Open,
    authority.durable.decisions.length() > 0,
    // Incorrectly treats any past disposition as covering newly received evidence.
    authority' = { ...authority, durable: applyCommit(authority.durable,
      { kind: OutcomeFailed, exec: Current(2) }) },
    workers' = workers, network' = network, external' = external, clock' = clock,
  }

  // BUG 5..10 分别破坏请求不变,重投去重,原记录,原结果,持久化顺序或分支优先级.
  action brokenCommandHandling = {
    val before = authority.durable
    val refreshed = proposeDecision(before, success1, ExcludeFromJudgment, Operator(1))
    val rewritten = { ...originalCommand, decision: {
      ...originalCommand.decision, kind: AdoptSuccess, basis: VerifiedCompletion,
    } }
    val updated =
      if (BUG == 5) recordCommittedCommand(before,
        applyReconcileAndMaybeCommit(before, policy, refreshed), originalCommand)
      else if (BUG == 6) applyNewCommand(before, policy, originalCommand)
      else if (BUG == 7) { ...before, commands: List({ ...originalRecord, command: rewritten }) }
      else before
    val reply =
      if (BUG == 8) CommandCommitted({ ...originalRecord, outcomes: before.outcomes })
      else if (BUG == 10) CommandStale({
        command: originalCommand, revision: before.revision, current: before.current, reports: before.reports,
        view: judgmentView(before),
      })
      else if (BUG == 9) CommandCommitted(originalRecord)
      else CommandCommitted(updated.commands.head())
    all {
      authority.online, network.contains(ReconcileRequest(originalCommand)),
      authority' = { ...authority, durable: updated }, workers' = workers,
      network' = network.exclude(Set(ReconcileRequest(originalCommand))).union(Set(ReconcileReply(reply))),
      external' = observeCommandHandling(external, before, updated, policy, originalCommand, reply),
      clock' = clock,
    }
  }

  action brokenRejectionOrAccessHandling = {
    val before = authority.durable
    val access = if (BUG == 13) { maySubmit: false, mayRead: false }
      else if (BUG == 14 or BUG == 15) { maySubmit: false, mayRead: true }
      else fullCommandAccess
    val evaluatedPolicy = if (BUG == 16) { ...policy, excludable: Set() } else policy
    val updated =
      if (BUG == 11) applyNewCommand(before, policy, originalCommand)
      else if (BUG == 12) { ...before, rejections: List(rejectionFor(before, originalCommand)) }
      else if (BUG == 15) recordRejectedCommand(before, policy, originalCommand, access)
      else before
    val reply =
      if (BUG == 11 or BUG == 13) CommandCommitted(updated.commands.head())
      else if (BUG == 14) CommandForbidden(originalCommand)
      else if (BUG == 12) rejectionReply(updated.rejections.head())
      else CommandIneligible(originalCommand)
    all {
      authority.online, network.contains(ReconcileRequest(originalCommand)),
      authority' = { ...authority, durable: updated }, workers' = workers,
      network' = network.exclude(Set(ReconcileRequest(originalCommand))).union(Set(ReconcileReply(reply))),
      external' = observeCommandWithAccess(external, before, updated, evaluatedPolicy, originalCommand, access, reply),
      clock' = clock,
    }
  }

  // BUG 17..20 覆盖漏增,心跳误增,证据漏增和重置;用独立变化链检出,不能让见证反过来屏蔽动作.
  action brokenJudgmentRevision = {
    val before = authority.durable
    val correct = if (BUG == 17) applyReconcile(before, policy, validExclusion)
      else if (BUG == 18) applyRenew(before, t2, clock)
      else applyReport(before, querySuccess)
    val broken =
      if (BUG == 17 or BUG == 19) { ...correct, revision: before.revision }
      else if (BUG == 18) { ...correct, revision: before.revision + 1 }
      else { ...correct, revision: 0, judgmentChanges: List() }
    all {
      authority.online,
      authority' = { ...authority, durable: broken },
      workers' = workers, network' = network, external' = external, clock' = clock,
    }
  }

  action mutantStep =
    if (BUG >= 17) brokenJudgmentRevision
    else if (BUG >= 11) brokenRejectionOrAccessHandling
    else if (BUG >= 5) brokenCommandHandling
    else if (BUG == 4) treatDecisionAsPermanent
    else bypassDecisionGuard

  val mutantInvariant =
    if (BUG >= 17) judgmentRevisionSound
    else if (BUG == 11) commandRecordsUnique
    else if (BUG == 12) rejectedCommandsImmutable
    else if (BUG == 13) commandReadAuthorized
    else if (BUG == 14) commandHandlingSound
    else if (BUG == 15) rejectionQualified
    else if (BUG == 16) commandRepliesSound
    else if (BUG == 5) commandExecutionMatchesRequest
    else if (BUG == 6) commandRecordsUnique
    else if (BUG == 7) commandRecordsImmutable
    else if (BUG == 8 or BUG == 9) commandRepliesSound
    else if (BUG == 10) commandHandlingSound
    else if (BUG == 4) failureRespectsOldSuccess
    else reconciliationQualified

  run mutationCaughtTest = mutantInit.expect(commandSafety)
    .then(mutantStep).expect(not(mutantInvariant)
      and (if (BUG >= 5) not(commandSafety) else not(safety)))
}
