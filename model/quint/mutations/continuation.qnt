// Target checks remain independent of guards and saved success flags.
module continuationMutations {
  import continuationRecoveryTests.* from "../scenarios/continuation/recovery_test"
  export continuationRecoveryTests.*
  const BUG: int
  action mutantInit = if (BUG == 1 or BUG == 4) partialProgressInit
    else if (BUG == 2 or BUG == 6) registeredProgressInit.then(crashProgressAgent).then(restartProgressAgent)
    else if (BUG == 3) decidedProgressInit.then(crashProgressAgent)
    else decidedProgressInit.then(finishProgressIntent(2, Success, 2)).then(readProgressResult(sourceRefB))
  action mutantStep = if (BUG == 1) all { multiSend(1, nextRequest), holdProgress }
    else if (BUG == 2 or BUG == 6) all {
      multiSend(1, if (BUG == 2) { ...nextRequest, identity: StableKey({ namespace: 3, key: 2 }) }
        else { ...nextRequest, definition: { ...nextRequest.definition, input: 2 } }), holdProgress,
    } else {
      val wrong = if (BUG == 4) recordFor({ ...resultA, intent: 2 }) else recordFor(resultB)
      all { holdRuntime, callerRounds' = callerRounds, agentLocals' = agentLocals,
        progress' = if (BUG == 3) { ...progress, decision: NoProgress }
          else if (BUG == 4) applyDecide(progress, wrong)
          else { ...progress, decision: ProgressCommitted(wrong) },
      }
    }
  val mutantInvariant = if (BUG == 1 or BUG == 2 or BUG == 6) dispatchOrdering
    else if (BUG == 4) decisionSourcesSound else decisionStable
  run mutationCaughtTest = mutantInit.expect(continuationSafety)
    .then(mutantStep).expect(not(mutantInvariant))
}
