// Deterministic scenarios using the shared fixture and real guarded transitions.
module strictConflictsTests {
  import strictFixtures.* from "./fixtures"
  export strictFixtures.*

  run defensiveConflictProjectionTest = {
    val claimed = applyClaim(applyCreate(initialLedger, 1), 1, 1, 1, 0)
    val authorized = applyAuthorize(claimed, t1, 0)
    val firstReport = applyReport(authorized, success1)
    val conflict = applyReport(firstReport, failure1)
    val terminal: Outcome = { kind: OutcomeSucceeded, exec: Current(1) }
    val committed = applyCommit(firstReport, terminal)
    val lateConflict = applyReport(committed, failure1)
    init.expect(all {
      conflict.reports.size() == 2, conflict.attempts.get(1).conflict,
      conflict.attempts.get(1).phase == firstReport.attempts.get(1).phase,
      conflict.attempts.get(1).knowledge == firstReport.attempts.get(1).knowledge,
      not(canCommit(conflict, terminal)), conflict.outcomes.length() == 0,
      lateConflict.attempts.get(1).conflict,
      lateConflict.attempts.get(1).phase == Resolved,
      lateConflict.attempts.get(1).knowledge == SuccessKnown,
      lateConflict.reports.size() == 2,
      lateConflict.outcomes == committed.outcomes,
      sameReportIdentity(success1, failure1),
      not(sameReportIdentity(success1, { ...success1, id: 4 })),
    })
  }

  run conflictDoesNotClearOnNewReportTest = {
    val claimed = applyClaim(applyCreate(initialLedger, 1), 1, 1, 1, 0)
    val authorized = applyAuthorize(claimed, t1, 0)
    val waiting = applyReport(authorized, pendingReport(t1))
    // Reuse the Pending identity with changed content: preserve Waiting, not Resolved.
    val disputed = applyReport(waiting, { ...success1, id: 1 })
    val subsequent = applyReport(disputed, success1)
    val cancelled: Outcome = { kind: OutcomeCancelled, exec: NoCurrent }
    init.expect(all {
      disputed.attempts.get(1).phase == Waiting,
      disputed.attempts.get(1).knowledge == NoKnowledge,
      disputed.attempts.get(1).conflict, disputed.reports.size() == 2,
      subsequent.attempts.get(1).phase == Waiting,
      subsequent.attempts.get(1).knowledge == NoKnowledge,
      subsequent.attempts.get(1).conflict, subsequent.reports.size() == 3,
      not(canCommit(subsequent, { kind: OutcomeSucceeded, exec: Current(1) })),
      canCommit(subsequent, cancelled),
      applyCommit(subsequent, cancelled).reports == subsequent.reports,
    })
  }
}
