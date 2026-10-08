// A new core abstraction, not an equivalent encoding of the detailed suite.
module core {
  const RUNS: Set[int]
  const QUEUE_LIMIT: int
  type Life = Open | Finished | Failed
  type Kind = External | Continuation | Uncertainty | Reply
  type Disposition = PendingInput | Applied | Obsolete | Unprocessed
  type Choice = Invoke | Wait | Continue | Finish | Fault
  type Actual = NoActual | Succeeded | FailedCall | NotExecuted
  type Knowledge = Unused | Admitted | Unknown | Recorded
  // Authority-observed meaning, separate from physical completion and phase tags.
  type Evidence = NoEvidence | LostContact | SuccessEvidence | FailureEvidence | NonexecutionEvidence
  type Result = NoResult | Ok | Error
  type Phase = Dormant | Executing | Uncertain | Outcome | Consumed
  type Boundary = { stable: bool, app: int, revision: int, ready: bool, life: Life, result: Result }
  type Control = { exists: bool, active: bool, life: Life, epoch: int, revision: int, app: int, cursor: int, ready: bool, parent: int, origin: Boundary }
  type Effect = { exists: bool, token: int, retryable: bool, conclusive: bool, phase: Phase, result: Result, permit: int, issued: int }
  type Attempt = { knowledge: Knowledge, evidence: Evidence, owner: int, entries: int, actor: int, actual: Actual, permit: int }
  type Owner = { alive: bool, reachable: bool }
  type Input = { kind: Kind, revision: int, disposition: Disposition }
  type Proposal = { valid: bool, epoch: int, revision: int, cursor: int, choice: Choice, retryable: bool, conclusive: bool }
  type Event = Init | Evaluate | Commit | Fail | Dispose | Admit | Enter | Duplicate | Complete | Record | Lose | Repeat | Settle | ControlChange | Takeover | Disconnect | Reconnect | Availability | InputArrival | Fork
  type Prior = { event: Event, runId: int, attempt: int, owner: int, source: int, control: Control, effect: Effect, at: Attempt, other: Attempt, physicalOwner: Owner, proposal: Proposal, inbox: List[Input], boundary: Boundary, sourceBoundaries: List[Boundary], writes: bool }
  pure val ATTEMPTS = Set(0, 1)
  pure val OWNERS = Set(0, 1)
  pure val IDS = RUNS.map(r => ATTEMPTS.map(a => (r, a))).flatten()
  pure val emptyBoundary: Boundary = {stable: false, app: 0, revision: 0, ready: false, life: Open, result: NoResult}
  pure def emptyControl(present: bool): Control = {exists: present, active: true, life: Open, epoch: 0, revision: 0, app: 0, cursor: 0, ready: false, parent: -1, origin: emptyBoundary}
  pure def emptyEffect(r: int): Effect = {exists: false, token: r, retryable: false, conclusive: false, phase: Dormant, result: NoResult, permit: 0, issued: 0}
  pure val emptyAttempt: Attempt = {knowledge: Unused, evidence: NoEvidence, owner: -1, entries: 0, actor: -1, actual: NoActual, permit: 0}
  pure val emptyProposal: Proposal = {valid: false, epoch: 0, revision: 0, cursor: 0, choice: Wait, retryable: false, conclusive: false}
  pure def input(kind: Kind, revision: int): Input = {kind: kind, revision: revision, disposition: PendingInput}
  var control: int -> Control
  var effect: int -> Effect
  var attempt: (int, int) -> Attempt
  var owner: int -> Owner
  var inbox: int -> List[Input]
  var held: int -> Proposal
  var boundaries: int -> List[Boundary]
  var writes: bool
  var prior: Prior
  pure val initialPrior: Prior = {event: Init, runId: 0, attempt: 0, owner: 0, source: 0, control: emptyControl(true), effect: emptyEffect(0), at: emptyAttempt, other: emptyAttempt, physicalOwner: {alive: true, reachable: true}, proposal: emptyProposal, inbox: List(input(External, 0)), boundary: {...emptyBoundary, stable: true}, sourceBoundaries: List({...emptyBoundary, stable: true}), writes: true}
  action init = all {
    control' = RUNS.mapBy(r => emptyControl(r == 0)), effect' = RUNS.mapBy(r => emptyEffect(r)),
    attempt' = IDS.mapBy(_ => emptyAttempt), owner' = OWNERS.mapBy(_ => {alive: true, reachable: true}),
    inbox' = RUNS.mapBy(r => if (r == 0) List(input(External, 0)) else List()), held' = RUNS.mapBy(_ => emptyProposal),
    boundaries' = RUNS.mapBy(r => List({...emptyBoundary, stable: r == 0})), writes' = true, prior' = initialPrior,
  }
  action note(event: Event, r: int, a: int, o: int, src: int, b: Boundary): bool = prior' = {event: event, runId: r, attempt: a, owner: o, source: src, control: control.get(r), effect: effect.get(r), at: attempt.get((r, a)), other: attempt.get((r, 1 - a)), physicalOwner: owner.get(o), proposal: held.get(r), inbox: inbox.get(r), boundary: b, sourceBoundaries: boundaries.get(src), writes: writes}
  action noteRun(event: Event, r: int): bool = note(event, r, 0, 0, r, emptyBoundary)
  pure def active(c: Control): bool = c.exists and c.active and c.life == Open
  val readyHead = RUNS.exists(r => active(control.get(r)) and control.get(r).cursor < inbox.get(r).length())
  def queueHead(r: int): Input = inbox.get(r).nth(control.get(r).cursor)
  def obsolete(r: int): bool = (queueHead(r).kind == Continuation and queueHead(r).revision != control.get(r).revision) or (queueHead(r).kind == Uncertainty and effect.get(r).result != NoResult)
  def canEvaluate(r: int, choice: Choice): bool = active(control.get(r)) and control.get(r).cursor < inbox.get(r).length() and not(obsolete(r)) and (choice != Invoke or not(effect.get(r).exists))
  action evaluate(r: int, choice: Choice, retryable: bool, conclusive: bool): bool = all {
    canEvaluate(r, choice), noteRun(Evaluate, r),
    held' = held.set(r, {valid: true, epoch: control.get(r).epoch, revision: control.get(r).revision, cursor: control.get(r).cursor, choice: choice, retryable: retryable, conclusive: conclusive}), attempt' = attempt, boundaries' = boundaries, control' = control, effect' = effect, inbox' = inbox, owner' = owner, writes' = writes}
  def current(r: int): bool = {
    val c = control.get(r)
    val p = held.get(r)
    p.valid and active(c) and c.cursor < inbox.get(r).length() and not(obsolete(r)) and p.epoch == c.epoch and p.revision == c.revision and p.cursor == c.cursor
  }
  def canCommit(r: int): bool = {
    val p = held.get(r)
    val e = effect.get(r)
    current(r) and writes and p.choice != Fault and
    (p.choice != Invoke or not(e.exists)) and
    (p.choice != Continue or inbox.get(r).length() < QUEUE_LIMIT) and
    (p.choice != Finish or not(e.exists) or e.phase == Consumed or (queueHead(r).kind == Reply and e.result != NoResult))
  }
  pure def boundaryValue(c: Control, e: Effect, q: List[Input]): Boundary = {
    {stable: c.life != Failed and (not(e.exists) or e.phase == Consumed) and q.indices().forall(i => i < c.cursor or (q.nth(i).kind != Reply and q.nth(i).kind != Uncertainty)), app: c.app, revision: c.revision, ready: c.ready, life: c.life, result: e.result}
  }
  action commitUpdate(r: int): bool = {
    val c = control.get(r)
    val p = held.get(r)
    val old = effect.get(r)
    val consumed = if (queueHead(r).kind == Reply) {...old, phase: Consumed} else old
    val e = if (p.choice == Invoke) {...emptyEffect(r), exists: true, retryable: p.retryable, conclusive: p.conclusive} else consumed
    val q = inbox.get(r).replaceAt(c.cursor, {...queueHead(r), disposition: Applied})
    val continued = if (p.choice == Continue) q.append(input(Continuation, c.revision + 1)) else q
    val done = if (p.choice == Finish) continued.foldl(List(), (acc, i) => acc.append(if (i.disposition == PendingInput) {...i, disposition: Unprocessed} else i)) else continued
    val updated = {...c, app: c.app + 1, revision: c.revision + 1, cursor: if (p.choice == Finish) done.length() else c.cursor + 1, ready: p.choice == Continue, life: if (p.choice == Finish) Finished else c.life}
    all {noteRun(Commit, r), control' = control.set(r, updated), effect' = effect.set(r, e), inbox' = inbox.set(r, done), held' = held.set(r, {...p, valid: false}), boundaries' = boundaries.set(r, boundaries.get(r).append(boundaryValue(updated, e, done))), attempt' = attempt, owner' = owner, writes' = writes}
  }
  action commit(r: int): bool = all {canCommit(r), commitUpdate(r)}
  action failRun(r: int): bool = all {writes, current(r), held.get(r).choice == Fault, noteRun(Fail, r), control' = control.setBy(r, c => {...c, life: Failed, ready: false, cursor: inbox.get(r).length()}), inbox' = inbox.setBy(r, q => q.foldl(List(), (acc, i) => acc.append(if (i.disposition == PendingInput) {...i, disposition: Unprocessed} else i))), attempt' = attempt, boundaries' = boundaries, effect' = effect, held' = held, owner' = owner, writes' = writes}
  action dispose(r: int): bool = all {writes, active(control.get(r)), control.get(r).cursor < inbox.get(r).length(), obsolete(r), noteRun(Dispose, r), inbox' = inbox.setBy(r, q => q.replaceAt(control.get(r).cursor, {...queueHead(r), disposition: Obsolete})), control' = control.setBy(r, c => {...c, cursor: c.cursor + 1}), attempt' = attempt, boundaries' = boundaries, effect' = effect, held' = held, owner' = owner, writes' = writes}
  def pendingAttempt(r: int): bool = ATTEMPTS.exists(a => attempt.get((r, a)).knowledge == Admitted)
  pure def unresolved(at: Attempt, e: Effect): bool = at.knowledge == Admitted or at.evidence == LostContact or (at.evidence == FailureEvidence and not(e.conclusive))
  pure def observed(actual: Actual): Evidence = if (actual == Succeeded) SuccessEvidence else if (actual == FailedCall) FailureEvidence else NonexecutionEvidence
  // One normal reducer. Result choice and phase use committed observation meaning;
  // physical completion alone does not resolve authority uncertainty.
  pure def reduce(e: Effect, at: Attempt, other: Attempt): Effect = {
    val selected = e.result == NoResult and (at.evidence == SuccessEvidence or other.evidence == SuccessEvidence or (e.conclusive and (at.evidence == FailureEvidence or other.evidence == FailureEvidence) and not(unresolved(at, e)) and not(unresolved(other, e))))
    val uncertain = unresolved(at, e) or unresolved(other, e)
    {...e, result: if (selected) (if (at.evidence == SuccessEvidence or other.evidence == SuccessEvidence) Ok else Error) else e.result,
      phase: if (selected) Outcome else if (e.result != NoResult) e.phase else if (other.knowledge == Admitted) Executing else if (uncertain) Uncertain else Dormant}
  }
  def uncertainOwner(r: int, o: int): bool = ATTEMPTS.exists(a => {val at = attempt.get((r, a)) at.owner == o and unresolved(at, effect.get(r))})
  def canAdmit(r: int, a: int, o: int): bool = {
    val e = effect.get(r)
    writes and active(control.get(r)) and e.exists and e.result == NoResult and not(pendingAttempt(r)) and attempt.get((r, a)).knowledge == Unused and owner.get(o).alive and not(uncertainOwner(r, o)) and (e.phase != Uncertain or e.retryable or e.permit > 0)
  }
  action admitUpdate(r: int, a: int, o: int): bool = all {note(Admit, r, a, o, r, emptyBoundary), attempt' = attempt.set((r, a), {...emptyAttempt, knowledge: Admitted, owner: o, permit: effect.get(r).permit}), effect' = effect.setBy(r, e => {...e, phase: Executing, permit: 0}), boundaries' = boundaries, control' = control, held' = held, inbox' = inbox, owner' = owner, writes' = writes}
  action admit(r: int, a: int, o: int): bool = all {canAdmit(r, a, o), admitUpdate(r, a, o)}
  action enterUpdate(r: int, a: int, o: int): bool = all {note(Enter, r, a, o, r, emptyBoundary), attempt' = attempt.setBy((r, a), at => {...at, entries: at.entries + 1, actor: o}), boundaries' = boundaries, control' = control, effect' = effect, held' = held, inbox' = inbox, owner' = owner, writes' = writes}
  action enter(r: int, a: int, o: int): bool = all {attempt.get((r, a)).knowledge != Unused, attempt.get((r, a)).owner == o, owner.get(o).alive, attempt.get((r, a)).entries == 0, attempt.get((r, a)).actual == NoActual, enterUpdate(r, a, o)}
  // Idempotent re-delivery is an interface assumption; this named event is
  // isActive only for an already entered, owner-matching Attempt.
  action duplicate(r: int, a: int): bool = all {attempt.get((r, a)).entries == 1, note(Duplicate, r, a, attempt.get((r, a)).owner, r, emptyBoundary), attempt' = attempt, boundaries' = boundaries, control' = control, effect' = effect, held' = held, inbox' = inbox, owner' = owner, writes' = writes}
  action complete(r: int, a: int, result: Actual): bool = all {attempt.get((r, a)).entries == 1, attempt.get((r, a)).actual == NoActual, owner.get(attempt.get((r, a)).owner).alive, result == Succeeded or result == FailedCall, note(Complete, r, a, attempt.get((r, a)).owner, r, emptyBoundary), attempt' = attempt.setBy((r, a), at => {...at, actual: result}), boundaries' = boundaries, control' = control, effect' = effect, held' = held, inbox' = inbox, owner' = owner, writes' = writes}
  action precheck(r: int, a: int): bool = all {attempt.get((r, a)).knowledge != Unused, attempt.get((r, a)).entries == 0, attempt.get((r, a)).actual == NoActual, note(Complete, r, a, attempt.get((r, a)).owner, r, emptyBoundary), attempt' = attempt.setBy((r, a), at => {...at, actual: NotExecuted}), boundaries' = boundaries, control' = control, effect' = effect, held' = held, inbox' = inbox, owner' = owner, writes' = writes}
  pure def delivery(c: Control, result: Result, revision: int): Input = {...input(if (result == NoResult) Uncertainty else Reply, revision), disposition: if (c.life == Open) PendingInput else Unprocessed}
  action lose(r: int, a: int): bool = {
    val at = attempt.get((r, a))
    val e = effect.get(r)
    val notify = e.result == NoResult and e.phase != Uncertain and attempt.get((r, 1 - a)).knowledge != Admitted
    val q = if (notify) inbox.get(r).append(delivery(control.get(r), NoResult, e.issued)) else inbox.get(r)
    all {writes, at.knowledge == Admitted, not(owner.get(at.owner).reachable), q.length() <= QUEUE_LIMIT, note(Lose, r, a, at.owner, r, emptyBoundary), attempt' = attempt.set((r, a), {...at, knowledge: Unknown, evidence: LostContact}), effect' = effect.set(r, if (notify) {...e, phase: Uncertain} else e), inbox' = inbox.set(r, q), control' = control.setBy(r, c => if (c.life != Open) {...c, cursor: q.length()} else c), boundaries' = boundaries, held' = held, owner' = owner, writes' = writes}
  }
  action recordUpdate(r: int, a: int): bool = {
    val at = attempt.get((r, a))
    val other = attempt.get((r, 1 - a))
    val e = effect.get(r)
    val recorded = {...at, knowledge: Recorded, evidence: observed(at.actual)}
    val updated = reduce(e, recorded, other)
    val choose = e.result == NoResult and updated.result != NoResult
    val notify = updated.phase == Uncertain and e.phase != Uncertain and e.result == NoResult
    val q = if (choose or notify) inbox.get(r).append(delivery(control.get(r), if (choose) updated.result else NoResult, e.issued)) else inbox.get(r)
    all {q.length() <= QUEUE_LIMIT, note(Record, r, a, at.owner, r, emptyBoundary), attempt' = attempt.set((r, a), recorded), effect' = effect.set(r, updated), inbox' = inbox.set(r, q), control' = control.setBy(r, c => if (c.life != Open) {...c, cursor: q.length()} else c), boundaries' = boundaries, held' = held, owner' = owner, writes' = writes}
  }
  action record(r: int, a: int): bool = all {writes, attempt.get((r, a)).knowledge != Unused, attempt.get((r, a)).knowledge != Recorded, attempt.get((r, a)).actual != NoActual, recordUpdate(r, a)}
  action repeat(r: int): bool = all {writes, control.get(r).life == Open, effect.get(r).phase == Uncertain, effect.get(r).result == NoResult, not(pendingAttempt(r)), noteRun(Repeat, r), effect' = effect.setBy(r, e => {...e, issued: e.issued + 1, permit: e.issued + 1}), attempt' = attempt, boundaries' = boundaries, control' = control, held' = held, inbox' = inbox, owner' = owner, writes' = writes}
  action settle(r: int): bool = {
    val q = inbox.get(r).append(delivery(control.get(r), Ok, effect.get(r).issued))
    all {writes, control.get(r).life == Open, effect.get(r).phase == Uncertain, effect.get(r).result == NoResult, not(pendingAttempt(r)), q.length() <= QUEUE_LIMIT, noteRun(Settle, r), effect' = effect.setBy(r, e => {...e, result: Ok, phase: Outcome}), inbox' = inbox.set(r, q), attempt' = attempt, boundaries' = boundaries, control' = control, held' = held, owner' = owner, writes' = writes}
  }
  action setActiveUpdate(r: int, isActive: bool): bool = all {noteRun(ControlChange, r), control' = control.setBy(r, c => {...c, active: isActive, epoch: c.epoch + 1}), attempt' = attempt, boundaries' = boundaries, effect' = effect, held' = held, inbox' = inbox, owner' = owner, writes' = writes}
  action setActive(r: int, isActive: bool): bool = all {writes, control.get(r).exists, control.get(r).life == Open, control.get(r).active != isActive, setActiveUpdate(r, isActive)}
  action takeover(r: int): bool = all {writes, control.get(r).exists, control.get(r).life == Open, noteRun(Takeover, r), control' = control.setBy(r, c => {...c, epoch: c.epoch + 1}), attempt' = attempt, boundaries' = boundaries, effect' = effect, held' = held, inbox' = inbox, owner' = owner, writes' = writes}
  action disconnect(o: int, death: bool): bool = all {owner.get(o).alive, death or owner.get(o).reachable, note(Disconnect, 0, 0, o, 0, emptyBoundary), owner' = owner.set(o, {alive: not(death), reachable: false}), attempt' = attempt, boundaries' = boundaries, control' = control, effect' = effect, held' = held, inbox' = inbox, writes' = writes}
  action reconnect(o: int): bool = all {owner.get(o).alive, not(owner.get(o).reachable), note(Reconnect, 0, 0, o, 0, emptyBoundary), owner' = owner.setBy(o, own => {...own, reachable: true}), attempt' = attempt, boundaries' = boundaries, control' = control, effect' = effect, held' = held, inbox' = inbox, writes' = writes}
  action availability = all {noteRun(Availability, 0), writes' = not(writes), attempt' = attempt, boundaries' = boundaries, control' = control, effect' = effect, held' = held, inbox' = inbox, owner' = owner}
  action addInput(r: int): bool = all {writes, control.get(r).exists, control.get(r).life == Open, inbox.get(r).length() < QUEUE_LIMIT, noteRun(InputArrival, r), inbox' = inbox.setBy(r, q => q.append(input(External, 0))), attempt' = attempt, boundaries' = boundaries, control' = control, effect' = effect, held' = held, owner' = owner, writes' = writes}
  action forkUpdate(src: int, dst: int, index: int): bool = {
    val b = boundaries.get(src).nth(index)
    all {note(Fork, dst, 0, 0, src, b), control' = control.set(dst, {...emptyControl(true), active: false, app: b.app, revision: b.revision, ready: b.ready, life: b.life, parent: src, origin: b}), inbox' = inbox.set(dst, if (b.ready) List(input(Continuation, b.revision)) else List()), boundaries' = boundaries.set(dst, List(b)), attempt' = attempt, effect' = effect, held' = held, owner' = owner, writes' = writes}
  }
  action fork(src: int, dst: int, index: int): bool = all {writes, control.get(src).exists, not(control.get(dst).exists), src != dst, boundaries.get(src).nth(index).stable, forkUpdate(src, dst, index)}
  action step = any {
    {nondet r = RUNS.oneOf() nondet choice = Set(Invoke, Wait, Continue, Finish, Fault).oneOf() nondet retryable = Set(false, true).oneOf() nondet conclusive = Set(false, true).oneOf() evaluate(r, choice, retryable, conclusive)},
    {nondet r = RUNS.oneOf() any {commit(r), failRun(r), dispose(r), repeat(r), settle(r), addInput(r), takeover(r), setActive(r, true), setActive(r, false)}},
    {nondet r = RUNS.oneOf() nondet a = ATTEMPTS.oneOf() nondet o = OWNERS.oneOf() nondet result = Set(Succeeded, FailedCall).oneOf() any {admit(r, a, o), enter(r, a, o), duplicate(r, a), complete(r, a, result), precheck(r, a), record(r, a), lose(r, a)}},
    {nondet o = OWNERS.oneOf() any {disconnect(o, false), disconnect(o, true), reconnect(o), availability}},
    {nondet src = RUNS.oneOf() nondet dst = RUNS.oneOf() nondet index = boundaries.get(src).indices().oneOf() fork(src, dst, index)},
  }
  // Prior records are read from the actual pre-state, not filled validity flags.
  val identityRetention = attempt.get((prior.runId, prior.attempt)).entries >= prior.at.entries and attempt.get((prior.runId, 1 - prior.attempt)).entries >= prior.other.entries and
    (prior.other.knowledge == Unused or attempt.get((prior.runId, 1 - prior.attempt)).owner == prior.other.owner) and
    (prior.other.knowledge != Unknown or attempt.get((prior.runId, 1 - prior.attempt)).knowledge == Unknown) and
    (prior.at.knowledge != Unknown or attempt.get((prior.runId, prior.attempt)).knowledge == Unknown or prior.event == Record and prior.at.actual != NoActual) and
    (prior.physicalOwner.alive or not(owner.get(prior.owner).alive))
  val C1 = identityRetention and (not(prior.effect.exists) or (effect.get(prior.runId).exists and effect.get(prior.runId).token == prior.effect.token and effect.get(prior.runId).retryable == prior.effect.retryable and effect.get(prior.runId).conclusive == prior.effect.conclusive)) and
    (prior.effect.result == NoResult or effect.get(prior.runId).result == prior.effect.result) and
    (prior.at.knowledge == Unused or (attempt.get((prior.runId, prior.attempt)).knowledge != Unused and attempt.get((prior.runId, prior.attempt)).owner == prior.at.owner and attempt.get((prior.runId, prior.attempt)).permit == prior.at.permit)) and
    (prior.at.actual == NoActual or attempt.get((prior.runId, prior.attempt)).actual == prior.at.actual) and
    (prior.other.actual == NoActual or attempt.get((prior.runId, 1 - prior.attempt)).actual == prior.other.actual)
  val C2 = IDS.forall(id => {val at = attempt.get(id) at.entries <= 1 and (at.actual != Succeeded and at.actual != FailedCall or at.entries == 1) and (at.actual != NotExecuted or at.entries == 0) and (at.entries == 0 or at.knowledge != Unused and at.actor == at.owner and effect.get(id._1).exists)}) and
    (prior.event != Enter or prior.at.knowledge != Unused and prior.at.owner == prior.owner and prior.physicalOwner.alive and prior.at.entries == 0) and
    (prior.event != Admit or prior.writes and active(prior.control) and prior.effect.exists and prior.effect.result == NoResult and prior.at.knowledge == Unused and prior.physicalOwner.alive and prior.other.knowledge != Admitted and (not(prior.other.evidence == LostContact or prior.other.evidence == FailureEvidence and not(prior.effect.conclusive)) or prior.other.owner != prior.owner) and (prior.effect.phase != Uncertain or prior.effect.retryable or prior.effect.permit > 0))
  // Independent pre-state criterion: do not call reduce/observed/unresolved here.
  val terminalChoice = prior.effect.result != NoResult or effect.get(prior.runId).result == NoResult or (
    prior.writes and ((prior.event == Settle and prior.control.life == Open and prior.effect.phase == Uncertain and prior.at.knowledge != Admitted and prior.other.knowledge != Admitted) or
    (prior.event == Record and prior.at.knowledge != Unused and prior.at.knowledge != Recorded and prior.at.actual != NoActual and
      ((effect.get(prior.runId).result == Ok and (prior.at.actual == Succeeded or prior.other.evidence == SuccessEvidence)) or
       (effect.get(prior.runId).result == Error and prior.effect.conclusive and (prior.at.actual == FailedCall or prior.other.evidence == FailureEvidence) and prior.other.knowledge != Admitted and prior.other.evidence != LostContact)))))
  val normalReductionRequired = prior.event != Record or prior.effect.result != NoResult or {
    val afterResult = effect.get(prior.runId).result
    and {
      prior.at.actual != Succeeded or afterResult == Ok,
      not(prior.effect.conclusive and prior.other.knowledge != Admitted and prior.other.evidence != LostContact and
        (prior.at.actual == FailedCall or prior.at.actual == NotExecuted and prior.other.evidence == FailureEvidence)) or afterResult == Error,
    }
  }
  val evidenceRetention = (prior.event != Record or attempt.get((prior.runId, prior.attempt)).evidence == (if (prior.at.actual == Succeeded) SuccessEvidence else if (prior.at.actual == FailedCall) FailureEvidence else NonexecutionEvidence)) and
    (prior.event == Record or prior.event == Lose or attempt.get((prior.runId, prior.attempt)).evidence == prior.at.evidence) and
    attempt.get((prior.runId, 1 - prior.attempt)).evidence == prior.other.evidence
  val evidencePhase = RUNS.forall(r => {
    val e = effect.get(r)
    val pending = ATTEMPTS.exists(a => attempt.get((r, a)).knowledge == Admitted)
    val unknown = ATTEMPTS.exists(a => {val at = attempt.get((r, a)) at.evidence == LostContact or at.evidence == FailureEvidence and not(e.conclusive)})
    e.result != NoResult or not(e.exists) or (pending implies e.phase == Executing) and (not(pending) and unknown implies e.phase == Uncertain) and (not(pending) and not(unknown) implies e.phase == Dormant)
  })
  val C3 = normalReductionRequired and evidenceRetention and evidencePhase and terminalChoice and RUNS.forall(r => {
    val e = effect.get(r)
    val replies = inbox.get(r).select(i => i.kind == Reply)
    replies.length() == (if (e.result == NoResult) 0 else 1) and ATTEMPTS.forall(a => attempt.get((r, a)).permit == 0 or ATTEMPTS.filter(b => attempt.get((r, b)).permit == attempt.get((r, a)).permit).size() == 1)
  }) and (prior.event != Record or prior.effect.result != NoResult or effect.get(prior.runId).result != Error or prior.effect.conclusive and prior.other.knowledge != Admitted and prior.other.evidence != LostContact and (prior.other.evidence != FailureEvidence or prior.effect.conclusive)) and
    (prior.event != Record or not(prior.other.evidence == LostContact or prior.other.evidence == FailureEvidence and not(prior.effect.conclusive)) or effect.get(prior.runId).result != NoResult or effect.get(prior.runId).phase == Uncertain) and
    (prior.event != Admit or effect.get(prior.runId).permit == 0 and attempt.get((prior.runId, prior.attempt)).permit == prior.effect.permit) and
    (prior.event != Repeat or effect.get(prior.runId).result == prior.effect.result)
  val applicationRetention = prior.event == Commit or prior.event == Fork or (control.get(prior.runId).app == prior.control.app and control.get(prior.runId).revision == prior.control.revision)
  val atomicConsumption = prior.event != Commit or {
    val c = control.get(prior.runId)
    val q = inbox.get(prior.runId)
    val e = effect.get(prior.runId)
    val p = prior.proposal
    q.length() == prior.inbox.length() + (if (p.choice == Continue) 1 else 0) and
    c.cursor == (if (p.choice == Finish) q.length() else prior.control.cursor + 1) and
    prior.inbox.indices().forall(i => {
      val before = prior.inbox.nth(i)
      val after = q.nth(i)
      after.kind == before.kind and after.revision == before.revision and
      after.disposition == (if (i == prior.control.cursor) Applied else if (p.choice == Finish and before.disposition == PendingInput) Unprocessed else before.disposition)
    }) and
    (p.choice != Invoke or e.exists and e.phase == Dormant and e.result == NoResult and e.token == prior.runId) and
    (p.choice == Invoke or e.phase == (if (prior.inbox.nth(prior.control.cursor).kind == Reply) Consumed else prior.effect.phase)) and
    (p.choice != Continue or q.nth(q.length() - 1).kind == Continuation and q.nth(q.length() - 1).revision == c.revision)
  }
  val inputRetention = prior.event == Fork or inbox.get(prior.runId).length() >= prior.inbox.length() and prior.inbox.indices().forall(i => {
    val before = prior.inbox.nth(i)
    val after = inbox.get(prior.runId).nth(i)
    after.kind == before.kind and after.revision == before.revision and (before.disposition == PendingInput or after.disposition == before.disposition)
  })
  val C4 = inputRetention and atomicConsumption and applicationRetention and RUNS.forall(r => {
    val c = control.get(r)
    c.cursor >= 0 and c.cursor <= inbox.get(r).length() and inbox.get(r).indices().forall(i => (i < c.cursor) iff (inbox.get(r).nth(i).disposition != PendingInput)) and
    (effect.get(r).phase != Consumed or inbox.get(r).indices().exists(i => inbox.get(r).nth(i).kind == Reply and inbox.get(r).nth(i).disposition == Applied))
  }) and (prior.event != Commit or prior.writes and active(prior.control) and prior.proposal.valid and prior.proposal.epoch == prior.control.epoch and prior.proposal.revision == prior.control.revision and prior.proposal.cursor == prior.control.cursor and prior.control.cursor < prior.inbox.length() and control.get(prior.runId).revision == prior.control.revision + 1 and control.get(prior.runId).app == prior.control.app + 1 and (not(effect.get(prior.runId).exists) or prior.effect.exists or prior.proposal.choice == Invoke) and (prior.inbox.nth(prior.control.cursor).kind != Uncertainty or prior.effect.result == NoResult))
  val failedAudit = RUNS.forall(r => control.get(r).life != Failed or inbox.get(r).indices().forall(i => inbox.get(r).nth(i).disposition != PendingInput)) and
    (prior.control.life != Failed or prior.event != Repeat and prior.event != Settle and prior.event != Admit and prior.event != Commit and effect.get(prior.runId).permit == prior.effect.permit and (effect.get(prior.runId).phase != Consumed or prior.effect.phase == Consumed)) and
    (prior.event != Fail or effect.get(prior.runId) == prior.effect and attempt.get((prior.runId, prior.attempt)) == prior.at and attempt.get((prior.runId, 1 - prior.attempt)) == prior.other and control.get(prior.runId).app == prior.control.app and prior.inbox.indices().forall(i => inbox.get(prior.runId).nth(i).disposition == (if (prior.inbox.nth(i).disposition == PendingInput) Unprocessed else prior.inbox.nth(i).disposition)))
  val C5 = failedAudit and (prior.control.life == Open or control.get(prior.runId).life == prior.control.life and control.get(prior.runId).active == prior.control.active and control.get(prior.runId).epoch == prior.control.epoch) and
    (prior.event != ControlChange or prior.writes and prior.control.exists and prior.control.life == Open) and
    (prior.event != Fail or prior.writes and active(prior.control) and prior.proposal.valid and prior.proposal.choice == Fault and prior.proposal.epoch == prior.control.epoch and prior.proposal.revision == prior.control.revision and prior.proposal.cursor == prior.control.cursor and prior.control.cursor < prior.inbox.length() and (prior.inbox.nth(prior.control.cursor).kind != Uncertainty or prior.effect.result == NoResult)) and
    RUNS.forall(r => control.get(r).life != Finished or not(effect.get(r).exists) or effect.get(r).phase == Consumed)
  val C6 = (prior.event != Fork or prior.writes and not(prior.control.exists) and prior.source != prior.runId and prior.sourceBoundaries.indices().exists(i => prior.sourceBoundaries.nth(i) == prior.boundary) and prior.boundary.stable and control.get(prior.runId).origin == prior.boundary and control.get(prior.runId).app == prior.boundary.app and control.get(prior.runId).revision == prior.boundary.revision and control.get(prior.runId).life == prior.boundary.life and control.get(prior.runId).ready == prior.boundary.ready and not(control.get(prior.runId).active) and control.get(prior.runId).cursor == 0 and control.get(prior.runId).epoch == 0 and not(effect.get(prior.runId).exists) and ATTEMPTS.forall(a => attempt.get((prior.runId, a)).knowledge == Unused) and inbox.get(prior.runId).length() == (if (prior.boundary.ready) 1 else 0) and (not(prior.boundary.ready) or inbox.get(prior.runId).nth(0).kind == Continuation and inbox.get(prior.runId).nth(0).revision == prior.boundary.revision)) and
    (prior.event != Commit or {
      val b = boundaries.get(prior.runId).nth(boundaries.get(prior.runId).length() - 1)
      val c = control.get(prior.runId)
      val e = effect.get(prior.runId)
      val q = inbox.get(prior.runId)
      b.app == c.app and b.revision == c.revision and b.life == c.life and b.ready == c.ready and b.result == e.result and
      (b.stable iff (c.life != Failed and (not(e.exists) or e.phase == Consumed) and q.indices().forall(i => i < c.cursor or (q.nth(i).kind != Reply and q.nth(i).kind != Uncertainty))))
    })
  val boundaryRetention = boundaries.get(prior.source).length() >= prior.sourceBoundaries.length() and prior.sourceBoundaries.indices().forall(i => boundaries.get(prior.source).nth(i) == prior.sourceBoundaries.nth(i)) and (not(prior.control.exists) or control.get(prior.runId).origin == prior.control.origin and control.get(prior.runId).parent == prior.control.parent)
  val safety = boundaryRetention and and {C1, C2, C3, C4, C5, C6}
  val intentWitness = RUNS.exists(r => effect.get(r).exists)
  val entryWitness = IDS.exists(id => attempt.get(id).entries == 1)
  val unknownWitness = IDS.exists(id => attempt.get(id).knowledge == Unknown)
  val recoveryWitness = RUNS.exists(r => ATTEMPTS.forall(a => attempt.get((r, a)).knowledge != Unused))
  val consumedWitness = RUNS.exists(r => effect.get(r).phase == Consumed)
  val recoveryConsumedWitness = RUNS.exists(r => ATTEMPTS.forall(a => attempt.get((r, a)).knowledge != Unused) and effect.get(r).phase == Consumed)
  val inconclusiveWitness = IDS.exists(id => attempt.get(id).evidence == FailureEvidence and not(effect.get(id._1).conclusive))
  val failedUnknownWitness = RUNS.exists(r => control.get(r).life == Failed and ATTEMPTS.exists(a => attempt.get((r, a)).evidence == LostContact))
  val failedReplyWitness = RUNS.exists(r => control.get(r).life == Failed and inbox.get(r).indices().exists(i => inbox.get(r).nth(i).kind == Reply and inbox.get(r).nth(i).disposition == Unprocessed))
  val branchWorkWitness = RUNS.exists(r => control.get(r).parent >= 0 and effect.get(r).exists)
}
