// Reachability witnesses; not transition guards.
// 通过 quint run --witnesses 观察可达性;这些谓词不是要求每条轨迹最终满足的活性性质.
// marks 只标记事件发生过,不能把它们加入动作守卫以排除本应探索的交错.
module executionWitnesses {
  import executionEvidenceLogic.* from "../logic/execution_evidence"
  export executionEvidenceLogic.*

  val claimedReached = EXECUTIONS.exists(e => authority.durable.attempts.get(e).lease.claimed)

  val clockBackwardReached = external.marks.contains("clockBackward")

  val requestReached = network.exists(m => match m {
    | StartRequest(_) => true | _ => false
  })

  val authorizedReached = authority.durable.starts.length() > 0

  val grantReceivedReached = external.marks.contains("grantReceived")

  val replyResentReached = external.marks.contains("replyResent")

  val expiryReached = authority.durable.invalidLeases.size() > 0

  val unknownReached = EXECUTIONS.exists(e => authority.durable.attempts.get(e).phase == Unknown)

  val renewalReached = external.marks.contains("renewed")

  val externalCallReached = external.invocations.length() > 0

  val resourceCompletedReached = EXECUTIONS.exists(e => external.finished.get(e) != ResourceUnfinished)

  val pendingSentReached = external.emitted.exists(r => r.kind == Pending)

  val completionSentReached = external.emitted.exists(r =>
    r.origin != ByQuery and (r.kind == Success or r.kind == Failure))

  val waitingReached = EXECUTIONS.exists(e => authority.durable.attempts.get(e).phase == Waiting)

  val resolvedReached = EXECUTIONS.exists(e => authority.durable.attempts.get(e).phase == Resolved)

  val succeededReached = authority.durable.outcomes.select(o => o.kind == OutcomeSucceeded).length() > 0

  val lateReportReached = external.marks.contains("lateReport")

  val cancelledReached = authority.durable.outcomes.select(o => o.kind == OutcomeCancelled).length() > 0

  val failedReached = authority.durable.outcomes.select(o => o.kind == OutcomeFailed).length() > 0

  val replacementReached = authority.durable.retries.length() > 0

  val negativeQueryReached = authority.durable.reports.exists(r => r.kind == NotFound)

  val queryReached = external.marks.contains("queried")

  val fencedReached = external.noFuture.size() > 0

  val workerCrashReached = external.marks.contains("workerCrashed")

  val workerRestartReached = external.marks.contains("workerRestarted")

  val coordinatorCrashReached = external.marks.contains("coordinatorCrashed")

  val coordinatorRestartReached = external.marks.contains("coordinatorRestarted")

  val messageLossReached = external.marks.contains("messageLost")

  val duplicateGrantReached = external.marks.contains("duplicateGrant")

  val oldGrantRejectedReached = external.marks.contains("oldGrantRejected")

  val receiptReached = external.marks.contains("receiptReceived")

  val duplicateReportReached = external.marks.contains("duplicateReport")

  val reportResentReached = external.marks.contains("reportResent")

  val oldSuccessWithCurrentFailureReached = EXECUTIONS.exists(e =>
    authority.durable.current == Current(e)
      and authority.durable.attempts.get(e).knowledge == FailureKnown
      and oldSuccessNeedsReconciliation(authority.durable, e))

  val preparedReached = EXECUTIONS.exists(e => authority.durable.attempts.get(e).exists)
}
