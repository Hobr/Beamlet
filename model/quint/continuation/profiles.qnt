// Directed prefixes use real core commands, never injected Running/Closed states.
module continuationProfiles {
  import continuationProperties.* from "./properties"
  export continuationProperties.*
  pure val sourceRefA: ResolvedRef = { call: 1, slot: 1, intent: 1 }
  pure val sourceRefB: ResolvedRef = { call: 1, slot: 2, intent: 2 }
  pure val successorRef: ResolvedRef = { call: 2, slot: 1, intent: 3 }
  pure def progressCallback(i: int, kind: ReportKind, value: int): Report = {
    id: 3, exec: 1, kind: kind, value: value, origin: ByCallback(correlation(i, 1)),
  }
  action startProgressIntent(i: int, w: int): bool = {
    val t = { ...t1, worker: w }
    all { multiCreate(i, 1), holdProgress }.then(all { multiClaim(i, 1, w), holdProgress })
      .then(all { multiRequest(i, t), holdProgress }).then(all { multiAuthorize(i, t, callbackHandler), holdProgress })
      .then(all { multiGrant(i, scoped(i, StartReply(t)), t), holdProgress })
      .then(all { multiCall(i, t), holdProgress })
  }
  action finishProgressIntent(i: int, kind: ReportKind, value: int): bool = {
    val r = progressCallback(i, kind, value)
    all { multiComplete(i, 1, kind, value), holdProgress }
      .then(all { multiEmitCallback(i, r, true), holdProgress })
      .then(all { multiReceive(i, scoped(i, ResultReport(r)), r), holdProgress })
  }
  action resolveProgressReply(reply: SubmissionReply): bool = all { multiResolve(1, reply), holdProgress }
  action resolveProgressSources = resolveProgressReply({ request: request, result: CreatedIntent(1) })
    .then(resolveProgressReply({ request: requestB, result: CreatedIntent(2) }))
  action readProgressResult(ref: ResolvedRef): bool = readContinuation(ref)
  action crashProgressAgent = all { crashAgent(1), holdProgress }
  action restartProgressAgent = all { restartAgent(1), holdProgress }
  action collectProgressRound(c: int): bool = collectContinuation(c)
  action sendNext = match progress.decision {
    | NoProgress => all { false, holdRuntime, callerRounds' = callerRounds,
        agentLocals' = agentLocals, holdProgress }
    | ProgressCommitted(r) => all { manifestMatches(callerRounds, r),
        multiSend(r.owner, r.nextDependency.request), holdProgress }
  }
  action submitNext = match progress.decision {
    | NoProgress => all { false, holdRuntime, callerRounds' = callerRounds,
        agentLocals' = agentLocals, holdProgress }
    | ProgressCommitted(r) => all { manifestMatches(callerRounds, r),
        multiSubmit(r.owner, r.nextDependency.request), holdProgress }
  }
  action decideA = all {
    agentLocals.get(1).results.filter(r => r.call == 1 and r.slot == 1).size() > 0,
    nondet result = agentLocals.get(1).results.filter(r => r.call == 1 and r.slot == 1).oneOf()
    decide(result)
  }
  action runningProgressInit = all { bothRunningInit, progress' = initialProgress }
  action partialProgressInit = runningProgressInit.then(resolveProgressSources)
    .then(finishProgressIntent(1, Success, 1)).then(readProgressResult(sourceRefA))
  action decidedProgressInit = partialProgressInit.then(decideA)
  action registeredProgressInit = decidedProgressInit.then(registerNext)
  action submittedProgressInit = registeredProgressInit.then(sendNext).then(submitNext)
  action closedProgressInit = submittedProgressInit.then(startProgressIntent(3, 2))
    .then(finishProgressIntent(3, Success, 1))
}
