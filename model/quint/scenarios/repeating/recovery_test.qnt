// Deterministic scenarios using the shared fixture and real guarded transitions.
module repeatingRecoveryTests {
  import repeatingFixtures.* from "./fixtures"
  export repeatingFixtures.*

  run oldSuccessBlocksOrdinaryFailureTest = oldSuccessCurrentFailureInit
    .expect(oldSuccessWithCurrentFailureReached)
    .expect(noUnresolvedRisk(authority.durable))
    .expect(authority.durable.phase == Open and authority.durable.outcomes.length() == 0)
    .then(finishFailure(2).fail())

  run oldSuccessDoesNotBlockCancellationTest = oldSuccessCurrentFailureInit
    .then(cancelIntent).expect(safety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeCancelled, exec: NoCurrent }))
    .expect(authority.durable.reports.contains(success1) and authority.durable.reports.contains(failure2))

  run failureThenOldSuccessStillBlocksTest = replacementInit
    .then(callExternal(t2)).expect(safety)
    .then(completeAtResource(2, Failure)).expect(safety)
    .then(publishCompletion(t2)).expect(safety)
    .then(receiveReport(failure2)).expect(safety)
    .expect(not(noUnresolvedRisk(authority.durable)))
    .then(callExternal(t1)).expect(safety)
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .expect(oldSuccessWithCurrentFailureReached and noUnresolvedRisk(authority.durable))
    .expect(authority.durable.attempts.get(2).phase == Resolved)
    .then(finishFailure(2).fail())

  run bothKnownFailuresCanCloseTest = replacementInit
    .then(callExternal(t1)).expect(safety)
    .then(completeAtResource(1, Failure)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport({ ...success1, kind: Failure })).expect(safety)
    .then(callExternal(t2)).expect(safety)
    .then(completeAtResource(2, Failure)).expect(safety)
    .then(publishCompletion(t2)).expect(safety)
    .then(receiveReport(failure2)).expect(safety)
    .expect(not(oldSuccessNeedsReconciliation(authority.durable, 2)))
    .then(finishFailure(2)).expect(safety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeFailed, exec: Current(2) }))

  run duplicateEffectsButOneOutcomeTest = replacementInit
    .then(callExternal(t2)).expect(safety)
    .then(callExternal(t1)).expect(safety)
    .expect(external.effects == Set(1, 2))
    .then(completeAtResource(1, Success)).expect(safety)
    .then(publishCompletion(t1)).expect(safety)
    .then(receiveReport(success1)).expect(safety)
    .then(receiveReceipt(success1)).expect(safety)
    .expect(authority.durable.phase == Open and authority.durable.outcomes.length() == 0)
    .expect(workers.get(1).receipts.contains(success1))
    .then(completeAtResource(2, Success)).expect(safety)
    .then(publishCompletion(t2)).expect(safety)
    .then(receiveReport(success2)).expect(safety)
    .expect(authority.durable.outcomes == List({ kind: OutcomeSucceeded, exec: Current(2) }))
    .expect(authority.durable.reports.contains(success1) and authority.durable.reports.contains(success2))

  run duplicateRiskAcceptanceDoesNotProveFailureTest = replacementInit
    .then(callExternal(t2)).expect(safety)
    .then(completeAtResource(2, Failure)).expect(safety)
    .then(publishCompletion(t2)).expect(safety)
    .then(receiveReport(failure2)).expect(safety)
    .expect(authority.durable.attempts.get(1).knowledge == NoKnowledge)
    .expect(authority.durable.attempts.get(2).knowledge == FailureKnown)
    .expect(not(noUnresolvedRisk(authority.durable)))
    .expect(authority.durable.phase == Open)
    .then(finishFailure(2).fail())
}
