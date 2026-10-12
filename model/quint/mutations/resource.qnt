module resourceMutations {
  import resourceScenarios.* from "../scenarios/contracts/resource_test"
  export resourceScenarios.*
  const BUG: int
  action mutantInit = if (BUG == 1) resourceBoundInit.then(changeEnvironment(1, { ...target, account: 2 }))
    else if (BUG == 2) resourcePreparedInit.then(changeEnvironment(1, { ...target, device: 2 }))
    else resourceBoundInit
  action mutantStep = if (BUG == 1) all {
    normalCall(t1), resourceContract' = { ...resourceContract, calls: resourceContract.calls.append({
      token: t1, binding: resourceContract.bindings.get(1), actual: resourceContract.environments.get(1) }) },
  } else if (BUG == 2) {
    val b = ResourceBound({ token: t1, environment: resourceContract.environments.get(1) })
    all { normalAuthorize(t1, syncHandler), resourceContract' = { ...resourceContract,
      bindings: resourceContract.bindings.set(1, b), saved: resourceContract.saved.append(b) } }
  } else {
    val b = ResourceBound({ token: t1, environment: { ...target, object: 2 } })
    all { authority' = authority, workers' = workers, external' = external, network' = network,
      clock' = clock, usage' = usage, resourceContract' = { ...resourceContract,
        bindings: resourceContract.bindings.set(1, b) } }
  }
  val mutantInvariant = if (BUG == 1) resourceCallsSound else resourceBindingsSound
  run mutationCaughtTest = mutantInit.expect(resourceSafety).then(mutantStep).expect(not(mutantInvariant))
}
