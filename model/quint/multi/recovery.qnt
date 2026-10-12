// Process failures are shared; each Intent's durable execution/evidence remains separate.
module multiIntentRecovery {
  import multiIntentReports.* from "./reports"
  export multiIntentReports.*

  action sharedWorkerCrash(w: int): bool = {
    val worker = sharedWorkers.get(w)
    val pool = sharedWorkers.set(w, { ...worker, alive: false,
      slots: INTENTS.mapBy(i => applyWorkerCrash(worker.slots.get(i))) })
    all {
      worker.alive, multiStore' = multiStore, sharedWorkers' = pool,
      resources' = resources, multiNetwork' = multiNetwork, multiClock' = multiClock,
      callerRounds' = callerRounds, agentLocals' = agentLocals,
      scopeObservation' = { target: 0, before: multiStore, after: multiStore,
        workersBefore: sharedWorkers, workersAfter: pool, resourcesBefore: resources,
        resourcesAfter: resources, workerSessionChanged: true, contractTimesChanged: false },
    }
  }
  action sharedWorkerRestart(w: int): bool = {
    val worker = sharedWorkers.get(w)
    val pool = sharedWorkers.set(w, { alive: true, incarnation: worker.incarnation + 1,
      slots: INTENTS.mapBy(i => applyWorkerRestart(worker.slots.get(i))) })
    all {
      not(worker.alive), worker.incarnation < MAX_INCARNATION,
      multiStore' = multiStore, sharedWorkers' = pool, resources' = resources,
      multiNetwork' = multiNetwork, multiClock' = multiClock,
      callerRounds' = callerRounds, agentLocals' = agentLocals,
      scopeObservation' = { target: 0, before: multiStore, after: multiStore,
        workersBefore: sharedWorkers, workersAfter: pool, resourcesBefore: resources,
        resourcesAfter: resources, workerSessionChanged: true, contractTimesChanged: false },
    }
  }
  action multiAvailability(online: bool): bool = all {
    multiStore.online != online,
    commitScope(0, { ...multiStore, online: online }, sharedWorkers, resources, multiNetwork),
  }
  action multiClockMove(n: int): bool = {
    val at = if (n > multiStore.contractTime) n else multiStore.contractTime
    val s = { ...multiStore, contractTime: at, intents: INTENTS.mapBy(i => {
      val d = multiStore.intents.get(i)
      { ...d, use: { ...d.use, contractTime: at } }
    }) }
    all {
      CLOCK_VALUES.contains(n), n != multiClock, multiStore' = s, multiClock' = n,
      sharedWorkers' = sharedWorkers, resources' = resources, multiNetwork' = multiNetwork,
      callerRounds' = callerRounds, agentLocals' = agentLocals,
      scopeObservation' = { target: 0, before: multiStore, after: s,
        workersBefore: sharedWorkers, workersAfter: sharedWorkers, resourcesBefore: resources,
        resourcesAfter: resources, workerSessionChanged: false, contractTimesChanged: true },
    }
  }
  action multiExpire(i: int, e: int): bool = {
    val d = multiStore.intents.get(i)
    all { multiStore.online, canExpire(d.ledger, e, multiClock),
      writeIntent(i, { ...d, ledger: applyExpire(d.ledger, e) }, sharedWorkers, resources.get(i), multiNetwork.messages) }
  }
  action multiRenew(i: int, t: Token): bool = {
    val d = multiStore.intents.get(i)
    all { multiStore.online, canRenew(d.ledger, t, multiClock),
      writeIntent(i, { ...d, ledger: applyRenew(d.ledger, t, multiClock) }, sharedWorkers, resources.get(i), multiNetwork.messages) }
  }
  action multiResendGrant(i: int, t: Token): bool = all {
    multiStore.online, messagesFor(i).contains(StartRequest(t)), not(messagesFor(i).contains(StartReply(t))),
    multiStore.intents.get(i).ledger.attempts.get(t.exec).grant == StartGrant(t),
    writeIntent(i, multiStore.intents.get(i), sharedWorkers, resources.get(i),
      multiNetwork.messages.exclude(Set(scoped(i, StartRequest(t)))).union(Set(scoped(i, StartReply(t))))),
  }
  action multiLoseMessage(envelope: ScopedMessage): bool = all {
    multiNetwork.messages.contains(envelope),
    commitScope(0, multiStore, sharedWorkers, resources,
      { ...multiNetwork, messages: multiNetwork.messages.exclude(Set(envelope)) }),
  }
  action multiLoseSubmissionReply(a: int, r: SubmissionReply): bool = all {
    multiNetwork.replies.contains({ agent: a, reply: r }),
    commitScope(0, multiStore, sharedWorkers, resources,
      { ...multiNetwork, replies: multiNetwork.replies.exclude(Set({ agent: a, reply: r })) }),
  }
}
