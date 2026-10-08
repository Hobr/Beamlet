module architecture_test {
  import architectureTypes.* from "./types"
  import architecture(RUNS = Set(0, 1), SLOTS = Set(0, 1), ATTEMPT_SLOTS = Set(0, 1, 2), QUEUE_LIMIT = 12, COMMAND_LIMIT = 32).* from "./architecture"
  pure val e0 = (0, 0)
  pure val e1 = (0, 1)
  pure val a0 = (e0, 0)
  pure val a1 = (e0, 1)
  pure val a2 = (e0, 2)
  run pending = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)
  run admittedPrefix = pending
    .then(admit(e0, a0, 0, 0, 0)).expect(architectureSafety)
  run unknownPrefix = admittedPrefix
    .then(enter(a0, 0)).expect(architectureSafety)
    .then(ownerFault(0, false)).expect(architectureSafety)
    .then(lose(a0)).expect(architectureSafety)
  run observedPrefix = admittedPrefix
    .then(enter(a0, 0)).expect(architectureSafety)
    .then(complete(a0, Success)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety)

  run fullSystemTest = observedPrefix
    .then(evaluate(0, 0, WaitStep, 1, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).phase == Consumed)
  run duplicateDispatchTest = admittedPrefix
    .then(enter(a0, 0)).expect(architectureSafety).expect(not(canEnter(s, a0, 0))).expect(G02 and s.attempts.get(a0).calls == 1)
  run replacementOwnerTest = admittedPrefix
    .then(ownerFault(0, true)).expect(architectureSafety).expect(not(canEnter(s, a0, 1)))
    .then(lose(a0)).expect(architectureSafety).expect(G02 and s.effects.get(e0).phase == Unknown)
  run hostLossTest = admittedPrefix
    .then(enter(a0, 0)).expect(architectureSafety)
    .then(takeover(0, false)).expect(architectureSafety)
    .then(complete(a0, Success)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety)
    .then(evaluate(0, 1, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(1)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).phase == Consumed)
  run admissionBeforeSuspendTest = admittedPrefix
    .then(control(0, Suspended)).expect(architectureSafety)
    .then(enter(a0, 0)).expect(architectureSafety)
    .then(complete(a0, Success)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety).expect(s.effects.get(e0).phase == OutcomeRecorded and s.runs.get(0).cursor == 1)
    .then(control(0, Active)).expect(architectureSafety)
    .then(evaluate(0, 0, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).phase == Consumed)
  run suspendBeforeAdmissionTest = pending
    .then(control(0, Suspended)).expect(architectureSafety).expect(not(canAdmit(s, e0, a0, 0, 0, 0))).expect(G05 and s.grants.size() == 0)
  run finishLastReplyTest = observedPrefix
    .then(evaluate(0, 0, FinishStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(architectureSafety and s.runs.get(0).lifetime == Finished and s.effects.get(e0).phase == Consumed and s.runs.get(0).result == 2)
  run invalidFinishTest = pending
    .then(appendInput(0, 1, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, FinishStep, 0, NonRepeatable)).expect(architectureSafety).expect(not(canCommit(s, 0))).expect(s.runs.get(0).app == 1 and s.runs.get(0).cursor == 1)
    .then(failRun(0)).expect(architectureSafety).expect(architectureSafety and s.runs.get(0).lifetime == Failed and s.effects.get(e0).phase == Pending)
  run recoveryPermissionTest = unknownPrefix
    .then(resolve(e0, 2, RepeatOp)).expect(architectureSafety)
    .then(admit(e0, a1, 1, 3, 0)).expect(architectureSafety).expect(not(canAdmit(s, e0, a2, 2, 3, 0)))
    .then(enter(a1, 1)).expect(architectureSafety)
    .then(complete(a1, Success)).expect(architectureSafety)
    .then(observe(a1, 1)).expect(architectureSafety)
    .then(dispose(0)).expect(architectureSafety)
    .then(evaluate(0, 0, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(architectureSafety and recoveryConsumedWitness and s.effects.get(e0).permitsUsed == Set(1))

  run precommitLossTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(loseProposal(0)).expect(architectureSafety).expect(not(s.effects.get(e0).exists) and s.entries.size() == 0)
    .then(evaluate(0, 1, InvokeStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(1)).expect(architectureSafety).expect(architectureSafety)
  run competingControllersTest = pending
    .then(admit(e0, a0, 0, 0, 0)).expect(architectureSafety).expect(not(canAdmit(s, e0, a1, 1, 0, 0)) and not(canAdmit(s, e0, a1, 1, 1, 0)) and G02)
  run earlierUnknownFailureTest = unknownPrefix
    .then(resolve(e0, 2, RepeatOp)).expect(architectureSafety)
    .then(admit(e0, a1, 1, 3, 0)).expect(architectureSafety)
    .then(enter(a1, 1)).expect(architectureSafety)
    .then(complete(a1, Failure)).expect(architectureSafety)
    .then(observe(a1, 1)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).phase == Unknown and s.effects.get(e0).replyCount == 0 and s.attempts.get(a0).phase == UnknownAttempt and not(canAdmit(s, e0, a2, 2, 5, 0)))
  run earlierUnknownPrecheckTest = unknownPrefix
    .then(resolve(e0, 2, RepeatOp)).expect(architectureSafety)
    .then(admit(e0, a1, 1, 3, 0)).expect(architectureSafety)
    .then(replaceProvider(0, false)).expect(architectureSafety)
    .then(precheckReject(a1)).expect(architectureSafety)
    .then(observe(a1, 1)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).phase == Unknown and s.effects.get(e0).result == NoResult and s.attempts.get(a0).phase == UnknownAttempt)
  run unknownNotificationConsumptionTest = unknownPrefix
    .then(evaluate(0, 0, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).phase == Unknown and s.effects.get(e0).replyCount == 0 and s.runs.get(0).cursor == 2)
  run auditNoExecutionTest = unknownPrefix
    .then(resolve(e0, 2, AuditOp)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).result == NoResult and s.grants.size() == 1 and s.effects.get(e0).permit == 0)
  run suspendedSettleTest = unknownPrefix
    .then(control(0, Suspended)).expect(architectureSafety)
    .then(resolve(e0, 2, SettleOp)).expect(architectureSafety).expect(s.effects.get(e0).phase == OutcomeRecorded and s.runs.get(0).app == 1)
    .then(control(0, Active)).expect(architectureSafety)
    .then(dispose(0)).expect(architectureSafety)
    .then(evaluate(0, 0, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).phase == Consumed)
  run observationWinsSettlementTest = unknownPrefix
    .then(complete(a0, Success)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety).expect(not(canResolve(s, e0, 2, SettleOp)) and not(canResolve(s, e0, 3, RepeatOp)) and s.effects.get(e0).replyCount == 1 and architectureSafety)
  run settlementWinsObservationTest = unknownPrefix
    .then(resolve(e0, 2, SettleOp)).expect(architectureSafety)
    .then(complete(a0, Failure)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).result == OkResult and s.effects.get(e0).replyCount == 1 and s.attempts.get(a0).observed.contains(Failure))
  run repeatNotPermanentTest = unknownPrefix
    .then(resolve(e0, 2, RepeatOp)).expect(architectureSafety)
    .then(admit(e0, a1, 1, 3, 0)).expect(architectureSafety)
    .then(ownerFault(1, false)).expect(architectureSafety)
    .then(lose(a1)).expect(architectureSafety).expect(not(canAdmit(s, e0, a2, 2, 5, 0)) and s.effects.get(e0).permit == 0 and s.effects.get(e0).permitsUsed == Set(1) and architectureSafety)
  run providerGenerationTest = admittedPrefix
    .then(replaceProvider(0, false)).expect(architectureSafety).expect(not(canEnter(s, a0, 0)))
    .then(precheckReject(a0)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).phase == Pending and s.attempts.get(a0).actual == NotExecuted and s.attempts.get(a0).calls == 0)
  run capturedIntentTest = pending
    .then(replaceProvider(0, false)).expect(architectureSafety)
    .then(admit(e0, a0, 0, 0, 0)).expect(architectureSafety)
    .then(enter(a0, 0)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).intent == 0 and s.providers.get(0).configuration == 1 and s.effects.get(e0).token == e0)
  run controllerReplacementTest = pending
    .then(takeover(0, true)).expect(architectureSafety).expect(not(canAdmit(s, e0, a0, 0, 0, 0)))
    .then(controllerReady(0)).expect(architectureSafety)
    .then(admit(e0, a0, 0, 0, 1)).expect(architectureSafety)
    .then(takeover(0, true)).expect(architectureSafety)
    .then(enter(a0, 0)).expect(architectureSafety).expect(architectureSafety and s.attempts.get(a0).controllerAtGrant == 1)
  run providerUnavailableTest = pending
    .then(providerFault(0, DependencyAbsent)).expect(architectureSafety).expect(not(canAdmit(s, e0, a0, 0, 0, 0)))
    .then(providerFault(0, DependencyAbsent)).expect(architectureSafety)
    .then(providerFault(0, IncompatibleProvider)).expect(architectureSafety).expect(not(canAdmit(s, e0, a0, 0, 0, 0)) and s.effects.get(e0).phase == Pending)
  run fifoContinuationTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(appendInput(0, 1, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, ContinueStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(s.runs.get(0).inbox.nth(1).kind == External and s.runs.get(0).inbox.nth(2).kind == Continuation)
    .then(evaluate(0, 0, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)
    .then(dispose(0)).expect(architectureSafety).expect(architectureSafety and s.runs.get(0).revision == 2 and s.runs.get(0).cursor == 3 and s.runs.get(0).inbox.nth(2).disposition == StaleContinuation)
  run obsoleteEvaluatedUnknownTest = unknownPrefix
    .then(evaluate(0, 0, InvokeStep, 1, NonRepeatable)).expect(architectureSafety)
    .then(complete(a0, Success)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety).expect(not(canCommit(s, 0)) and not(canFail(s, 0)))
    .then(rejectProposal(0)).expect(architectureSafety)
    .then(dispose(0)).expect(architectureSafety).expect(architectureSafety and not(s.effects.get(e1).exists) and s.runs.get(0).inbox.nth(1).disposition == ObsoleteUncertainty)
  run obsoleteUnknownFaultTest = unknownPrefix
    .then(evaluate(0, 0, FaultStep, 1, NonRepeatable)).expect(architectureSafety)
    .then(resolve(e0, 2, SettleOp)).expect(architectureSafety).expect(not(canFail(s, 0)))
    .then(rejectProposal(0)).expect(architectureSafety)
    .then(dispose(0)).expect(architectureSafety).expect(architectureSafety and s.runs.get(0).lifetime == Open)
  run failedLateResultTest = admittedPrefix
    .then(appendInput(0, 1, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, FaultStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(failRun(0)).expect(architectureSafety)
    .then(enter(a0, 0)).expect(architectureSafety)
    .then(complete(a0, Success)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety).expect(architectureSafety and s.runs.get(0).app == 1 and s.runs.get(0).inbox.nth(2).disposition == RunFailed and s.effects.get(e0).phase == OutcomeRecorded and not(canControl(s, 0, Active)))
  run faultTakeoverFirstTest = pending
    .then(appendInput(0, 1, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, FaultStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(takeover(0, false)).expect(architectureSafety).expect(not(canFail(s, 0)))
    .then(rejectProposal(0)).expect(architectureSafety).expect(architectureSafety and s.runs.get(0).lifetime == Open)
  run faultBeforeTakeoverTest = pending
    .then(appendInput(0, 1, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, FaultStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(failRun(0)).expect(architectureSafety).expect(not(canTakeover(s, 0)) and architectureSafety)
  run finishInputFirstTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, FinishStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(appendInput(0, 1, 1)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(architectureSafety and s.runs.get(0).inbox.nth(1).disposition == RunFinished and s.receipts.get(1).valid)
  run finishFirstInputTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, FinishStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)
    .then(rejectInput(0, 1, 1)).expect(architectureSafety).expect(architectureSafety and s.error == InvalidTransition and not(s.receipts.get(1).valid) and not(canControl(s, 0, Active)))
  run receiptAfterControlTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(loseAcknowledgement).expect(architectureSafety)
    .then(control(0, Suspended)).expect(architectureSafety)
    .then(retryInput(0, 0, 1)).expect(architectureSafety).expect(architectureSafety and s.acknowledged and s.runs.get(0).inbox.length() == 1)
    .then(rejectInput(0, 0, 2)).expect(architectureSafety).expect(s.error == KeyConflict and s.runs.get(0).inbox.length() == 1)
  run authorizationBeforeReceiptTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(permission(InputOp)).expect(architectureSafety)
    .then(rejectInput(0, 0, 1)).expect(architectureSafety).expect(s.error == Forbidden and s.receiptReads == 0 and not(canRetryInput(s, 0, 0, 1)))
    .then(permission(InputOp)).expect(architectureSafety)
    .then(authentication).expect(architectureSafety)
    .then(rejectInput(0, 0, 1)).expect(architectureSafety).expect(s.error == Unauthenticated and s.receiptReads == 0)
  run operationPermissionsTest = unknownPrefix
    .then(permission(SettleOp)).expect(architectureSafety).expect(not(canResolve(s, e0, 2, SettleOp)) and canResolve(s, e0, 2, AuditOp) and canResolve(s, e0, 2, RepeatOp))
    .then(resolve(e0, 2, AuditOp)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).result == NoResult)
  run authorityUnavailableTest = admittedPrefix
    .then(writeAvailability).expect(architectureSafety).expect(not(canInput(s, 0, 1)) and not(canAdmit(s, e0, a1, 1, 1, 0)))
    .then(enter(a0, 0)).expect(architectureSafety)
    .then(complete(a0, Success)).expect(architectureSafety).expect(not(canObserve(s, a0, 0)))
    .then(writeAvailability).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety).expect(architectureSafety)
  run uiIndependenceTest = pending
    .then(uiConnection).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).exists and s.runs.get(0).app == 1 and not(s.ui))
  run historicalBranchTest = pending
    .then(fork(0, 1, 0, ValidImport)).expect(architectureSafety).expect(s.runs.get(1).mode == Suspended and s.runs.get(1).app == 0 and s.runs.get(1).cursor == 0 and s.runs.get(1).inbox.length() == 0 and not(s.effects.get((1, 0)).exists))
    .then(control(1, Active)).expect(architectureSafety)
    .then(appendInput(1, 1, 1)).expect(architectureSafety)
    .then(evaluate(1, 1, InvokeStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(1)).expect(architectureSafety).expect(architectureSafety and branchNewWorkWitness and s.effects.get(e0).phase == Pending and s.effects.get((1, 0)).token != s.effects.get(e0).token)
  run unstableNotRetrofittedTest = observedPrefix
    .then(evaluate(0, 0, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(not(s.runs.get(0).boundaries.nth(1).valid) and s.runs.get(0).boundaries.nth(2).valid and not(canFork(s, 0, 1, 1, ValidImport)))
    .then(fork(0, 1, 2, ValidImport)).expect(architectureSafety).expect(architectureSafety)
  run finishedImportTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, FinishStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)
    .then(fork(0, 1, 1, ValidImport)).expect(architectureSafety).expect(architectureSafety and s.runs.get(1).lifetime == Finished and s.runs.get(1).result == 1 and s.runs.get(1).mode == Suspended and not(canControl(s, 1, Active)))
  run readyImportTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, ContinueStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)
    .then(fork(0, 1, 1, ValidImport)).expect(architectureSafety).expect(s.runs.get(1).cursor == 0 and s.runs.get(1).inbox.length() == 1 and s.runs.get(1).inbox.nth(0).effect == (1, 0))
    .then(control(1, Active)).expect(architectureSafety)
    .then(evaluate(1, 1, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(1)).expect(architectureSafety).expect(architectureSafety)
  run importRejectionsTest = init
    .then(rejectImport(MissingData)).expect(architectureSafety).expect(s.error == InvalidData and not(s.runs.get(1).exists))
    .then(rejectImport(BadVersion)).expect(architectureSafety).expect(s.error == IncompatibleVersion)
    .then(rejectImport(MissingResource)).expect(architectureSafety).expect(s.error == UnavailableResource)
    .then(rejectImport(ExcessiveData)).expect(architectureSafety).expect(s.error == ResourceLimit)
    .then(rejectImport(MissingPermission)).expect(architectureSafety).expect(s.error == Forbidden and not(s.runs.get(1).exists))

  run envelopeUnknownPrefix = init.then(submit(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commitEnvelope(0)).expect(architectureSafety).then(authorize(e0, a0, 0, 0, 0)).expect(architectureSafety)
    .then(enter(a0, 0)).expect(architectureSafety).then(ownerFault(0, false)).expect(architectureSafety)
    .then(reportLoss(a0)).expect(architectureSafety)
  run recoveryFixtureEnvelopeTest = envelopeUnknownPrefix.expect(s == recoveryFixture and s.commandReceipts.keys().filter(k => s.commandReceipts.get(k).valid).size() == 4)
  run combinedInterleavingTest = envelopeUnknownPrefix

    .then(claim(0, false)).expect(architectureSafety)
    .then(setMode(0, Suspended)).expect(architectureSafety)
    .then(replaceProvider(0, false)).expect(architectureSafety)

    .then(decide(e0, 2, RepeatOp)).expect(architectureSafety)
    .then(claim(0, true)).expect(architectureSafety)
    .then(setMode(0, Active)).expect(architectureSafety)

    .then(controllerReady(0)).expect(architectureSafety)
    .then(authorize(e0, a1, 1, 3, 3)).expect(architectureSafety)
    .then(enter(a1, 1)).expect(architectureSafety)
    .expect(not(canResolve(s, e0, 4, SettleOp)))

    .then(ownerFault(1, false)).expect(architectureSafety)
    .then(reportLoss(a1)).expect(architectureSafety)
    .then(decide(e0, 5, SettleOp)).expect(architectureSafety)

    .then(complete(a0, Failure)).expect(architectureSafety)
    .then(report(a0, 0)).expect(architectureSafety)
    .then(complete(a1, Success)).expect(architectureSafety)
    .then(report(a1, 1)).expect(architectureSafety)

    .then(disposeEnvelope(0)).expect(architectureSafety)
    .then(disposeEnvelope(0)).expect(architectureSafety)
    .then(evaluate(0, 0, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commitEnvelope(0)).expect(architectureSafety)
    .expect(recoveryConsumedWitness and s.effects.get(e0).replyCount == 1)

    .then(submit(0, 1, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, InvokeStep, 1, Deduplicated)).expect(architectureSafety)
    .then(commitEnvelope(0)).expect(architectureSafety)

    .then(branchEnvelope(0, 1, 2, ValidImport)).expect(architectureSafety)
    .then(setMode(1, Active)).expect(architectureSafety)
    .then(submit(1, 2, 1)).expect(architectureSafety)

    .then(evaluate(1, 1, InvokeStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commitEnvelope(1)).expect(architectureSafety)

    .then(authorize((1, 0), ((1, 0), 0), 2, 0, 1)).expect(architectureSafety)
    .then(enter(((1, 0), 0), 2)).expect(architectureSafety)

    .then(complete(((1, 0), 0), Success)).expect(architectureSafety)
    .then(report(((1, 0), 0), 2)).expect(architectureSafety)

    .then(evaluate(1, 1, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commitEnvelope(1)).expect(architectureSafety)
    .expect(architectureSafety and branchNewWorkWitness and s.effects.get(e1).phase == Pending and s.runs.get(1).app == 4)
  run twoEffectFifoTest = pending
    .then(appendInput(0, 1, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, InvokeStep, 1, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)

    .then(appendInput(0, 2, 1)).expect(architectureSafety)
    .then(admit(e0, a0, 0, 0, 0)).expect(architectureSafety)
    .then(admit(e1, (e1, 0), 1, 0, 0)).expect(architectureSafety)

    .then(enter(a0, 0)).expect(architectureSafety)
    .then(enter((e1, 0), 1)).expect(architectureSafety)
    .then(complete(a0, Success)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety)

    .then(complete((e1, 0), Success)).expect(architectureSafety)
    .then(observe((e1, 0), 1)).expect(architectureSafety)

    .then(evaluate(0, 0, ContinueStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)
    .expect(s.runs.get(0).cursor == 3 and s.runs.get(0).inbox.nth(5).kind == Continuation)

    .then(evaluate(0, 0, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)

    .then(evaluate(0, 0, ContinueStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)
    .then(dispose(0)).expect(architectureSafety)
    .expect(s.effects.get(e0).phase == Consumed and s.effects.get(e1).phase == Consumed and s.runs.get(0).revision == 5)

    .then(evaluate(0, 0, WaitStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety).expect(architectureSafety and s.runs.get(0).cursor == 7)
  run dedupSameDomainTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, InvokeStep, 0, Deduplicated)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)

    .then(admit(e0, a0, 0, 0, 0)).expect(architectureSafety)
    .then(enter(a0, 0)).expect(architectureSafety)
    .then(ownerFault(0, false)).expect(architectureSafety)
    .then(lose(a0)).expect(architectureSafety)

    .then(admit(e0, a1, 1, 2, 0)).expect(architectureSafety)
    .then(enter(a1, 1)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).token == e0 and s.attempts.get(a1).owner != s.attempts.get(a0).owner)
  run dedupChangedDomainTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, InvokeStep, 0, Deduplicated)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)

    .then(admit(e0, a0, 0, 0, 0)).expect(architectureSafety)
    .then(enter(a0, 0)).expect(architectureSafety)
    .then(ownerFault(0, false)).expect(architectureSafety)
    .then(lose(a0)).expect(architectureSafety)

    .then(replaceProvider(0, true)).expect(architectureSafety).expect(not(canAdmit(s, e0, a1, 1, 2, 0)))

    .then(resolve(e0, 2, RepeatOp)).expect(architectureSafety)
    .then(admit(e0, a1, 1, 3, 0)).expect(architectureSafety).expect(architectureSafety and s.effects.get(e0).token == e0)
  run dedupExpiryTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, InvokeStep, 0, Deduplicated)).expect(architectureSafety)
    .then(commit(0)).expect(architectureSafety)

    .then(admit(e0, a0, 0, 0, 0)).expect(architectureSafety)
    .then(enter(a0, 0)).expect(architectureSafety)
    .then(ownerFault(0, false)).expect(architectureSafety)
    .then(lose(a0)).expect(architectureSafety)

    .then(providerFault(0, ProtectionExpired)).expect(architectureSafety).expect(not(canAdmit(s, e0, a1, 1, 2, 0)) and architectureSafety)
  run unknownWhileSuspendedTest = admittedPrefix
    .then(control(0, Suspended)).expect(architectureSafety)
    .then(ownerFault(0, true)).expect(architectureSafety)
    .then(lose(a0)).expect(architectureSafety)
    .expect(not(canEnter(s, a0, 1)) and not(canAdmit(s, e0, a1, 1, 2, 1)) and architectureSafety)
  run staleEvaluatedSuspendTest = init
    .then(appendInput(0, 0, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(control(0, Suspended)).expect(architectureSafety)
    .expect(not(canCommit(s, 0)))
    .then(rejectProposal(0)).expect(architectureSafety).expect(not(s.effects.get(e0).exists) and architectureSafety)
  run duplicateObservationTest = observedPrefix.expect(not(canObserve(s, a0, 0)) and s.effects.get(e0).replyCount == 1 and architectureSafety)
  run duplicateUnknownTest = unknownPrefix.expect(not(canLose(s, a0)) and s.effects.get(e0).notifications == 1 and architectureSafety)
  run failedHistoricalForkTest = pending
    .then(appendInput(0, 1, 1)).expect(architectureSafety)
    .then(evaluate(0, 0, FaultStep, 0, NonRepeatable)).expect(architectureSafety)
    .then(failRun(0)).expect(architectureSafety)

    .then(fork(0, 1, 0, ValidImport)).expect(architectureSafety).expect(architectureSafety and s.runs.get(1).lifetime == Open and s.runs.get(1).mode == Suspended)
  // A terminal choice does not revoke an already admitted newer Attempt. Its
  // later unknown report is retained; failure eligibility is checked at choice.
  run terminalThenLaterUnknownTest = unknownPrefix
    .then(resolve(e0, 2, RepeatOp)).expect(architectureSafety)

    .then(admit(e0, a1, 1, 3, 0)).expect(architectureSafety)

    .then(complete(a0, Failure)).expect(architectureSafety)
    .then(observe(a0, 0)).expect(architectureSafety)

    .then(ownerFault(1, false)).expect(architectureSafety)
    .then(lose(a1)).expect(architectureSafety)
    .expect(s.effects.get(e0).result == ErrorResult and s.attempts.get(a1).phase == UnknownAttempt)

  run externalControllerGateTest = pending.then(takeover(0, true)).expect(architectureSafety)
    .expect(not(canAdmit(s, e0, a0, 0, 0, 1)) and not(canAutomaticAdmit(s, e0, a0, 0, 0, 1)))
    .then(controllerReady(0)).expect(architectureSafety).expect(not(canAutomaticAdmit(s, e0, a0, 0, 0, 1)))
    .then(admit(e0, a0, 0, 0, 1)).expect(architectureSafety).then(enter(a0, 0)).expect(architectureSafety)

}
