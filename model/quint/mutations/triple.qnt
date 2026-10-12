module tripleMutations {
  import tripleScenarios.* from "../scenarios/contracts/triple_test"
  export tripleScenarios.*
  const BUG: int
  action mutantInit = if (BUG == 2) tripleTwoCompletedInit else tripleRestartedInit
  action mutantStep = {
    val round = callerRounds.get(1)
    val deps = if (BUG == 1) Set(dependencyA, dependencyB)
      else Set(dependencyA, dependencyB, { ...dependencyC,
        request: { ...requestC, identity: StableKey({ namespace: 3, key: 2 }) } })
    all { holdRuntime, agentLocals' = agentLocals,
      callerRounds' = callerRounds.set(1, if (BUG == 2) { ...round, completed: true,
        results: agentLocals.get(1).results }
        else { ...round, dependencies: deps, registered: { owner: 1, dependencies: deps } }) }
  }
  val mutantInvariant = if (BUG == 2) tripleCompletionSound else tripleManifestSound
  run mutationCaughtTest = mutantInit.expect(tripleSafety).then(mutantStep).expect(not(mutantInvariant))
}
