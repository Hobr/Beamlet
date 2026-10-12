// Authenticated routing precedes local report/token interpretation; transport is lossy.
module multiIntentReports {
  import multiIntentExecution.* from "./execution"
  export multiIntentExecution.*

  action multiPublish(i: int, t: Token, pending: bool): bool = {
    val d = multiStore.intents.get(i)
    val x = resources.get(i)
    val r = if (pending) pendingReport(t) else completionReport(x, t)
    all {
      if (pending) supportsPending(d.use, t.exec) else x.finished.get(t.exec) != ResourceUnfinished,
      canPublish(localFor(i, t.worker), t, r),
      writeIntent(i, d, withLocal(sharedWorkers, i, t.worker, applyPublish(localFor(i, t.worker), r)),
        { ...x, emitted: x.emitted.union(Set(r)) }, multiNetwork.messages.union(Set(scoped(i, ResultReport(r))))),
    }
  }
  action multiEmitCallback(i: int, r: Report, verified: bool): bool = all {
    canCallback(multiStore.intents.get(i).use, multiStore.intents.get(i).ledger, resources.get(i), r, verified),
    writeIntent(i, multiStore.intents.get(i), sharedWorkers,
      { ...resources.get(i), emitted: resources.get(i).emitted.union(Set(r)) },
      multiNetwork.messages.union(Set(scoped(i, ResultReport(r))))),
  }
  action multiCallback(i: int, e: int, id: int): bool =
    multiEmitCallback(i, callbackReport(resources.get(i), e, correlation(i, e), id), true)
  action multiQuery(i: int, e: int, id: int): bool = {
    val d = multiStore.intents.get(i)
    val x = resources.get(i)
    val r = queryReport(x, e, id)
    all { d.ledger.attempts.get(e).exists, d.ledger.attempts.get(e).grant != NoGrant,
      supportsQuery(d.use, e), freshQueryId(x, e, id),
      writeIntent(i, d, sharedWorkers, { ...x, emitted: x.emitted.union(Set(r)) },
        multiNetwork.messages.union(Set(scoped(i, ResultReport(r))))) }
  }
  action multiReceive(i: int, envelope: ScopedMessage, r: Report): bool = {
    val d = multiStore.intents.get(i)
    val after = receiveWithPolicy(d.use, d.ledger, r)
    all {
      multiStore.online, envelope.intent == i, envelope.message == ResultReport(r),
      multiNetwork.messages.contains(envelope), reportSourceValid(d.ledger, r),
      r.kind != Pending or supportsPending(d.use, r.exec), not(d.ledger.reports.contains(r)),
      writeIntent(i, { ...d, ledger: after, use: { ...d.use,
        acceptances: d.use.acceptances.append({ report: r, before: d.ledger, after: after,
          stop: stopRequired(d.use, d.ledger), definition: focused(d.use).request.definition,
          binding: d.use.bindings.get(r.exec), at: d.use.contractTime }) } },
        sharedWorkers, resources.get(i), multiNetwork.messages.union(Set(scoped(i, StoredReceipt(r))))),
    }
  }
  action multiDuplicate(i: int, r: Report): bool = all {
    multiStore.online, messagesFor(i).contains(ResultReport(r)), multiStore.intents.get(i).ledger.reports.contains(r),
    not(messagesFor(i).contains(StoredReceipt(r))),
    writeIntent(i, multiStore.intents.get(i), sharedWorkers, resources.get(i),
      multiNetwork.messages.union(Set(scoped(i, StoredReceipt(r))))),
  }
  action multiRedeliver(i: int, r: Report): bool = all {
    resources.get(i).emitted.contains(r), not(messagesFor(i).contains(ResultReport(r))),
    (match r.origin {
      | ByWorker(t) => localFor(i, t.worker).alive and localFor(i, t.worker).reports.contains(r)
      | ByCallback(_) => true | ByQuery => false
    }),
    writeIntent(i, multiStore.intents.get(i), sharedWorkers,
      { ...resources.get(i), marks: resources.get(i).marks.union(Set("redelivered")) },
      multiNetwork.messages.union(Set(scoped(i, ResultReport(r))))),
  }
  action multiReceipt(i: int, envelope: ScopedMessage, r: Report): bool = {
    val localUpdate = match r.origin {
      | ByWorker(t) => withLocal(sharedWorkers, i, t.worker, applyReceipt(localFor(i, t.worker), r))
      | _ => sharedWorkers
    }
    all {
      envelope.intent == i, envelope.message == StoredReceipt(r), multiNetwork.messages.contains(envelope),
      (match r.origin { | ByWorker(t) => localFor(i, t.worker).alive | _ => true }),
      writeIntent(i, multiStore.intents.get(i), localUpdate, resources.get(i),
        multiNetwork.messages.exclude(Set(envelope, scoped(i, ResultReport(r))))),
    }
  }
  action multiStop(i: int, e: int): bool = {
    val d = multiStore.intents.get(i)
    val o: Outcome = { kind: OutcomeFailed, exec: Current(e), value: knownResultValue(d.ledger, e, Failure) }
    all { multiStore.online, stopRequired(d.use, d.ledger), canCommit(d.ledger, o),
      writeIntent(i, { ...d, ledger: applyCommit(d.ledger, o) }, sharedWorkers, resources.get(i), multiNetwork.messages) }
  }
}
