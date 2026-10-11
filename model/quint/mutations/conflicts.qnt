// Intentionally broken conflict transitions; never imported by simulation entry points.
module conflictMutations {
  import conflictFixtures.* from "../scenarios/conflicts/fixtures"
  export conflictFixtures.*

  const BUG: int

  action mutantInit =
    if (BUG == 12) wideExcludedInit.then(sendReconciliationCommand(freshPartialExclusion)).expect(commandSafety)
    else if (BUG == 13) partiallySupersededInit
    else if (BUG >= 10) resolvedConflictInit.then(sendReconciliationCommand(replacementCommand)).expect(commandSafety)
    else if (BUG == 8) allExcludedInit
    else if (BUG == 9) conflictInit.then(sendReconciliationCommand(allExclusionCommand)).expect(commandSafety)
    else if (BUG == 5) resolvedConflictInit
      .then(offerCheckedEvidence(querySuccess)).expect(commandSafety)
      .then(receiveReport(querySuccess)).expect(commandSafety)
    else if (BUG == 3 or BUG == 7) resolvedConflictInit
    else conflictInit.then(sendReconciliationCommand(exclusionCommand)).expect(commandSafety)

  action mutantStep = {
    val before = authority.durable
    val omitted = conflictDecision(before, success1, AdoptSuccess, Set(keep(success1)), Operator(1))
    val updated =
      if (BUG == 1) applyReconcile(before, { ...policy, resolutions: Set(Set(keep(success1))) }, omitted)
      else if (BUG == 2) applyReconcile(before, { ...policy, resolutions: Set() }, exclusion)
      else if (BUG == 3) advanceJudgment(before, { ...before,
        attempts: before.attempts.set(1, { ...before.attempts.get(1), conflict: false }) })
      else if (BUG == 4 or BUG == 5) applyCommit(before, { kind: OutcomeFailed, exec: Current(2) })
      else if (BUG == 8) applyCommit(before, { kind: OutcomeFailed, exec: Current(2) })
      else if (BUG == 9) {
        val decided = applyReconcile(before, policy, allExclusionCommand.decision)
        val committed = applyCommit(decided, { kind: OutcomeSucceeded, exec: Current(1) })
        recordCommittedCommand(before, committed, allExclusionCommand)
      }
      else if (BUG == 10 or BUG == 11 or BUG == 12) {
        val intended = if (BUG == 12) freshPartialExclusion else replacementCommand
        val refs = if (BUG == 10) Set()
          else Set({ decisionIndex: if (BUG == 11) 7 else 0,
            reports: if (BUG == 12) Set(success1, disputedFailure, failure2) else Set(success1, disputedFailure) })
        val broken = { ...intended, decision: { ...intended.decision, supersedes: refs } }
        val applied = applyNewCommand(before, policy, broken)
        val ws = applied.decisions
        // Forge the admission flag: independent structural checks must still fail.
        { ...applied, decisions: ws.replaceAt(ws.length() - 1,
          { ...ws.nth(ws.length() - 1), supersessionQualified: true }) }
      }
      else if (BUG == 13) {
        val old = before.decisions.head()
        { ...before, decisions: before.decisions.replaceAt(0,
          { ...old, decision: { ...old.decision, evidence: excludeAllConflict } }) }
      }
      else if (BUG == 14) {
        val applied = applyReconcile(before, policy, {
          ...replacementCommand.decision, supersedes: Set() })
        recordCommittedCommand(before, applied, replacementCommand)
      }
      else if (BUG == 7) { ...before, reports: before.reports.exclude(Set(disputedFailure)) }
      else before
    all {
      authority.online,
      authority' = { ...authority, durable: updated }, workers' = workers,
      network' = if (BUG == 6)
        network.union(Set(ReconcileReply(CommandCommitted(exclusionRecord)))) else network,
      external' = external, clock' = clock,
    }
  }

  val mutantInvariant =
    if (BUG == 1 or BUG == 2) conflictCoverageSound
    else if (BUG == 3) conflictHistoryPreserved
    else if (BUG == 4 or BUG == 5) terminalConflictsResolved
    else if (BUG == 10 or BUG == 11 or BUG == 12) supersessionLinksSound
    else if (BUG == 13) decisionsImmutable
    else if (BUG == 14) commandExecutionMatchesRequest
    else if (BUG == 8) commitsQualified
    else if (BUG == 9) allExcludedCommitSound
    else if (BUG == 7) reconciledEvidencePreserved
    else commandRepliesSound
}
