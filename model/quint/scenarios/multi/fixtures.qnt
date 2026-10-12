module multiIntentFixtures {
  import multiIntentProfiles.* from "../../multi/profiles"
  export multiIntentProfiles.*
  pure val refA: ResolvedRef = { call: 1, slot: 1, intent: 1 }
  pure val refB: ResolvedRef = { call: 1, slot: 2, intent: 2 }
  pure def callbackValue(i: int, kind: ReportKind, value: int): Report = {
    id: 3, exec: 1, kind: kind, value: value, origin: ByCallback(correlation(i, 1)),
  }
  pure def workerValue(t: Token, kind: ReportKind, value: int): Report = {
    id: 2, exec: t.exec, kind: kind, value: value, origin: ByWorker(t),
  }
  action finishCallback(i: int, kind: ReportKind, value: int): bool = {
    val r = callbackValue(i, kind, value)
    multiComplete(i, 1, kind, value).then(multiEmitCallback(i, r, true))
      .then(multiReceive(i, scoped(i, ResultReport(r)), r))
  }
  action finishWorker(i: int, t: Token, kind: ReportKind, value: int): bool = {
    val r = workerValue(t, kind, value)
    multiComplete(i, t.exec, kind, value).then(multiPublish(i, t, false))
      .then(multiReceive(i, scoped(i, ResultReport(r)), r))
  }
  action resolveJoined = multiResolve(1, { request: request, result: CreatedIntent(1) })
    .then(multiResolve(1, { request: requestB, result: CreatedIntent(2) }))
  action readJoined = readDependency(1, refA).then(readDependency(1, refB))
  action completePairInit = bothRunningInit.then(finishCallback(2, Success, 2)).then(finishCallback(1, Success, 1))
  action partiallyReadInit = bothRunningInit.then(resolveJoined).then(finishCallback(1, Success, 1))
    .then(readDependency(1, refA))
}
