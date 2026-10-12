// Caller-owned durable progress; never added to an Intent ledger.
module continuationState {
  import multiIntentProfiles.* from "../multi/profiles"
  export multiIntentProfiles.*
  type ProgressRecord = {
    owner: int, sourceCall: int, stepKey: int, ruleVersion: int,
    consumed: Set[CollectedResult], nextCall: int, nextDependency: Dependency,
  }
  type ProgressDecision = NoProgress | ProgressCommitted(ProgressRecord)
  type ProgressState = {
    decision: ProgressDecision,
    // Independent immutable commit witness, not a required product field.
    commits: List[ProgressRecord],
    // Action coverage only; never used to authorize a decision or invocation.
    registrations: List[int], collections: List[{ call: int, restarts: int }],
    recoveredReads: Set[CollectedResult],
  }
  var progress: ProgressState
  pure val initialProgress: ProgressState = { decision: NoProgress, commits: List(),
    registrations: List(), collections: List(), recoveredReads: Set() }
  action progressInit = all { joinedInit, progress' = initialProgress }
  action holdProgress = progress' = progress
  // Exclude scheduleRound: the successor manifest is reconstructed from the decision.
  action ordinaryRuntimeStep = any {
    scheduleSubmission, scheduleReply,
    scheduleExecution, scheduleCompletion, scheduleResourceReport, scheduleDelivery,
  }
  action progressRuntimeStep = all { ordinaryRuntimeStep, holdProgress }
}
