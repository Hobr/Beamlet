module resourceProtocol {
  import resourceState.* from "./resource_state"
  export resourceState.*
  pure def environmentMatches(env: Environment, h: Handler): bool =
    env == target and h.operation == 1 and h.protocol == env.protocol
  pure def bindingMatches(b: ResourceBinding, t: Token, env: Environment): bool = match b {
    | ResourceUnbound => false
    | ResourceBound(s) => s.token == t and s.environment == target and s.environment == env
  }
  action authorizeResource(t: Token, h: Handler): bool = all {
    environmentMatches(resourceContract.environments.get(t.worker), h),
    normalAuthorize(t, h), resourceContract' = { ...resourceContract,
      bindings: resourceContract.bindings.set(t.exec,
        ResourceBound({ token: t, environment: resourceContract.environments.get(t.worker) })),
      saved: resourceContract.saved.append(ResourceBound({ token: t,
        environment: resourceContract.environments.get(t.worker) })) },
  }
  action callResource(t: Token): bool = all {
    bindingMatches(resourceContract.bindings.get(t.exec), t, resourceContract.environments.get(t.worker)),
    normalCall(t), resourceContract' = { ...resourceContract, calls: resourceContract.calls.append({
      token: t, binding: resourceContract.bindings.get(t.exec), actual: resourceContract.environments.get(t.worker) }) },
  }
  action changeEnvironment(w: int, env: Environment): bool = all {
    resourceContract.environments.get(w) != env, resourceContract.changes < 4,
    authority' = authority, workers' = workers, network' = network, external' = external,
    clock' = clock, usage' = usage,
    resourceContract' = { ...resourceContract,
      environments: resourceContract.environments.set(w, env), changes: resourceContract.changes + 1 },
  }
  val resourceBindingsSound = EXECUTIONS.forall(e => match resourceContract.bindings.get(e) {
    | ResourceUnbound => authority.durable.attempts.get(e).grant == NoGrant
    | ResourceBound(b) => b.environment == target and b.token.exec == e
      and authority.durable.attempts.get(e).grant == StartGrant(b.token)
      and resourceContract.saved.indices().exists(ix => resourceContract.saved.nth(ix) == ResourceBound(b))
  }) and resourceContract.saved.indices().forall(index => match resourceContract.saved.nth(index) {
    | ResourceUnbound => false
    | ResourceBound(b) => resourceContract.bindings.get(b.token.exec) == ResourceBound(b)
  })
  val resourceCallsSound = resourceContract.calls.length() == external.invocations.length()
    and resourceContract.calls.indices().forall(index => {
      val c = resourceContract.calls.nth(index)
      c.token == external.invocations.nth(index).token and c.actual == target
        and (match c.binding {
          | ResourceUnbound => false
          | ResourceBound(b) => b.environment == c.actual and b.token == c.token
            and resourceContract.saved.indices().exists(ix => resourceContract.saved.nth(ix) == c.binding)
        })
    })
  val resourceSafety = normalSafety and resourceBindingsSound and resourceCallsSound
  val boundWitness = resourceContract.saved.length() > 0
  val resourceCalledWitness = resourceContract.calls.length() > 0
  val changedWitness = resourceContract.changes > 0
  val migratedWorkerWitness = resourceContract.calls.indices().exists(ix => resourceContract.calls.nth(ix).token.worker == 2)
  val resourceCompletedWitness = authority.durable.phase == Closed
  action resourceHealthyStep = {
    nondet w = WORKERS.oneOf()
    val t = if (authority.durable.attempts.get(1).lease.claimed) tokenFor(authority.durable, 1) else t1
    any {
      authorizeResource(t, syncHandler), callResource(t),
      all { any { sendSubmission(request), receiveSubmission(request), normalCreate(1), normalClaim(1, w),
        normalRequest(t), normalGrant(t), normalComplete(1, Success, 1), normalPublish(t), normalReceiveAny, readFacts }, holdResource },
    }
  }
  action resourceStep = {
    nondet w = WORKERS.oneOf()
    nondet device = Set(1, 2).oneOf()
    nondet account = Set(1, 2).oneOf()
    nondet object = Set(1, 2).oneOf()
    nondet protocol = Set(1, 2).oneOf()
    any { resourceHealthyStep, changeEnvironment(w, { device: device, account: account, object: object, protocol: protocol }),
      all { any { normalClock(2), normalClock(0), normalExpire(1), releaseWorker(w),
        normalRestartWorker(w), normalCrashCoordinator, normalRestartCoordinator }, holdResource } }
  }
  action resourcePreparedInit = resourceInit.then(all { sendSubmission(request), holdResource })
    .then(all { receiveSubmission(request), holdResource }).then(all { normalCreate(1), holdResource })
    .then(all { normalClaim(1, 1), holdResource }).then(all { normalRequest(t1), holdResource })
  action resourceAlternateInit = resourceInit.then(changeEnvironment(2, target))
    .then(all { sendSubmission(request), holdResource }).then(all { receiveSubmission(request), holdResource })
    .then(all { normalCreate(1), holdResource }).then(all { normalClaim(1, 2), holdResource })
    .then(all { normalRequest({ ...t1, worker: 2 }), holdResource })
  action resourceBoundInit = resourcePreparedInit.then(authorizeResource(t1, syncHandler))
    .then(all { normalGrant(t1), holdResource })
}
