module continuationProtocolTests {
  import continuationProfiles.* from "../../continuation/profiles"
  export continuationProfiles.*
  pure val resultA: CollectedResult = { call: 1, slot: 1, intent: 1,
    outcome: { kind: OutcomeSucceeded, exec: Current(1), value: 1 } }
  pure val resultB: CollectedResult = { call: 1, slot: 2, intent: 2,
    outcome: { kind: OutcomeSucceeded, exec: Current(1), value: 2 } }
  pure val nextRequest = nextDependencyFor(resultA).request
  run initialDecisionIsNotAnAuthorityWorkflowTest = progressInit.expect(continuationSafety)
    .expect(progress == initialProgress and multiStore.catalog.length() == 2 and not(callerRounds.get(2).exists))
  run partialSuccessCommitsWithoutCompletingSourceRoundTest = partialProgressInit.then(decideA)
    .expect(continuationSafety and partialDecisionWitness)
    .expect(multiStore.intents.get(2).ledger.phase == Open and not(callerRounds.get(1).completed))
  run noDecisionCannotSendSuccessorTest = partialProgressInit.expect(continuationSafety).then(sendNext.fail())
  run decisionWithoutManifestCannotSendSuccessorTest = decidedProgressInit
    .expect(continuationSafety).then(sendNext.fail())
  run manifestUsesRecordedDefinitionTest = registeredProgressInit.expect(continuationSafety)
    .expect(callerRounds.get(2).dependencies == Set(nextDependencyFor(resultA)))
  run stableStepCannotDecideAgainTest = decidedProgressInit.expect(continuationSafety).then(decideA.fail())
  run sourceResultMustHaveBeenReadTest = runningProgressInit.then(resolveProgressSources)
    .then(finishProgressIntent(1, Success, 1)).expect(continuationSafety).then(decide(resultA).fail())
  run pendingIsNotAConsumedSuccessTest = all { releasedPairInit, progress' = initialProgress }
    .then(resolveProgressSources).expect(continuationSafety).then(decide(resultA).fail())
  run failedSourceCannotDriveSuccessOnlyPolicyTest = runningProgressInit.then(resolveProgressSources)
    .then(finishProgressIntent(1, Failure, 1)).then(readProgressResult(sourceRefA)).expect(continuationSafety)
    .then(decide({ ...resultA, outcome: { kind: OutcomeFailed, exec: Current(1), value: 1 } }).fail())
  run cancelledSourceCannotDriveSuccessOnlyPolicyTest = runningProgressInit.then(resolveProgressSources)
    .then(all { multiCancel(1), holdProgress }).then(readProgressResult(sourceRefA)).expect(continuationSafety)
    .then(decide({ ...resultA, outcome: { kind: OutcomeCancelled, exec: NoCurrent, value: 0 } }).fail())
  run unknownSiblingDoesNotBlockPartialDecisionTest = runningProgressInit.then(resolveProgressSources)
    .then(all { multiClockMove(2), holdProgress }).then(all { multiExpire(2, 1), holdProgress })
    .then(finishProgressIntent(1, Success, 1)).then(readProgressResult(sourceRefA)).then(decideA)
    .expect(continuationSafety and multiStore.intents.get(2).ledger.attempts.get(1).phase == Unknown)
  run laterSiblingCannotReplaceCommittedDecisionTest = decidedProgressInit
    .then(finishProgressIntent(2, Success, 2)).then(readProgressResult(sourceRefB))
    .expect(continuationSafety and progress.decision == ProgressCommitted(recordFor(resultA)))
    .then(decide(resultB).fail())
  run partialSubmissionPreservesUnfinishedSiblingTest = submittedProgressInit.expect(continuationSafety)
    .expect(partialSubmissionWitness and not(callerRounds.get(1).completed))
    .expect(multiStore.intents.get(2).ledger.phase == Open and multiStore.catalog.nth(2).request == nextRequest)
  run nextInputUsesConsumedOutcomeNotOriginalInputTest = runningProgressInit.then(resolveProgressSources)
    .then(finishProgressIntent(1, Success, 2)).then(readProgressResult(sourceRefA)).then(decideA).then(registerNext)
    .expect(continuationSafety and callerRounds.get(2).dependencies.forall(d => d.request.definition.input == 2))
  run cachedCommittedOutcomeCanDriveDecisionWhileAuthorityOfflineTest = partialProgressInit
    .then(all { multiAvailability(false), holdProgress }).then(decideA).then(registerNext)
    .expect(continuationSafety and not(multiStore.online) and manifestWitness)
}
