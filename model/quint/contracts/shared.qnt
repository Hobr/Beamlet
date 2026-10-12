module sharedProtocol {
  import sharedState.* from "./shared_state"
  export sharedState.*
  pure val sharedHandler: Handler = { ...idempotentHandler, query: true, pending: true }
  pure def sameObjectKey(a: ObjectRequest, b: ObjectRequest): bool =
    a.account == b.account and a.object == b.object and a.operation == b.operation and a.key == b.key
  pure def objectReceipt(x: SharedObject, req: ObjectRequest): ObjectReceipt = {
    val saved = x.receipts.filter(r => sameObjectKey(r.request, req))
    val applied = req.expected == x.version
    if (saved.size() > 0) saved.fold({ request: req, applied: false, version: 0, value: 0 }, (_, r) => r)
    else { request: req, applied: applied, version: if (applied) x.version + 1 else x.version,
      value: if (applied) 1 else 2 }
  }
  pure def applyObject(x: SharedObject, req: ObjectRequest): SharedObject = {
    val r = objectReceipt(x, req)
    val replay = x.receipts.exists(old => sameObjectKey(old.request, req))
    { ...x, version: if (not(replay) and r.applied) r.version else x.version,
      content: if (not(replay) and r.applied) req.content else x.content,
      receipts: x.receipts.union(Set(r)),
      writes: if (not(replay) and r.applied) x.writes.append(r) else x.writes,
      replays: x.replays + (if (replay) 1 else 0) }
  }
  action executeObject(i: int, e: int): bool = {
    val req = objectRequest(i)
    val r = objectReceipt(sharedObject, req)
    all { resources.get(i).effects.contains(e),
      multiComplete(i, e, Success, r.value), sharedObject' = applyObject(sharedObject, req) }
  }
  action replayObject(i: int): bool = all {
    sharedObject.receipts.exists(r => r.request == objectRequest(i)),
    holdRuntime, callerRounds' = callerRounds, agentLocals' = agentLocals,
    sharedObject' = applyObject(sharedObject, objectRequest(i)),
  }
  action queryObject(i: int, e: int): bool = {
    val r = objectReceipt(sharedObject, objectRequest(i))
    all { sharedObject.receipts.contains(r), multiQuery(i, e, 3),
      sharedObject' = { ...sharedObject, reads: sharedObject.reads + 1,
        observations: sharedObject.observations.append({ intent: i, receipt: r }) } }
  }
  val objectWritesSound = sharedObject.writes.length() <= 1
    and sharedObject.version == sharedObject.writes.length()
    and sharedObject.content == (if (sharedObject.writes.length() == 0) 0
      else sharedObject.writes.nth(0).request.content)
    and sharedObject.receipts.filter(r => r.applied).size() == sharedObject.writes.length()
    and sharedObject.receipts.forall(r => r.request == objectRequest(r.request.intent)
      and r.version == 1 and r.value == (if (r.applied) 1 else 2)
      and sharedObject.receipts.filter(other => sameObjectKey(other.request, r.request)).size() == 1)
    and sharedObject.writes.indices().forall(ix => sharedObject.receipts.contains(sharedObject.writes.nth(ix)))
  val objectEvidenceSound = INTENTS.forall(i => {
    val own = sharedObject.receipts.filter(r => r.request == objectRequest(i))
    val x = resources.get(i)
    (EXECUTIONS.exists(e => x.finished.get(e) != ResourceUnfinished) implies own.size() == 1)
      and EXECUTIONS.forall(e => x.finished.get(e) != ResourceUnfinished implies
        own.exists(r => r.value == x.values.get(e)))
      and multiStore.intents.get(i).ledger.reports.forall(report => report.kind == Pending or
        own.exists(r => report.kind == Success and report.value == r.value))
      and multiStore.intents.get(i).ledger.outcomes.indices().forall(ix => {
        val o = multiStore.intents.get(i).ledger.outcomes.nth(ix)
        o.kind == OutcomeCancelled or own.exists(r => o.kind == OutcomeSucceeded and o.value == r.value)
      })
  }) and sharedObject.observations.indices().forall(ix => {
    val o = sharedObject.observations.nth(ix)
    o.receipt.request == objectRequest(o.intent) and sharedObject.receipts.contains(o.receipt)
  })
  val sharedSafety = multiSafety and objectWritesSound and objectEvidenceSound
  val appliedWitness = sharedObject.writes.length() == 1
  val mismatchWitness = sharedObject.receipts.exists(r => not(r.applied))
  val objectReplayWitness = sharedObject.replays > 0
  val objectRecoveryWitness = sharedObject.reads > 0
  val bothOutcomesWitness = INTENTS.forall(i => multiStore.intents.get(i).ledger.phase == Closed)
  action startShared(i: int, w: int): bool = {
    val t = { ...t1, worker: w }
    all { multiCreate(i, 1), holdObject }.then(all { multiClaim(i, 1, w), holdObject })
      .then(all { multiRequest(i, t), holdObject }).then(all { multiAuthorize(i, t, sharedHandler), holdObject })
      .then(all { multiGrant(i, scoped(i, StartReply(t)), t), holdObject })
      .then(all { multiCall(i, t), holdObject })
  }
  action sharedRunningInit = sharedInit.then(startShared(1, 1)).then(startShared(2, 2))
  action sharedAppliedInit = sharedRunningInit.then(executeObject(1, 1))
  action sharedBothInit = sharedAppliedInit.then(executeObject(2, 1))
  action sharedHealthyStep = {
    nondet i = INTENTS.oneOf()
    nondet e = EXECUTIONS.oneOf()
    nondet w = WORKERS.oneOf()
    val l = multiStore.intents.get(i).ledger
    val t = if (l.attempts.get(e).lease.claimed) tokenFor(l, e) else { ...t1, exec: e, worker: w }
    any { executeObject(i, e), replayObject(i), queryObject(i, e),
      all { any { multiCreate(i, e), multiClaim(i, e, w), multiRequest(i, t), multiAuthorize(i, t, sharedHandler),
        multiCall(i, t), multiPublish(i, t, false), multiReplace(i, 1, 2), scheduleDelivery,
        scheduleSubmission, scheduleReply, scheduleRead, scheduleCollect }, holdObject } }
  }
  action sharedStep = any { sharedHealthyStep, all { multiFaultStep, holdObject } }
}
