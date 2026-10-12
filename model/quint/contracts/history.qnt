module historyProtocol {
  import historyState.* from "./history_state"
  export historyState.*
  pure def historyNext(l: Ledger, cmd: HistoryCommand, at: int, inc: int): Ledger = match cmd {
    | HistoryCreate => applyCreate(l, 1)
    | HistoryClaim => applyClaim(l, 1, 1, inc, at)
    | HistoryAuthorize => applyAuthorize(l, tokenFor(l, 1), at)
    | HistoryReport(r) => recordAndMaybeCommit(l, r)
  }
  pure def historyDelta(before: Ledger, after: Ledger): List[Audit] =
    after.history.foldl({ position: 0, events: List() }, (acc, event) => {
      position: acc.position + 1,
      events: if (acc.position >= before.history.length()) acc.events.append(event) else acc.events,
    }).events
  pure def historyAllowed(l: Ledger, messages: Set[Message], locals: int -> LocalState,
    now: int, cmd: HistoryCommand): bool = match cmd {
    | HistoryCreate => canCreate(l, 1)
    | HistoryClaim => locals.get(1).alive and canClaim(l, 1, now)
    | HistoryAuthorize => messages.contains(StartRequest(tokenFor(l, 1))) and canAuthorize(l, tokenFor(l, 1), now)
    | HistoryReport(r) => messages.contains(ResultReport(r)) and reportSourceValid(l, r)
      and not(l.reports.contains(r))
  }
  action prepareHistory(actor: int, cmd: HistoryCommand): bool = all {
    authority.online, historyDrafts.get(actor) == NoHistoryDraft, historyStore.groups.length() < 6,
    historyAllowed(authority.durable, network, workers, clock, cmd), authority' = authority, workers' = workers, network' = network,
    external' = external, clock' = clock, historyStore' = historyStore,
    historyDrafts' = historyDrafts.set(actor, HistoryDrafted({ base: authority.durable,
      updated: historyNext(authority.durable, cmd, clock, workers.get(1).incarnation), command: cmd, at: clock })),
  }
  action commitHistory(actor: int): bool = match historyDrafts.get(actor) {
    | NoHistoryDraft => all { false, authority' = authority, workers' = workers, network' = network,
        external' = external, clock' = clock, holdHistory }
    | HistoryDrafted(d) => {
        val updated = historyNext(authority.durable, d.command, clock, workers.get(1).incarnation)
        val group: HistoryGroup = { sequence: historyStore.groups.length() + 1, actor: actor, at: clock,
          version: 1, command: d.command, before: authority.durable, after: updated,
          events: historyDelta(authority.durable, updated) }
        all {
          authority.online, d.base == authority.durable, d.at == clock, d.updated == updated,
          historyStore.groups.length() < 6, historyAllowed(authority.durable, network, workers, clock, d.command),
          authority' = { ...authority, durable: updated },
          historyStore' = { ...historyStore, groups: historyStore.groups.append(group),
            committed: historyStore.committed.append(group) },
          historyDrafts' = historyDrafts.set(actor, NoHistoryDraft),
          workers' = if (d.command == HistoryClaim) workers.set(1, { ...workers.get(1),
            leases: workers.get(1).leases.union(Set(tokenFor(updated, 1))) }) else workers,
          network' = match d.command {
            | HistoryAuthorize => network.exclude(Set(StartRequest(tokenFor(updated, 1))))
                .union(Set(StartReply(tokenFor(updated, 1))))
            | HistoryReport(r) => network.union(Set(StoredReceipt(r)))
            | _ => network
          }, external' = external, clock' = clock,
        }
      }
  }
  action rollbackHistory(actor: int): bool = all {
    historyDrafts.get(actor) != NoHistoryDraft,
    authority' = authority, workers' = workers, network' = network, external' = external, clock' = clock,
    historyDrafts' = historyDrafts.set(actor, NoHistoryDraft),
    historyStore' = { ...historyStore, rollbacks: historyStore.rollbacks + 1 },
  }
  action crashHistoryCoordinator = all {
    crashCoordinator, historyDrafts' = Set(1, 2).mapBy(_ => NoHistoryDraft),
    historyStore' = { ...historyStore, rollbacks: historyStore.rollbacks +
      Set(1, 2).filter(a => historyDrafts.get(a) != NoHistoryDraft).size() },
  }
  action historyDuplicate(r: Report): bool = all {
    acknowledgeDuplicate(r), historyDrafts' = historyDrafts,
    historyStore' = { ...historyStore, duplicateReads: historyStore.duplicateReads + 1 },
  }
  val historyGroupsSound = historyStore.groups == historyStore.committed
    and historyStore.groups.indices().forall(index => {
      val g = historyStore.groups.nth(index)
      g.sequence == index + 1 and Set(1, 2).contains(g.actor) and g.version == 1
        and g.events == historyDelta(g.before, g.after)
        and g.before == (if (index == 0) initialLedger else historyStore.groups.nth(index - 1).after)
        and g.after.history == g.before.history.concat(g.events)
    })
  val historyStateAtomic = authority.durable == (if (historyStore.groups.length() == 0) initialLedger
      else historyStore.groups.nth(historyStore.groups.length() - 1).after)
    and authority.durable.history == historyStore.groups.foldl(List(), (events, g) => events.concat(g.events))
  val historyCommandsSound = historyStore.groups.indices().forall(ix => {
    val g = historyStore.groups.nth(ix)
    g.events.length() > 0 and (match g.command {
      | HistoryReport(r) => not(g.before.reports.contains(r)) and g.after.reports.contains(r)
      | _ => true
    })
  })
  val historySafety = safety and historyGroupsSound and historyStateAtomic and historyCommandsSound
  val historyCommittedWitness = historyStore.groups.length() > 0
  val historyOutcomeWitness = authority.durable.outcomes.length() == 1
  val historyRollbackWitness = historyStore.rollbacks > 0
  val historyDuplicateWitness = historyStore.duplicateReads > 0
  pure val historyToken: Token = { exec: 1, worker: 1, incarnation: 1, generation: 1 }
  action historyCommand(actor: int, cmd: HistoryCommand): bool = prepareHistory(actor, cmd).then(commitHistory(actor))
  action historyPreparedInit = historyInit.then(historyCommand(1, HistoryCreate)).then(historyCommand(1, HistoryClaim))
    .then(all { requestStart(historyToken), holdHistory })
  action historyRunningInit = historyPreparedInit.then(historyCommand(1, HistoryAuthorize))
    .then(all { receiveGrant(historyToken), holdHistory }).then(all { callExternal(historyToken), holdHistory })
  action historyHealthyStep = {
    nondet actor = Set(1, 2).oneOf()
    // An unclaimed lease has worker=0; scheduler candidates must name a real Worker.
    val t = if (authority.durable.attempts.get(1).lease.claimed) tokenFor(authority.durable, 1) else historyToken
    val r: Report = { id: 2, exec: 1, kind: Success, value: 0, origin: ByWorker(t) }
    nondet cmd = Set(HistoryCreate, HistoryClaim, HistoryAuthorize, HistoryReport(r)).oneOf()
    any { prepareHistory(actor, cmd), commitHistory(actor), historyDuplicate(r),
      all { any { requestStart(t), receiveGrant(t), callExternal(t), completeAtResource(1, Success),
        publishCompletion(t), loseMessage(StoredReceipt(r)) }, holdHistory } }
  }
  action historyStep = {
    nondet actor = Set(1, 2).oneOf()
    any { historyHealthyStep, rollbackHistory(actor), crashHistoryCoordinator,
      all { any { restartCoordinator, moveClock }, holdHistory } }
  }
}
