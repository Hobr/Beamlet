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

  // 合规 Worker 凭已收到的持久许可调用,不重新读取 Authority 的 phase,current 或墙钟.
  // 所以到期/取消后仍可能调用;noFuture 表示资源侧已永久排除该尝试的可信协议前提.
  pure def canCall(local: LocalState, x: ExternalState, t: Token): bool =
    local.alive and local.incarnation == t.incarnation and local.grants.contains(t)
      and not(local.started.contains(t.exec)) and not(x.noFuture.contains(t.exec))

  // effects 只见证调用可能产生效果,不代表成功完成;Failure 也可能留下部分业务效果.
  pure def applyCall(x: ExternalState, t: Token, inc: int): ExternalState =
    { ...x, invocations: x.invocations.append({ token: t, incarnationAtCall: inc }),
      effects: x.effects.union(Set(t.exec)) }

  pure def applyExternalCompletionValue(x: ExternalState, e: int, kind: ReportKind, value: int): ExternalState =
    { ...x, finished: x.finished.set(e, if (kind == Success) ResourceSucceeded else ResourceFailed),
      values: x.values.set(e, value) }

  pure def applyExternalCompletion(x: ExternalState, e: int, kind: ReportKind): ExternalState =
    applyExternalCompletionValue(x, e, kind, 0)

  // 固定 1/2 仅是同一 Worker token 来源内 Pending/完成报告的有界身份,不是产品 ID 方案.
  pure def pendingReport(t: Token): Report =
    { id: 1, exec: t.exec, kind: Pending, value: 0, origin: ByWorker(t) }

  pure def canPublish(local: LocalState, t: Token, r: Report): bool =
    local.alive and local.incarnation == t.incarnation and local.started.contains(t.exec)
      and not(local.reports.contains(r))

  pure def applyPublish(local: LocalState, r: Report): LocalState =
    { ...local, reports: local.reports.union(Set(r)) }

  pure def completionReport(x: ExternalState, t: Token): Report =
    { id: 2, exec: t.exec, kind: if (x.finished.get(t.exec) == ResourceSucceeded) Success else Failure,
      value: x.values.get(t.exec), origin: ByWorker(t) }

  // 崩溃清空所有局部许可,已调用集合和报告;重启递增 incarnation,不能继承旧代许可.
  pure def applyWorkerCrash(local: LocalState): LocalState =
    { ...initialWorker, alive: false, incarnation: local.incarnation }

  pure def applyWorkerRestart(local: LocalState): LocalState =
    { ...initialWorker, incarnation: local.incarnation + 1 }

  pure def applyReceipt(local: LocalState, r: Report): LocalState =
    { ...local, receipts: local.receipts.union(Set(r)) }
}
