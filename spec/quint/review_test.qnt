module review_test {
  import architectureTypes.* from "./types"
  import architecture(RUNS = Set(0, 1), SLOTS = Set(0, 1), ATTEMPT_SLOTS = Set(0, 1, 2), QUEUE_LIMIT = 12, COMMAND_LIMIT = 32).* from "./architecture"
  pure val e = (0, 0)
  pure val a = (e, 0)
  run pending = init.then(appendInput(0, 0, 1)).then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).then(commit(0)).expect(architectureSafety)
  run evaluationCaptureTest = init.then(appendInput(0, 0, 1)).then(evaluate(0, 0, InvokeStep, 0, NonRepeatable))
    .then(replaceProvider(0, false)).then(commit(0)).expect(architectureSafety and s.effects.get(e).intent == 0)
  run observationPermissionBlockTest = pending.then(admit(e, a, 0, 0, 0)).then(ownerFault(0, true))
    .then(permission(ObserveOp)).expect(not(usefulEnabled(s)) and classifiedBlocked(s) and G08)
  // Missing reply insertion is a reachable transition mutation: record the normal
  // result update, but deliberately omit its atomic inbox insertion.
  action badMissingReply = {
    val changed = applyObserve(s, a)
    advance({...changed, runs: changed.runs.setBy(0, rr => {...rr, inbox: s.runs.get(0).inbox})})
  }
  run missingReplyStallDetectionTest = pending.then(admit(e, a, 0, 0, 0)).then(enter(a, 0)).then(complete(a, Success))
    .then(badMissingReply).expect(not(G03) and not(G08) and not(referenceSafety))
  // Bypassing the FailRun active guard must be caught by the observable relation.
  action badSuspendedFailure = advance(applyFail(s, 0))
  run suspendedFailureDetectionTest = init.then(appendInput(0, 0, 1)).then(evaluate(0, 0, FaultStep, 0, NonRepeatable))
    .then(control(0, Suspended)).then(badSuspendedFailure).expect(not(referenceSafety))
  // Former accepted-gap probes are now regressions that require detection/refusal.
  action badTerminalResume = advance(applyControl(s, 1, Active))
  run terminalResumeBlindSpotTest = init.then(appendInput(0, 0, 1)).then(evaluate(0, 0, FinishStep, 0, NonRepeatable))
    .then(commit(0)).then(fork(0, 1, 1, ValidImport)).expect(not(canControl(s, 1, Active)))
    .then(badTerminalResume).expect(not(G05) and not(referenceSafety) and s.runs.get(1).lifetime == Finished and s.runs.get(1).mode == Active)
  run recoveryOwnerReuseGapTest = pending.then(admit(e, a, 0, 0, 0)).then(enter(a, 0)).then(ownerFault(0, false)).then(lose(a))
    .then(resolve(e, 2, RepeatOp)).then(reconnect(0))
    .expect(architectureSafety and not(canAdmit(s, e, (e, 1), 0, 3, 0)) and canAdmit(s, e, (e, 1), 1, 3, 0))
  // A real command-path counterexample: observation replay omits binding fields
  // from its key comparison. The command succeeds, but the reference rejects it.
  run observationBindingConflictCounterexampleTest = pending.then(admit(e, a, 0, 0, 0)).then(enter(a, 0)).then(complete(a, Success))
    .then(command(0, {...emptyCommand, tag: ObservationCommand, observation: Success, observationId: 4}))
    .then(rejectCommand(1, {...emptyCommand, tag: ObservationCommand, observation: Success, observationId: 4, generation: 999, domain: 999, intent: 999}))
    .expect(architectureSafety and s.error == KeyConflict and not(s.commandReceipts.get(1).valid))
  action inconclusiveDeclaration = advance({...s, providers: s.providers.setBy(0, pr => {...pr, failureConclusive: false})})
  action badFailureApplicability = advance(recordOutcome(s, e, ErrorResult, Failure, false, 0))
  run inconclusiveFailureTest = init.then(inconclusiveDeclaration).then(appendInput(0, 0, 1)).then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).then(commit(0))
    .then(admit(e, a, 0, 0, 0)).then(enter(a, 0)).then(complete(a, Failure)).then(observe(a, 0))
    .expect(architectureSafety and s.effects.get(e).phase == Unknown and s.effects.get(e).replyCount == 0 and not(canAdmit(s, e, (e, 1), 1, 2, 0)))
  run failureDeclarationMutationTest = init.then(inconclusiveDeclaration).then(appendInput(0, 0, 1)).then(evaluate(0, 0, InvokeStep, 0, NonRepeatable)).then(commit(0))
    .then(admit(e, a, 0, 0, 0)).then(enter(a, 0)).then(complete(a, Failure)).then(badFailureApplicability).expect(not(G03) and not(referenceSafety))
  action badFabricatedBoundary = {
    val fake = {...s, runs: s.runs.setBy(0, rr => {...rr, boundaries: rr.boundaries.replaceAt(1, {...rr.boundaries.nth(1), valid: true})})}
    advance(applyFork(fake, 0, 1, 1))
  }
  action badRecoveryOwnerReuse = advance(applyAdmit(s, e, (e, 1), 0))
  run recoveryOwnerMutationTest = pending.then(admit(e, a, 0, 0, 0)).then(enter(a, 0)).then(ownerFault(0, false)).then(lose(a)).then(resolve(e, 2, RepeatOp)).then(badRecoveryOwnerReuse).expect(not(G02) and not(referenceSafety))
  action badReceiptHistory = {
    val changed = applyCommand(s, 0, admissionEnvelope(s, e, a, 0, 0, 0))
    advance({...changed, runs: changed.runs.setBy(0, rr => {...rr, history: rr.history + 1})})
  }
  run receiptHistoryMutationTest = pending.then(badReceiptHistory).expect(not(referenceSafety))
  run fabricatedBoundaryMutationTest = pending.then(badFabricatedBoundary).expect(not(G06) and not(referenceSafety))
}
