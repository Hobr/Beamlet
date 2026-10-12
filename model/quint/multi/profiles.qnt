// Legal prefixes; every running/closed state is reached through ordinary commands.
module multiIntentProfiles {
  import multiIntentScheduling.* from "./scheduling"
  export multiIntentScheduling.*
  action submitPair(a: int): bool = multiSend(a, request).then(multiSend(2, requestB))
    .then(multiSubmit(a, request)).then(multiSubmit(2, requestB))
  action independentInit = multiInit.then(openRound(1, 1, Set(dependencyA)))
    .then(openRound(2, 2, Set(dependencyB))).then(submitPair(1))
  action joinedInit = multiInit.then(openRound(1, 1, Set(dependencyA, dependencyB)))
    .then(multiSend(1, request)).then(multiSend(1, requestB))
    .then(multiSubmit(1, request)).then(multiSubmit(1, requestB))
  // Only used in prefixes at incarnation/generation 1.
  action startFirst(i: int, w: int, h: Handler): bool = {
    val t = { ...t1, worker: w }
    multiCreate(i, 1).then(multiClaim(i, 1, w)).then(multiRequest(i, t))
      .then(multiAuthorize(i, t, h)).then(multiGrant(i, scoped(i, StartReply(t)), t)).then(multiCall(i, t))
  }
  action bothRunningInit = joinedInit.then(startFirst(1, 1, callbackHandler)).then(startFirst(2, 1, callbackHandler))
  action releasedPairInit = bothRunningInit.then(multiPublish(1, t1, true)).then(multiPublish(2, t1, true))
    .then(multiReceive(1, scoped(1, ResultReport(pendingReport(t1))), pendingReport(t1)))
    .then(multiReceive(2, scoped(2, ResultReport(pendingReport(t1))), pendingReport(t1)))
    .then(sharedWorkerCrash(1))
  action unknownPairInit = joinedInit.then(startFirst(1, 1, syncHandler)).then(multiClockMove(2))
    .then(multiExpire(1, 1)).then(startFirst(2, 2, callbackHandler))
  pure val retryRequest = { ...request, definition: { ...definition, policy: RetryOnce } }
  action retryPairInit = multiInit.then(openRound(1, 1, Set({ ...dependencyA, request: retryRequest }, dependencyB)))
    .then(multiSend(1, retryRequest)).then(multiSubmit(1, retryRequest))
    .then(multiSend(1, requestB)).then(multiSubmit(1, requestB))
    .then(startFirst(1, 1, idempotentHandler)).then(startFirst(2, 1, callbackHandler))
    .then(multiComplete(1, 1, Failure, 1)).then(multiPublish(1, t1, false))
    .then(multiReceive(1, scoped(1, ResultReport({ id: 2, exec: 1, kind: Failure, value: 1, origin: ByWorker(t1) })),
      { id: 2, exec: 1, kind: Failure, value: 1, origin: ByWorker(t1) }))
    .then(multiReplace(1, 1, 2)).then(multiClaim(1, 2, 2)).then(multiRequest(1, t2))
    .then(multiAuthorize(1, t2, idempotentHandler)).then(multiGrant(1, scoped(1, StartReply(t2)), t2))
}
