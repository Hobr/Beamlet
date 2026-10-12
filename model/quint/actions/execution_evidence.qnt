// Frame-complete report delivery, query, receipt and retransmission transitions.
module executionActionsEvidence {
  import executionOutcomeLogic.* from "../logic/execution_outcomes"
  export executionOutcomeLogic.*
  import executionRecoveryLogic.* from "../logic/execution_recovery"
  export executionRecoveryLogic.*
  import executionWorkerLogic.* from "../logic/execution_workers"
  export executionWorkerLogic.*

  // 保存证据,可能的成功终结与持久化回执原子形成;Closed 或旧租约不妨碍合格证据入账.
  // 保留在途报告以允许重复交付;duplicate 分支只补发回执,不重复记账.
  action receiveReport(r: Report): bool = all {
    authority.online, network.contains(ResultReport(r)),
    reportSourceValid(authority.durable, r), not(authority.durable.reports.contains(r)),
    authority' = { ...authority, durable: recordAndMaybeCommit(authority.durable, r) },
    workers' = workers, network' = network.union(Set(StoredReceipt(r))),
    external' = if (isLate(authority.durable, r))
      { ...external, marks: external.marks.union(Set("lateReport")) } else external,
    clock' = clock,
  }

  action receiveAnyReport = {
    val candidates = network.filter(m => match m { | ResultReport(_) => true | _ => false })
    all {
      candidates.size() > 0,
      nondet m = candidates.oneOf()
      match m { | ResultReport(r) => receiveReport(r) | _ => invalidMessageVariant },
    }
  }

  // 查询只发送受信证据,不直接改变 Authority;与正常报告共享接收/保存路径.
  action queryExternal(e: int, id: int): bool = {
    val r = queryReport(external, e, id)
    all {
      authority.durable.attempts.get(e).grant != NoGrant,
      freshQueryId(external, e, id),
      authority' = authority, workers' = workers,
      network' = network.union(Set(ResultReport(r))),
      external' = { ...external, emitted: external.emitted.union(Set(r)),
        marks: external.marks.union(Set("queried")) },
      clock' = clock,
    }
  }

  // 资源原子地建立"未发生且未来不再发生"事实后发 NotExecuted;普通 NotFound 没有此能力.
  action fenceAtResource(e: int, id: int): bool = {
    val r: Report = { id: id, exec: e, kind: NotExecuted, value: 0, origin: ByQuery }
    all {
      CAN_FENCE, authority.durable.attempts.get(e).grant != NoGrant,
      not(external.effects.contains(e)), not(external.noFuture.contains(e)),
      freshQueryId(external, e, id),
      authority' = authority, workers' = workers,
      network' = network.union(Set(ResultReport(r))),
      external' = { ...external, noFuture: external.noFuture.union(Set(e)),
        emitted: external.emitted.union(Set(r)) },
      clock' = clock,
    }
  }

  action receiveReceipt(r: Report): bool = match r.origin {
    | ByWorker(t) => all {
        network.contains(StoredReceipt(r)), workers.get(t.worker).alive,
        workers.get(t.worker).incarnation == t.incarnation,
        workers.get(t.worker).reports.contains(r), not(workers.get(t.worker).receipts.contains(r)),
        authority' = authority,
        workers' = workers.set(t.worker, applyReceipt(workers.get(t.worker), r)),
        network' = network.exclude(Set(StoredReceipt(r))),
        external' = { ...external, marks: external.marks.union(Set("receiptReceived")) }, clock' = clock,
      }
    | ByQuery => invalidMessageVariant
    | ByCallback(_) => invalidMessageVariant
  }

  action receiveAnyReceipt = {
    val candidates = network.filter(m => match m { | StoredReceipt(_) => true | _ => false })
    all {
      candidates.size() > 0,
      nondet m = candidates.oneOf()
      match m { | StoredReceipt(r) => receiveReceipt(r) | _ => invalidMessageVariant },
    }
  }

  // 只有已保存的完全相同报告可直接确认;同身份不同正文必须保留并检测冲突.
  action acknowledgeDuplicate(r: Report): bool = all {
    authority.online, network.contains(ResultReport(r)), authority.durable.reports.contains(r),
    not(network.contains(StoredReceipt(r))),
    authority' = authority, workers' = workers,
    network' = network.exclude(Set(ResultReport(r))).union(Set(StoredReceipt(r))),
    external' = { ...external, marks: external.marks.union(Set("duplicateReport")) }, clock' = clock,
  }

  action acknowledgeAnyDuplicate = {
    val candidates = network.filter(m => match m { | ResultReport(_) => true | _ => false })
    all {
      candidates.size() > 0,
      nondet m = candidates.oneOf()
      match m { | ResultReport(r) => acknowledgeDuplicate(r) | _ => invalidMessageVariant },
    }
  }

  // Worker 仅在尚未获持久化回执时重投本地报告;丢回执不应造成重复 EvidenceStored 审计.
  action resendReport(r: Report): bool = match r.origin {
    | ByWorker(t) => all {
        workers.get(t.worker).alive, workers.get(t.worker).incarnation == t.incarnation,
        workers.get(t.worker).reports.contains(r), not(workers.get(t.worker).receipts.contains(r)),
        not(network.contains(ResultReport(r))),
        authority' = authority, workers' = workers, network' = network.union(Set(ResultReport(r))),
        external' = { ...external, marks: external.marks.union(Set("reportResent")) }, clock' = clock,
      }
    | ByQuery => invalidMessageVariant
    | ByCallback(_) => invalidMessageVariant
  }

  action resendAnyReport = {
    val candidates: Set[Report] = WORKERS.fold(Set(), (acc, w) => acc.union(workers.get(w).reports))
    all {
      candidates.size() > 0,
      nondet r = candidates.oneOf()
      resendReport(r),
    }
  }
}
