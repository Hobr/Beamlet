// Per-Intent lease/start adapters share one Worker session and one Authority availability.
module multiIntentExecution {
  import multiIntentSubmission.* from "./submission"
  export multiIntentSubmission.*

  action multiCreate(i: int, e: int): bool = {
    val d = multiStore.intents.get(i)
    all { multiStore.online, d.exists, canCreate(d.ledger, e),
      writeIntent(i, { ...d, ledger: applyCreate(d.ledger, e) }, sharedWorkers,
        resources.get(i), multiNetwork.messages) }
  }
  action multiClaim(i: int, e: int, w: int): bool = {
    val d = multiStore.intents.get(i)
    val local = localFor(i, w)
    val l = applyClaim(d.ledger, e, w, local.incarnation, multiClock)
    val t = tokenFor(l, e)
    all { multiStore.online, d.exists, local.alive, canClaim(d.ledger, e, multiClock),
      writeIntent(i, { ...d, ledger: l }, withLocal(sharedWorkers, i, w,
        { ...local, leases: local.leases.union(Set(t)) }), resources.get(i), multiNetwork.messages) }
  }
  action multiRequest(i: int, t: Token): bool = all {
    canRequest(localFor(i, t.worker), messagesFor(i), t),
    writeIntent(i, multiStore.intents.get(i), sharedWorkers, resources.get(i),
      multiNetwork.messages.union(Set(scoped(i, StartRequest(t))))),
  }
  action multiAuthorize(i: int, t: Token, h: Handler): bool = {
    val d = multiStore.intents.get(i)
    val l = applyAuthorize(d.ledger, t, multiClock)
    val updated = { ...l, attempts: l.attempts.set(t.exec, { ...l.attempts.get(t.exec),
      completion: if (h.pending) CallbackBinding(correlation(i, t.exec)) else NoCompletion }) }
    all {
      multiStore.online, messagesFor(i).contains(StartRequest(t)), compatible(d.use, h),
      canAuthorize(d.ledger, t, multiClock), d.use.bindings.get(t.exec) == NoHandler,
      retryHandlerQualified(d.use, t.exec, h, d.use.contractTime),
      writeIntent(i, { ...d, ledger: updated,
        use: { ...d.use, bindings: d.use.bindings.set(t.exec, bindingFor(d.use, h)) } },
        sharedWorkers, resources.get(i), multiNetwork.messages.exclude(Set(scoped(i, StartRequest(t))))
          .union(Set(scoped(i, StartReply(t))))),
    }
  }
  // The receiver checks the authenticated Intent scope before projecting a local token.
  action multiGrant(i: int, envelope: ScopedMessage, t: Token): bool = all {
    envelope.intent == i, envelope.message == StartReply(t), multiNetwork.messages.contains(envelope),
    canReceiveGrant(localFor(i, t.worker), t),
    writeIntent(i, multiStore.intents.get(i), withLocal(sharedWorkers, i, t.worker,
      applyReceiveGrant(localFor(i, t.worker), t)), resources.get(i), multiNetwork.messages.exclude(Set(envelope))),
  }
  action multiCall(i: int, t: Token): bool = {
    val d = multiStore.intents.get(i)
    val local = localFor(i, t.worker)
    all {
      canCall(local, resources.get(i), t), d.use.bindings.get(t.exec) != NoHandler,
      (match d.use.bindings.get(t.exec) {
        | NoHandler => false | BoundHandler(b) => retryHandlerQualified(d.use, t.exec, b.handler, d.use.contractTime)
      }),
      writeIntent(i, { ...d, use: { ...d.use, launches: d.use.launches.append({ token: t,
        binding: d.use.bindings.get(t.exec), completion: d.ledger.attempts.get(t.exec).completion,
        authorizationStored: d.ledger.attempts.get(t.exec).grant == StartGrant(t), at: d.use.contractTime }) } },
        withLocal(sharedWorkers, i, t.worker, { ...local, started: local.started.union(Set(t.exec)) }),
        applyCall(resources.get(i), t, local.incarnation), multiNetwork.messages),
    }
  }
  action multiComplete(i: int, e: int, kind: ReportKind, value: int): bool = all {
    resources.get(i).effects.contains(e), resources.get(i).finished.get(e) == ResourceUnfinished,
    kind == Success or kind == Failure,
    writeIntent(i, multiStore.intents.get(i), sharedWorkers,
      applyExternalCompletionValue(resources.get(i), e, kind, value), multiNetwork.messages),
  }
  action multiReplace(i: int, old: int, fresh: int): bool = {
    val d = multiStore.intents.get(i)
    val valid = idempotencyValid(d.use, old, d.use.contractTime)
    all {
      multiStore.online, focused(d.use).request.definition.policy == RetryOnce,
      canReplaceWithEvidence(d.ledger, old, fresh, valid),
      writeIntent(i, { ...d, ledger: applyReplaceWithEvidence(d.ledger, old, fresh, valid),
        use: { ...d.use, retries: d.use.retries.append({ oldExec: old, newExec: fresh,
          binding: d.use.bindings.get(old), at: d.use.contractTime, repeatAccepted: ALLOW_REPEAT,
          before: d.ledger, definition: focused(d.use).request.definition, context: focused(d.use).context }) } },
        sharedWorkers, resources.get(i), multiNetwork.messages),
    }
  }
  action multiCancel(i: int): bool = {
    val d = multiStore.intents.get(i)
    val o: Outcome = { kind: OutcomeCancelled, exec: NoCurrent, value: 0 }
    all { multiStore.online, d.exists, canCommit(d.ledger, o),
      writeIntent(i, { ...d, ledger: applyCommit(d.ledger, o) }, sharedWorkers,
        resources.get(i), multiNetwork.messages) }
  }
}
