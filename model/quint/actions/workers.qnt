// Frame-complete Worker and external-resource transitions.
module coreActionsWorkers {
  import coreLogicWorkers.* from "../logic/workers"
  export coreLogicWorkers.*

  action requestStart(t: Token): bool = all {
    canRequest(workers.get(t.worker), network, t),
    authority' = authority, workers' = workers,
    network' = network.union(Set(StartRequest(t))),
    external' = external, clock' = clock,
  }

  action receiveGrant(t: Token): bool = all {
    network.contains(StartReply(t)), canReceiveGrant(workers.get(t.worker), t),
    authority' = authority,
    workers' = workers.set(t.worker, applyReceiveGrant(workers.get(t.worker), t)),
    network' = network.exclude(Set(StartReply(t))),
    external' = { ...external, marks: external.marks.union(Set("grantReceived")) },
    clock' = clock,
  }

  action resendGrant(t: Token): bool = all {
    authority.online, network.contains(StartRequest(t)),
    authority.durable.attempts.get(t.exec).grant == StartGrant(t),
    not(network.contains(StartReply(t))),
    authority' = authority, workers' = workers,
    network' = network.exclude(Set(StartRequest(t))).union(Set(StartReply(t))),
    external' = { ...external, marks: external.marks.union(Set("replyResent")) },
    clock' = clock,
  }

  action callExternal(t: Token): bool = {
    val local = workers.get(t.worker)
    all {
      canCall(local, external, t),
      authority' = authority,
      workers' = workers.set(t.worker, { ...local, started: local.started.union(Set(t.exec)) }),
      network' = network, external' = applyCall(external, t, local.incarnation), clock' = clock,
    }
  }

  action completeAtResource(e: int, kind: ReportKind): bool = all {
    external.effects.contains(e), external.finished.get(e) == ResourceUnfinished,
    kind == Success or kind == Failure,
    authority' = authority, workers' = workers, network' = network,
    external' = applyExternalCompletion(external, e, kind), clock' = clock,
  }

  action publishPending(t: Token): bool = {
    val r = pendingReport(t)
    all {
      // Pending is the handler's delayed start response, not omniscient resource knowledge.
      canPublish(workers.get(t.worker), t, r),
      authority' = authority, workers' = workers.set(t.worker, applyPublish(workers.get(t.worker), r)),
      network' = network.union(Set(ResultReport(r))),
      external' = { ...external, emitted: external.emitted.union(Set(r)) }, clock' = clock,
    }
  }

  action publishCompletion(t: Token): bool = {
    val r = completionReport(external, t)
    all {
      external.finished.get(t.exec) != ResourceUnfinished,
      canPublish(workers.get(t.worker), t, r),
      authority' = authority, workers' = workers.set(t.worker, applyPublish(workers.get(t.worker), r)),
      network' = network.union(Set(ResultReport(r))),
      external' = { ...external, emitted: external.emitted.union(Set(r)) }, clock' = clock,
    }
  }

  action crashWorker(w: int): bool = all {
    workers.get(w).alive,
    authority' = authority, workers' = workers.set(w, applyWorkerCrash(workers.get(w))),
    network' = network,
    external' = { ...external, marks: external.marks.union(Set("workerCrashed")) }, clock' = clock,
  }

  action restartWorker(w: int): bool = all {
    not(workers.get(w).alive), workers.get(w).incarnation < MAX_INCARNATION,
    authority' = authority, workers' = workers.set(w, applyWorkerRestart(workers.get(w))),
    network' = network,
    external' = { ...external, marks: external.marks.union(Set("workerRestarted")) }, clock' = clock,
  }

  action discardDuplicateGrant(t: Token): bool = all {
    network.contains(StartReply(t)), workers.get(t.worker).alive,
    workers.get(t.worker).incarnation == t.incarnation, workers.get(t.worker).grants.contains(t),
    authority' = authority, workers' = workers, network' = network.exclude(Set(StartReply(t))),
    external' = { ...external, marks: external.marks.union(Set("duplicateGrant")) }, clock' = clock,
  }

  action discardOldGrant(t: Token): bool = all {
    network.contains(StartReply(t)), workers.get(t.worker).alive,
    workers.get(t.worker).incarnation != t.incarnation,
    authority' = authority, workers' = workers, network' = network.exclude(Set(StartReply(t))),
    external' = { ...external, marks: external.marks.union(Set("oldGrantRejected")) }, clock' = clock,
  }
}
