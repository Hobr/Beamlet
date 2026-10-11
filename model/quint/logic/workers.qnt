// Worker-local guards and pure updates, including external invocation witnesses.
module coreLogicWorkers {
  import coreBaseState.* from "../base/state"
  export coreBaseState.*

  pure def canRequest(local: LocalState, messages: Set[Message], t: Token): bool =
    local.alive and local.incarnation == t.incarnation and local.leases.contains(t)
      and not(messages.contains(StartRequest(t)))

  pure def canReceiveGrant(local: LocalState, t: Token): bool =
    local.alive and local.incarnation == t.incarnation and not(local.grants.contains(t))

  pure def applyReceiveGrant(local: LocalState, t: Token): LocalState =
    { ...local, grants: local.grants.union(Set(t)) }

  pure def canCall(local: LocalState, x: ExternalState, t: Token): bool =
    local.alive and local.incarnation == t.incarnation and local.grants.contains(t)
      and not(local.started.contains(t.exec)) and not(x.noFuture.contains(t.exec))

  pure def applyCall(x: ExternalState, t: Token, inc: int): ExternalState =
    { ...x, invocations: x.invocations.append({ token: t, incarnationAtCall: inc }),
      effects: x.effects.union(Set(t.exec)) }

  pure def applyExternalCompletion(x: ExternalState, e: int, kind: ReportKind): ExternalState =
    { ...x, finished: x.finished.set(e, if (kind == Success) ResourceSucceeded else ResourceFailed) }

  pure def pendingReport(t: Token): Report =
    { id: 1, exec: t.exec, kind: Pending, origin: ByWorker(t) }

  pure def canPublish(local: LocalState, t: Token, r: Report): bool =
    local.alive and local.incarnation == t.incarnation and local.started.contains(t.exec)
      and not(local.reports.contains(r))

  pure def applyPublish(local: LocalState, r: Report): LocalState =
    { ...local, reports: local.reports.union(Set(r)) }

  pure def completionReport(x: ExternalState, t: Token): Report =
    { id: 2, exec: t.exec, kind: if (x.finished.get(t.exec) == ResourceSucceeded) Success else Failure,
      origin: ByWorker(t) }

  pure def applyWorkerCrash(local: LocalState): LocalState =
    { ...initialWorker, alive: false, incarnation: local.incarnation }

  pure def applyWorkerRestart(local: LocalState): LocalState =
    { ...initialWorker, incarnation: local.incarnation + 1 }

  pure def applyReceipt(local: LocalState, r: Report): LocalState =
    { ...local, receipts: local.receipts.union(Set(r)) }
}
