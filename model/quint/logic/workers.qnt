// State-specific transport types; Worker/resource computations are shared.
module coreLogicWorkers {
  import coreBaseState.* from "../base/state"
  export coreBaseState.*
  import executionWorkerValues as shared from "./execution_worker_values"

  pure def canRequest(local: LocalState, messages: Set[Message], t: Token): bool =
    shared::requestQualified(local, t, messages.contains(StartRequest(t)))

  pure def canReceiveGrant(local: LocalState, t: Token): bool =
    shared::canReceiveGrant(local, t)

  pure def applyReceiveGrant(local: LocalState, t: Token): LocalState =
    shared::applyReceiveGrant(local, t)

  pure def canCall(local: LocalState, x: ExternalState, t: Token): bool =
    shared::canCall(local, x, t)

  pure def applyCall(x: ExternalState, t: Token, inc: int): ExternalState =
    shared::applyCall(x, t, inc)

  pure def applyExternalCompletionValue(x: ExternalState, e: int, kind: ReportKind, value: int): ExternalState =
    shared::applyExternalCompletionValue(x, e, kind, value)

  pure def applyExternalCompletion(x: ExternalState, e: int, kind: ReportKind): ExternalState =
    shared::applyExternalCompletion(x, e, kind)

  pure def pendingReport(t: Token): Report =
    shared::pendingReport(t)

  pure def canPublish(local: LocalState, t: Token, r: Report): bool =
    shared::canPublish(local, t, r)

  pure def applyPublish(local: LocalState, r: Report): LocalState =
    shared::applyPublish(local, r)

  pure def completionReport(x: ExternalState, t: Token): Report =
    shared::completionReport(x, t)

  pure def applyWorkerCrash(local: LocalState): LocalState =
    shared::applyWorkerCrash(local)

  pure def applyWorkerRestart(local: LocalState): LocalState =
    shared::applyWorkerRestart(local)

  pure def applyReceipt(local: LocalState, r: Report): LocalState =
    shared::applyReceipt(local, r)
}
