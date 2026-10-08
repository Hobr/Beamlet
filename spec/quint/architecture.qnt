// One composition, shared authority and separately interleavable local work.
module architecture {
  import architectureTypes.* from "./types"
  import architectureReference.* from "./reference"
  const RUNS: Set[int]
  const SLOTS: Set[int]
  const ATTEMPT_SLOTS: Set[int]
  const COMMAND_LIMIT: int
  const QUEUE_LIMIT: int
  pure val OWNERS = Set(0, 1, 2)
  pure val PROPOSALS = Set(0, 1)
  pure val COMMANDS = 0.to(7)
  pure val COMMAND_IDS = 0.to(COMMAND_LIMIT - 1)
  pure val OBSERVATION_IDS = 0.to(7)
  pure val INPUT_IDS = RUNS.map(r => COMMANDS.map(k => (r, k))).flatten()
  pure val emptyCommand: Command = { tag: InputCommand, definition: 0, progress: Waiting, provider: 0, resource: 0, operation: 0, runId: 0, slot: 0, attempt: 0, owner: 0, generation: 0, domain: 0, intent: 0, revision: 0, epoch: 0, cursor: 0, inputId: 0, observationId: 0, payload: 0, observation: NoObservation, decision: AuditOp, source: 0, evidence: 1, mode: Suspended, dst: 0, boundary: 0, validation: ValidImport, stepKind: WaitStep, policy: NonRepeatable, failureConclusive: true }
  pure val OPERATIONS = Set(CreateOp, ResourceOp, InputOp, ControlOp, AdmitOp, ObserveOp, AuditOp, SettleOp, RepeatOp, ForkOp, InspectOp, ExportOp)
  pure val EFFECTS = RUNS.fold(Set(), (acc, r) => acc.union(SLOTS.map(e => (r, e))))
  pure val ATTEMPTS = EFFECTS.fold(Set(), (acc, e) => acc.union(ATTEMPT_SLOTS.map(a => (e, a))))
  pure val emptyBoundary: Boundary = { valid: false, app: 0, revision: 0, cursor: 0, progress: Waiting, lifetime: Open, result: 0, definition: 0, prefix: Set(), results: Set(), events: Set() }
  pure def emptyRun(present: bool): Run = { exists: present, definition: 0, scope: 0, requiredResource: 0, app: 0, revision: 0, history: 0, host: 0, controller: 0, externalController: false, controllerReady: true, mode: Active, lifetime: Open, progress: Waiting, inbox: List(), cursor: 0, result: 0, boundaries: List({...emptyBoundary, valid: present}), parent: -1, origin: emptyBoundary }
  pure def emptyEffect(e: EffectId): Effect = { exists: false, operation: 0, resource: 0, intent: 0, token: e, policy: NonRepeatable, failureConclusive: true, phase: Pending, revision: 0, result: NoResult, resultPayload: 0, provenance: NoObservation, settled: false, notifications: 0, permit: 0, permitsIssued: 0, permitsUsed: Set(), replyCount: 0 }
  pure val emptyAttempt: Attempt = { phase: Unused, provider: 0, resource: 0, owner: 0, generation: 0, domain: 0, entered: false, calls: 0, actual: NoObservation, observed: Set(), permit: 0, hostAtGrant: 0, controllerAtGrant: 0, activeAtGrant: false, intentAtGrant: 0 }
  pure val emptyProposal: Proposal = { valid: false, runId: 0, host: 0, revision: 0, cursor: 0, kind: WaitStep, operation: 0, resource: 0, slot: 0, policy: NonRepeatable, intent: 0, failureConclusive: true }
  pure val initial: State = { roles: Set(InteractionRole, ComputeRole, ExecuteRole, AuthorityRole), scopes: RUNS.mapBy(r => {parent: if (r == 0) -1 else 0, isolated: r != 0, provider: r}), resources: RUNS.mapBy(_ => {available: true, permitted: true}), queryReads: 0, exports: Set(), runs: RUNS.mapBy(r => {...emptyRun(r == 0), scope: r}), effects: EFFECTS.mapBy(e => emptyEffect(e)), attempts: ATTEMPTS.mapBy(_ => emptyAttempt), owners: OWNERS.mapBy(_ => {alive: true, reachable: true}), providers: RUNS.mapBy(_ => {resource: 0, generation: 0, domain: 0, present: true, compatible: true, dependencies: true, protection: true, configuration: 0, failureConclusive: true}), proposals: PROPOSALS.mapBy(_ => emptyProposal), receipts: COMMANDS.mapBy(_ => {valid: false, operation: InputOp, target: 0, payload: 0, revision: 0}), commandReceipts: COMMAND_IDS.mapBy(_ => {valid: false, body: emptyCommand, history: 0, stateRevision: 0, executionRevision: 0}), inputIds: INPUT_IDS.mapBy(_ => {valid: false, payload: 0, sequence: 0}), observationIds: OBSERVATION_IDS.mapBy(_ => {valid: false, provider: 0, resource: 0, attempt: ((0, 0), 0), owner: 0, generation: 0, domain: 0, intent: 0, observation: NoObservation, payload: 0}), resolutions: Set(), writes: true, authenticated: true, permissions: OPERATIONS, ui: true, error: NoError, acknowledged: false, receiptReads: 0, commits: Set(), grants: Set(), entries: Set(), outcomes: Set(), performed: Set() }
  pure def permitted(st: State, op: Operation): bool = st.authenticated and st.permissions.contains(op)
  pure def writable(st: State, op: Operation): bool = st.writes and st.roles.contains(AuthorityRole) and permitted(st, op)
  pure def active(st: State, r: int): bool = { val rr = st.runs.get(r) rr.exists and rr.mode == Active and rr.lifetime == Open }
  pure def input(kind: Kind, e: EffectId, revision: int, key: int): Input = {kind: kind, effect: e, revision: revision, key: key, disposition: Queued}
  pure def touchHistory(st: State, r: int): State = {...st, runs: st.runs.setBy(r, rr => {...rr, history: rr.history + 1})}
  pure def putRun(st: State, r: int, rr: Run): State = {...st, runs: st.runs.set(r, rr)}
  pure def mark(st: State, name: str): State = {...st, performed: st.performed.union(Set(name)), error: NoError, acknowledged: false}
  pure def canInput(st: State, r: int, key: int): bool = and { writable(st, InputOp), st.runs.get(r).exists, st.runs.get(r).lifetime == Open, not(st.receipts.get(key).valid), not(st.inputIds.get((r, key)).valid), st.runs.get(r).inbox.length() < QUEUE_LIMIT }
  pure def applyInput(st: State, r: int, key: int, payload: int): State = {
    val rr = st.runs.get(r)
    val updated = putRun(st, r, {...rr, inbox: rr.inbox.append(input(External, (r, 0), payload, key)), history: rr.history + 1})
    {...mark(updated, "input"), receipts: st.receipts.set(key, {valid: true, operation: InputOp, target: r, payload: payload, revision: rr.history + 1}), inputIds: st.inputIds.set((r, key), {valid: true, payload: payload, sequence: rr.inbox.length()}), acknowledged: true}
  }
  // Host evaluation is pure and explicitly separated from its conditional commit.
  pure def hasHead(st: State, r: int): bool = st.runs.get(r).cursor < st.runs.get(r).inbox.length()
  pure def inputHead(st: State, r: int): Input = st.runs.get(r).inbox.nth(st.runs.get(r).cursor)
  pure def obsolete(st: State, r: int): bool = if (not(hasHead(st, r))) false else {
    val h = inputHead(st, r)
    (h.kind == Continuation and h.revision != st.runs.get(r).revision) or
    (h.kind == Uncertainty and st.effects.get(h.effect).result != NoResult)
  }
  // Two registered deterministic Definitions use only portable state/input.
  // Operation IDs 0/1 are opaque to the foundation; no provider I/O occurs here.
  pure def definitionKind(definition: int, app: int): ProposalKind =
    if (definition == 1) { if (app == 0 or app == 2) InvokeStep else if (app == 1) ContinueStep else FinishStep }
    else if (app < 2) InvokeStep else FinishStep
  pure def definitionSlot(definition: int, app: int): int = if (definition == 1) (if (app == 0) 0 else 1) else app
  pure def definitionOperation(definition: int, app: int): int = if (definition == 2) (if (app == 0) 1 else 0) else (if (app < 2) 0 else 1)
  pure def providerId(st: State, r: int): int = {
    val sc = st.scopes.get(st.runs.get(r).scope)
    if (st.providers.get(sc.provider).present or sc.parent < 0 or sc.isolated) sc.provider else st.scopes.get(sc.parent).provider
  }
  pure def resolvedProvider(st: State, r: int): Provider = st.providers.get(providerId(st, r))
  pure def canEvaluate(st: State, r: int, kind: ProposalKind, slot: int): bool =
    st.roles.contains(ComputeRole) and active(st, r) and hasHead(st, r) and not(obsolete(st, r)) and
    (kind != InvokeStep or not(st.effects.get((r, slot)).exists)) and
    (st.runs.get(r).definition == 0 or (kind == definitionKind(st.runs.get(r).definition, st.runs.get(r).app) and (kind != InvokeStep or slot == definitionSlot(st.runs.get(r).definition, st.runs.get(r).app))))
  pure def applyEvaluate(st: State, r: int, p: int, kind: ProposalKind, slot: int, policy: Policy): State = {
    val rr = st.runs.get(r)
    {...mark(st, "evaluate"), proposals: st.proposals.set(p, {valid: true, runId: r, host: rr.host, revision: rr.revision, cursor: rr.cursor, kind: kind, operation: if (rr.definition == 0) slot else definitionOperation(rr.definition, rr.app), resource: rr.requiredResource, slot: slot, policy: policy, intent: resolvedProvider(st, r).configuration, failureConclusive: resolvedProvider(st, r).failureConclusive})}
  }
  pure def validDefinitionProposal(st: State, pp: Proposal): bool = {
    val rr = st.runs.get(pp.runId)
    rr.definition == 0 or (pp.kind == definitionKind(rr.definition, rr.app) and pp.operation == definitionOperation(rr.definition, rr.app) and pp.resource == rr.requiredResource and pp.policy == NonRepeatable and (pp.kind != InvokeStep or pp.slot == definitionSlot(rr.definition, rr.app)))
  }
  pure def currentProposal(st: State, p: int): bool = {
    val pp = st.proposals.get(p)
    val rr = st.runs.get(pp.runId)
    pp.valid and validDefinitionProposal(st, pp) and active(st, pp.runId) and hasHead(st, pp.runId) and not(obsolete(st, pp.runId)) and pp.host == rr.host and pp.revision == rr.revision and pp.cursor == rr.cursor
  }
  pure def afterConsumption(st: State, r: int): EffectId -> Effect = {
    val h = inputHead(st, r)
    if (h.kind == TerminalReply) st.effects.setBy(h.effect, e => {...e, phase: Consumed}) else st.effects
  }
  pure def canFinish(st: State, r: int): bool = {
    val es = afterConsumption(st, r)
    EFFECTS.filter(e => e._1 == r).forall(e => not(es.get(e).exists) or es.get(e).phase == Consumed) and
    st.runs.get(r).inbox.indices().forall(i => i <= st.runs.get(r).cursor or st.runs.get(r).inbox.nth(i).kind != TerminalReply)
  }
  pure def stable(st: State, r: int): bool = {
    val rr = st.runs.get(r)
    rr.lifetime != Failed and EFFECTS.filter(e => e._1 == r).forall(e => not(st.effects.get(e).exists) or st.effects.get(e).phase == Consumed) and
    rr.inbox.indices().forall(i => i < rr.cursor or (rr.inbox.nth(i).kind != TerminalReply and rr.inbox.nth(i).kind != Uncertainty))
  }
  pure def capture(st: State, r: int): State = {
    val rr = st.runs.get(r)
    val b: Boundary = {valid: stable(st, r), app: rr.app, revision: rr.revision, cursor: rr.cursor, progress: rr.progress, lifetime: rr.lifetime, result: rr.result, definition: rr.definition, prefix: EFFECTS.filter(e => e._1 == r and st.effects.get(e).exists), results: EFFECTS.filter(e => e._1 == r and st.effects.get(e).exists).map(e => (e, st.effects.get(e).result, st.effects.get(e).resultPayload)), events: rr.inbox.indices().filter(i => i < rr.cursor).map(i => (i, rr.inbox.nth(i).kind, rr.inbox.nth(i).effect, rr.inbox.nth(i).disposition))}
    putRun(st, r, {...rr, boundaries: rr.boundaries.append(b)})
  }
  pure def canCommit(st: State, p: int): bool = {
    val pp = st.proposals.get(p)
    currentProposal(st, p) and writable(st, ControlOp) and pp.kind != FaultStep and
    (pp.kind != FinishStep or canFinish(st, pp.runId)) and
    (pp.kind != InvokeStep or not(st.effects.get((pp.runId, pp.slot)).exists)) and
    (pp.kind != ContinueStep or st.runs.get(pp.runId).inbox.length() < QUEUE_LIMIT)
  }
  pure def applyCommit(st: State, p: int): State = {
    val pp = st.proposals.get(p)
    val r = pp.runId
    val rr = st.runs.get(r)
    val h = inputHead(st, r)
    val q = rr.inbox.replaceAt(rr.cursor, {...h, disposition: Applied})
    val cq = if (pp.kind == ContinueStep) q.append(input(Continuation, (r, 0), rr.revision + 1, -1)) else q
    val fq = if (pp.kind == FinishStep) cq.foldl(List(), (acc, i) => acc.append(if (i.disposition == Queued) {...i, disposition: RunFinished} else i)) else cq
    val es = afterConsumption(st, r)
    val e = (r, pp.slot)
    val nes = if (pp.kind == InvokeStep) es.set(e, {...emptyEffect(e), exists: true, intent: pp.intent, policy: pp.policy, operation: pp.operation, resource: pp.resource, failureConclusive: pp.failureConclusive}) else es
    val updated = putRun({...st, effects: nes}, r, {...rr, app: rr.app + 1, revision: rr.revision + 1, history: rr.history + 1, inbox: fq, cursor: if (pp.kind == FinishStep) fq.length() else rr.cursor + 1, progress: if (pp.kind == FinishStep) FinishedProgress else if (pp.kind == ContinueStep) Ready else Waiting, lifetime: if (pp.kind == FinishStep) Finished else Open, result: if (pp.kind == FinishStep) rr.app + 1 else rr.result})
    val fact: CommitFact = {runId: r, cursor: rr.cursor, oldRevision: rr.revision, newRevision: rr.revision + 1, host: pp.host, currentHost: rr.host, kind: h.kind, disposition: Applied, active: active(st, r), appBefore: rr.app, appAfter: rr.app + 1, created: if (pp.kind == InvokeStep) Set(e) else Set(), effect: h.effect, terminalAtCommit: st.effects.get(h.effect).result, inputRevision: h.revision}
    capture({...mark(updated, "commit"), commits: st.commits.union(Set(fact)), proposals: st.proposals.setBy(p, old => {...old, valid: false})}, r)
  }
  pure def canDispose(st: State, r: int): bool = writable(st, ControlOp) and active(st, r) and obsolete(st, r)
  pure def applyDispose(st: State, r: int): State = {
    val rr = st.runs.get(r)
    val h = inputHead(st, r)
    val disp = if (h.kind == Continuation) StaleContinuation else ObsoleteUncertainty
    val fact: CommitFact = {runId: r, cursor: rr.cursor, oldRevision: rr.revision, newRevision: rr.revision, host: rr.host, currentHost: rr.host, kind: h.kind, disposition: disp, active: true, appBefore: rr.app, appAfter: rr.app, created: Set(), effect: h.effect, terminalAtCommit: st.effects.get(h.effect).result, inputRevision: h.revision}
    val updated = putRun(st, r, {...rr, cursor: rr.cursor + 1, history: rr.history + 1, inbox: rr.inbox.replaceAt(rr.cursor, {...h, disposition: disp})})
    {...mark(updated, "dispose"), commits: st.commits.union(Set(fact))}
  }
  pure def canFail(st: State, p: int): bool = {
    val pp = st.proposals.get(p)
    writable(st, ControlOp) and currentProposal(st, p) and
    (pp.kind == FaultStep or (pp.kind == FinishStep and not(canFinish(st, pp.runId))))
  }
  pure def applyFail(st: State, p: int): State = {
    val r = st.proposals.get(p).runId
    val rr = st.runs.get(r)
    mark(putRun(st, r, {...rr, lifetime: Failed, progress: FailedProgress, result: -1, cursor: rr.inbox.length(), history: rr.history + 1, inbox: rr.inbox.foldl(List(), (acc, i) => acc.append(if (i.disposition == Queued) {...i, disposition: RunFailed} else i))}), "fail")
  }
  pure def canControl(st: State, r: int, mode: Mode): bool = writable(st, ControlOp) and st.runs.get(r).exists and st.runs.get(r).lifetime == Open and st.runs.get(r).mode != mode
  pure def applyControl(st: State, r: int, mode: Mode): State = {
    val rr = st.runs.get(r)
    mark(putRun(st, r, {...rr, mode: mode, host: rr.host + 1, controller: rr.controller + 1, history: rr.history + 1}), if (mode == Active) "resume" else "suspend")
  }
  pure def canTakeover(st: State, r: int): bool = writable(st, ControlOp) and st.runs.get(r).exists and st.runs.get(r).lifetime == Open
  pure def applyTakeover(st: State, r: int, controller: bool): State = {
    val rr = st.runs.get(r)
    mark(putRun(st, r, {...rr, host: rr.host + (if (controller) 0 else 1), controller: rr.controller + (if (controller) 1 else 0), externalController: if (controller) true else rr.externalController, controllerReady: if (controller) false else rr.controllerReady, history: rr.history + 1}), if (controller) "controller" else "takeover")
  }
  // Admission, local precheck/entry, physical completion and recording are distinct.
  pure def admitted(st: State, e: EffectId): bool = ATTEMPTS.exists(a => a._1 == e and st.attempts.get(a).phase == Admitted)
  pure def unresolved(st: State, e: EffectId, except: AttemptId): bool = ATTEMPTS.exists(a => a._1 == e and a != except and st.attempts.get(a).phase == UnknownAttempt)
  pure def eligibleProvider(st: State, r: int): bool = {
    val pr = resolvedProvider(st, r)
    pr.present and pr.compatible and pr.dependencies and st.resources.get(pr.resource).available and st.resources.get(pr.resource).permitted and st.permissions.contains(ResourceOp)
  }
  pure def uncertainAttempts(st: State, e: EffectId): Set[AttemptId] = ATTEMPTS.filter(a => a._1 == e and
    (st.attempts.get(a).phase == UnknownAttempt or (st.effects.get(e).phase == Unknown and not(st.effects.get(e).failureConclusive) and st.attempts.get(a).observed.contains(Failure))))
  pure def recoveryAllowed(st: State, e: EffectId): bool = {
    val ef = st.effects.get(e)
    val pr = resolvedProvider(st, e._1)
    uncertainAttempts(st, e).size() == 0 and ef.phase != Unknown or
    ef.permit > 0 or ef.policy == Idempotent or
    (ef.policy == Deduplicated and pr.protection and uncertainAttempts(st, e).forall(a => st.attempts.get(a).domain == pr.domain))
  }
  // authority-and-recovery:71-77: reconnect can redispatch the SAME Attempt;
  // recovery after unknown creates a new Attempt bound to a NEW instance.
  pure def freshRecoveryOwner(st: State, e: EffectId, owner: int): bool =
    uncertainAttempts(st, e).forall(a => st.attempts.get(a).owner != owner)
  pure def canAdmit(st: State, e: EffectId, a: AttemptId, owner: int, revision: int, controller: int): bool = and {
    writable(st, AdmitOp), active(st, e._1), st.effects.get(e).exists, st.effects.get(e).result == NoResult,
    st.effects.get(e).revision == revision, st.runs.get(e._1).controller == controller, a._1 == e,
    st.attempts.get(a).phase == Unused, not(admitted(st, e)), st.owners.get(owner).alive, freshRecoveryOwner(st, e, owner),
    eligibleProvider(st, e._1), resolvedProvider(st, e._1).resource == st.effects.get(e).resource, recoveryAllowed(st, e), not(st.runs.get(e._1).externalController) or st.runs.get(e._1).controllerReady,
  }
  pure def applyAdmit(st: State, e: EffectId, a: AttemptId, owner: int): State = {
    val ef = st.effects.get(e)
    val rr = st.runs.get(e._1)
    val pr = resolvedProvider(st, e._1)
    val at = {...emptyAttempt, phase: Admitted, provider: providerId(st, e._1), resource: pr.resource, owner: owner, generation: pr.generation, domain: pr.domain, permit: ef.permit, hostAtGrant: rr.host, controllerAtGrant: rr.controller, activeAtGrant: active(st, e._1), intentAtGrant: ef.intent}
    val g: Grant = {attempt: a, provider: providerId(st, e._1), resource: pr.resource, revision: ef.revision, owner: owner, generation: pr.generation, domain: pr.domain, intent: ef.intent, token: e, permit: ef.permit, active: active(st, e._1), controller: rr.controller, currentController: rr.controller, policy: ef.policy, priorUnknownDomains: uncertainAttempts(st, e).map(aid => st.attempts.get(aid).domain), protection: pr.protection, externalController: rr.externalController, controllerReady: rr.controllerReady}
    {...mark(st, "admit"), attempts: st.attempts.set(a, at), effects: st.effects.set(e, {...ef, phase: Executing, revision: ef.revision + 1, permitsUsed: if (ef.permit > 0) ef.permitsUsed.union(Set(ef.permit)) else ef.permitsUsed, permit: 0}), grants: st.grants.union(Set(g)), runs: st.runs.set(e._1, {...rr, history: rr.history + 1})}
  }
  pure def preciseBinding(st: State, a: AttemptId, owner: int): bool = {
    val at = st.attempts.get(a)
    val pr = resolvedProvider(st, a._1._1)
    st.roles.contains(ExecuteRole) and at.provider == providerId(st, a._1._1) and at.resource == pr.resource and at.owner == owner and st.owners.get(owner).alive and at.generation == pr.generation and at.domain == pr.domain and eligibleProvider(st, a._1._1)
  }
  pure def canEnter(st: State, a: AttemptId, owner: int): bool = {
    val at = st.attempts.get(a)
    (at.phase == Admitted or at.phase == UnknownAttempt) and not(at.entered) and at.actual == NoObservation and preciseBinding(st, a, owner)
  }
  pure def applyEnter(st: State, a: AttemptId, owner: int): State = {
    val at = st.attempts.get(a)
    val ef = st.effects.get(a._1)
    val en: Entry = {attempt: a, provider: providerId(st, a._1._1), resource: resolvedProvider(st, a._1._1).resource, owner: owner, generation: resolvedProvider(st, a._1._1).generation, domain: resolvedProvider(st, a._1._1).domain, intent: ef.intent, token: ef.token}
    {...mark(st, "enter"), attempts: st.attempts.set(a, {...at, entered: true, calls: at.calls + 1}), entries: st.entries.union(Set(en))}
  }
  pure def canPrecheckReject(st: State, a: AttemptId): bool = {
    val at = st.attempts.get(a)
    (at.phase == Admitted or at.phase == UnknownAttempt) and not(at.entered) and at.actual == NoObservation and st.owners.get(at.owner).alive and not(preciseBinding(st, a, at.owner))
  }
  pure def applyPrecheckReject(st: State, a: AttemptId): State =
    {...mark(st, "precheck"), attempts: st.attempts.setBy(a, at => {...at, actual: NotExecuted})}
  pure def canComplete(st: State, a: AttemptId): bool = {
    val at = st.attempts.get(a)
    st.roles.contains(ExecuteRole) and at.entered and at.actual == NoObservation and st.owners.get(at.owner).alive
  }
  pure def applyComplete(st: State, a: AttemptId, observation: Observation): State =
    {...mark(st, "complete"), attempts: st.attempts.setBy(a, at => {...at, actual: observation})}
  pure def enqueue(st: State, e: EffectId, kind: Kind): State = {
    val rr = st.runs.get(e._1)
    val disp = if (rr.lifetime == Failed) RunFailed else if (rr.lifetime == Finished) RunFinished else Queued
    val q = rr.inbox.append({...input(kind, e, st.effects.get(e).revision, -1), disposition: disp})
    putRun(st, e._1, {...rr, inbox: q, cursor: if (rr.lifetime != Open) q.length() else rr.cursor})
  }
  pure def recordOutcome(st: State, e: EffectId, result: Result, provenance: Observation, settled: bool, payload: int): State = {
    val ef = st.effects.get(e)
    val fact: OutcomeFact = {effect: e, result: result, payload: payload, provenance: provenance, settled: settled, unresolvedAtChoice: ATTEMPTS.filter(a => a._1 == e and st.attempts.get(a).phase == UnknownAttempt)}
    enqueue({...st, effects: st.effects.set(e, {...ef, phase: OutcomeRecorded, result: result, resultPayload: payload, provenance: provenance, settled: settled, replyCount: ef.replyCount + 1}), outcomes: st.outcomes.union(Set(fact))}, e, TerminalReply)
  }
  pure def becomeUnknown(st: State, e: EffectId): State = {
    val ef = st.effects.get(e)
    if (ef.result != NoResult or admitted(st, e)) st
    else if (ef.phase == Unknown) st
    else enqueue({...st, effects: st.effects.set(e, {...ef, phase: Unknown, notifications: ef.notifications + 1})}, e, Uncertainty)
  }
  pure def canLose(st: State, a: AttemptId): bool = {
    val at = st.attempts.get(a)
    writable(st, ObserveOp) and at.phase == Admitted and not(st.owners.get(at.owner).reachable) and st.runs.get(a._1._1).inbox.length() < QUEUE_LIMIT
  }
  pure def applyLose(st: State, a: AttemptId): State = {
    val ef = st.effects.get(a._1)
    val updated = {...mark(touchHistory(st, a._1._1), "unknown"), attempts: st.attempts.setBy(a, at => {...at, phase: UnknownAttempt, observed: at.observed.union(Set(Lost))}), effects: st.effects.set(a._1, {...ef, revision: ef.revision + 1})}
    becomeUnknown(updated, a._1)
  }
  pure def canObserve(st: State, a: AttemptId, owner: int): bool = {
    val at = st.attempts.get(a)
    writable(st, ObserveOp) and at.phase != Unused and at.owner == owner and at.actual != NoObservation and not(at.observed.contains(at.actual)) and st.runs.get(a._1._1).inbox.length() < QUEUE_LIMIT
  }
  pure def applyObservePayload(st: State, a: AttemptId, payload: int): State = {
    val at = st.attempts.get(a)
    val ef = st.effects.get(a._1)
    val updated = {...mark(touchHistory(st, a._1._1), "observe"), attempts: st.attempts.set(a, {...at, phase: ObservationRecorded, observed: at.observed.union(Set(at.actual))}), effects: st.effects.set(a._1, {...ef, revision: ef.revision + 1})}
    if (ef.result != NoResult) updated
    else if (at.actual == Success) recordOutcome(updated, a._1, OkResult, Success, false, payload)
    else if (unresolved(updated, a._1, a)) becomeUnknown(updated, a._1)
    else if (at.actual == Failure and not(ef.failureConclusive)) becomeUnknown(updated, a._1)
    else if (at.actual == Failure) recordOutcome(updated, a._1, ErrorResult, Failure, false, payload)
    else if (admitted(updated, a._1)) updated
    else {...updated, effects: updated.effects.setBy(a._1, e => {...e, phase: Pending})}
  }
  pure def applyObserve(st: State, a: AttemptId): State = applyObservePayload(st, a, 0)
  pure def canResolve(st: State, e: EffectId, revision: int, op: Operation): bool = and {
    writable(st, op), st.effects.get(e).exists, st.effects.get(e).revision == revision,
    op == AuditOp or (st.effects.get(e).phase == Unknown and st.effects.get(e).result == NoResult and not(admitted(st, e)) and st.runs.get(e._1).lifetime == Open),
    st.runs.get(e._1).inbox.length() < QUEUE_LIMIT,
  }
  pure def applyResolvePayload(st: State, e: EffectId, op: Operation, payload: int, source: int, evidence: int): State = {
    val ef = st.effects.get(e)
    val fact: ResolutionFact = {effect: e, operation: op, revision: ef.revision, source: source, evidence: evidence, payload: payload}
    val updated = {...st, resolutions: st.resolutions.union(Set(fact))}
    val changed = {...mark(touchHistory(updated, e._1), if (op == AuditOp) "audit" else if (op == SettleOp) "settle" else "repeat"), effects: st.effects.set(e, {...ef, revision: ef.revision + 1})}
    if (op == SettleOp) recordOutcome(changed, e, OkResult, NoObservation, true, payload)
    else if (op == RepeatOp) {...changed, effects: changed.effects.setBy(e, f => {...f, permit: f.permitsIssued + 1, permitsIssued: f.permitsIssued + 1})}
    else changed
  }
  pure def applyResolve(st: State, e: EffectId, op: Operation): State = applyResolvePayload(st, e, op, 0, 0, 1)
  pure def canOwnerFault(st: State, owner: int, death: bool): bool = st.owners.get(owner).alive and (death or st.owners.get(owner).reachable)
  pure def applyOwnerFault(st: State, owner: int, death: bool): State =
    {...mark(st, if (death) "ownerDeath" else "disconnect"), owners: st.owners.set(owner, {alive: not(death), reachable: false})}
  pure def canReconnect(st: State, owner: int): bool = st.owners.get(owner).alive and not(st.owners.get(owner).reachable)
  pure def applyReconnect(st: State, owner: int): State = {...mark(st, "reconnect"), owners: st.owners.setBy(owner, o => {...o, reachable: true})}
  pure def applyProvider(st: State, r: int, changeDomain: bool): State = {
    val pr = st.providers.get(r)
    {...mark(st, "provider"), providers: st.providers.set(r, {...pr, generation: pr.generation + 1, configuration: pr.configuration + 1, domain: pr.domain + (if (changeDomain) 1 else 0)})}
  }
  // Historical branch/import and operation-specific gateway use this same state.
  pure def canFork(st: State, src: int, dst: int, boundary: int, check: ImportCheck): bool = {
    val rr = st.runs.get(src)
    writable(st, ForkOp) and rr.exists and not(st.runs.get(dst).exists) and src != dst and check == ValidImport and
    (if (rr.boundaries.indices().contains(boundary)) rr.boundaries.nth(boundary).valid else false)
  }
  pure def applyFork(st: State, src: int, dst: int, boundary: int): State = {
    val b = st.runs.get(src).boundaries.nth(boundary)
    val q = if (b.progress == Ready) List(input(Continuation, (dst, 0), b.revision, -1)) else List()
    val rr = {...emptyRun(true), definition: b.definition, scope: st.runs.get(dst).scope, requiredResource: st.runs.get(src).requiredResource, app: b.app, revision: b.revision, progress: b.progress, lifetime: b.lifetime, result: b.result, mode: Suspended, inbox: q, parent: src, origin: b, boundaries: List(b), history: 1}
    mark(putRun(st, dst, rr), "fork")
  }
  pure def importError(check: ImportCheck): Error = match check {
    | ValidImport => NoError | MissingData => InvalidData | BadVersion => IncompatibleVersion
    | MissingResource => UnavailableResource | BadData => InvalidData | ExcessiveData => ResourceLimit | MissingPermission => Forbidden
  }
  pure def inputError(st: State, r: int, key: int, payload: int): Error = {
    val rc = st.receipts.get(key)
    if (not(st.authenticated)) Unauthenticated
    else if (not(st.permissions.contains(InputOp))) Forbidden
    else if (rc.valid and (rc.operation != InputOp or rc.target != r or rc.payload != payload)) KeyConflict
    else if (rc.valid) NoError
    else if (not(st.writes) or not(st.roles.contains(AuthorityRole))) AuthorityUnavailable
    else if (st.runs.get(r).lifetime != Open) InvalidTransition
    else if (not(st.runs.get(r).exists)) InvalidData
    else if (st.runs.get(r).inbox.length() >= QUEUE_LIMIT) ResourceLimit
    else NoError
  }
  pure def canRetryInput(st: State, r: int, key: int, payload: int): bool = permitted(st, InputOp) and st.receipts.get(key).valid and inputError(st, r, key, payload) == NoError
  pure def applyRetryInput(st: State): State = {...mark(st, "retry"), acknowledged: true, receiptReads: st.receiptReads + 1}
  pure def applyRejectInput(st: State, r: int, key: int, payload: int): State = {...mark(st, "reject"), error: inputError(st, r, key, payload)}
  pure def applyProviderFault(st: State, r: int, fault: ProviderFault): State = {
    val pr = st.providers.get(r)
    {...mark(st, "providerFault"), providers: st.providers.set(r, {...pr, present: if (fault == ProviderAbsent) not(pr.present) else pr.present, compatible: if (fault == IncompatibleProvider) not(pr.compatible) else pr.compatible, dependencies: if (fault == DependencyAbsent) not(pr.dependencies) else pr.dependencies, protection: if (fault == ProtectionExpired) not(pr.protection) else pr.protection})}
  }
  // G08 inspects useful protocol moves, excluding takeover/fault/environment toggles.
  pure def usefulEnabled(st: State): bool = or {
    RUNS.exists(r => canControllerReady(st, r) or (COMMAND_IDS.exists(k => not(st.commandReceipts.get(k).valid)) and (canDispose(st, r) or canControl(st, r, Active)))),
    COMMAND_IDS.exists(k => not(st.commandReceipts.get(k).valid)) and PROPOSALS.exists(p => canCommit(st, p) or canFail(st, p)),
    RUNS.exists(r => SLOTS.exists(slot => Set(WaitStep, InvokeStep, ContinueStep, FinishStep, FaultStep).exists(k => canEvaluate(st, r, k, slot)))),
    COMMAND_IDS.exists(k => not(st.commandReceipts.get(k).valid)) and EFFECTS.exists(e => ATTEMPT_SLOTS.exists(ai => OWNERS.exists(o => canAdmit(st, e, (e, ai), o, st.effects.get(e).revision, st.runs.get(e._1).controller)))),
    ATTEMPTS.exists(a => canEnter(st, a, st.attempts.get(a).owner) or canPrecheckReject(st, a) or canComplete(st, a) or (COMMAND_IDS.exists(k => not(st.commandReceipts.get(k).valid)) and OBSERVATION_IDS.exists(k => not(st.observationIds.get(k).valid)) and (canLose(st, a) or canObserve(st, a, st.attempts.get(a).owner)))),
  }
  pure def classifiedBlocked(st: State): bool = or {
    not(st.writes), not(st.roles.contains(AuthorityRole)), not(st.authenticated),
    not(COMMAND_IDS.exists(k => not(st.commandReceipts.get(k).valid))),
    RUNS.filter(r => st.runs.get(r).exists).forall(r => {
      val rr = st.runs.get(r)
      rr.lifetime != Open or rr.mode == Suspended or not(st.permissions.contains(ControlOp)) or (hasHead(st, r) and not(st.roles.contains(ComputeRole))) or
      (rr.cursor == rr.inbox.length() and EFFECTS.filter(e => e._1 == r and st.effects.get(e).exists and st.effects.get(e).phase != Consumed).forall(e => {
        val ef = st.effects.get(e)
        if (ef.phase == OutcomeRecorded) false
        else if (admitted(st, e)) {
          not(st.roles.contains(ExecuteRole)) or not(st.permissions.contains(ObserveOp)) or rr.inbox.length() >= QUEUE_LIMIT or
          not(OBSERVATION_IDS.exists(k => not(st.observationIds.get(k).valid)))
        }
        else not(st.permissions.contains(AdmitOp)) or not(st.permissions.contains(ResourceOp)) or not(eligibleProvider(st, r)) or resolvedProvider(st, r).resource != ef.resource or not(recoveryAllowed(st, e)) or (rr.externalController and not(rr.controllerReady)) or
          not(OWNERS.exists(o => st.owners.get(o).alive and freshRecoveryOwner(st, e, o))) or
          not(ATTEMPT_SLOTS.exists(ai => st.attempts.get((e, ai)).phase == Unused))
      }))
    }),
  }
  // Closed immutable command envelopes. Authorization precedes receipt access;
  // exact retained envelopes precede current lifecycle/epoch/revision conditions.
  pure def commandOperation(c: Command): Operation = match c.tag {
    | CreationCommand => CreateOp | InputCommand => InputOp | AdmissionCommand => AdmitOp
    | ObservationCommand => ObserveOp | LossCommand => ObserveOp
    | ResolutionCommand => c.decision | BranchCommand => ForkOp | ArchiveCommand => ForkOp
    | _ => ControlOp
  }
  pure def commandProposal(c: Command): Proposal = {valid: true, runId: c.runId, host: c.epoch, revision: c.revision, cursor: c.cursor, kind: c.stepKind, operation: c.operation, resource: c.resource, slot: c.slot, policy: c.policy, intent: c.intent, failureConclusive: c.failureConclusive}
  pure def proposalCommand(st: State, p: int, tag: CommandKind): Command = {
    val pp = st.proposals.get(p)
    {...emptyCommand, tag: tag, runId: pp.runId, epoch: pp.host, revision: pp.revision, cursor: pp.cursor, stepKind: pp.kind, operation: pp.operation, resource: pp.resource, slot: pp.slot, policy: pp.policy, intent: pp.intent, failureConclusive: pp.failureConclusive}
  }
  pure def observationEqual(st: State, c: Command): bool = {
    val old = st.observationIds.get(c.observationId)
    old.attempt == ((c.runId, c.slot), c.attempt) and old.owner == c.owner and old.provider == c.provider and old.resource == c.resource and old.generation == c.generation and old.domain == c.domain and old.intent == c.intent and old.observation == c.observation and old.payload == c.payload
  }
  pure def freshBodyError(st: State, c: Command): Error = {
    val r = c.runId
    val e = (r, c.slot)
    val a = (e, c.attempt)
    val rr = st.runs.get(r)
    val ef = st.effects.get(e)
    if (not(st.writes) or not(st.roles.contains(AuthorityRole))) AuthorityUnavailable
    else match c.tag {
      | CreationCommand => if (rr.exists) InvalidTransition else if (c.definition < 0 or c.definition > 2 or c.payload < 0 or c.payload > 1 or (c.progress != Ready and c.progress != Waiting)) InvalidData else if (not(st.resources.get(c.resource).available) or not(st.resources.get(c.resource).permitted)) UnavailableResource else NoError
      | InputCommand => {
        val old = st.inputIds.get((r, c.inputId))
        if (old.valid) { if (old.payload == c.payload) NoError else KeyConflict }
        else if (not(rr.exists) or rr.lifetime != Open) InvalidTransition
        else if (rr.inbox.length() >= QUEUE_LIMIT) ResourceLimit else NoError
      }
      | AdmissionCommand => if (c.revision != ef.revision or c.intent != ef.intent or c.epoch != rr.controller or c.provider != providerId(st, r) or c.resource != ef.resource or c.generation != resolvedProvider(st, r).generation or c.domain != resolvedProvider(st, r).domain) StalePermission else if (canAdmit(st, e, a, c.owner, c.revision, c.epoch)) NoError else InvalidTransition
      | ObservationCommand => {
        if (st.observationIds.get(c.observationId).valid) { if (observationEqual(st, c)) NoError else KeyConflict }
        else if (st.attempts.get(a).phase == Unused or st.attempts.get(a).owner != c.owner or st.attempts.get(a).provider != c.provider or st.attempts.get(a).resource != c.resource or st.attempts.get(a).generation != c.generation or st.attempts.get(a).domain != c.domain or st.attempts.get(a).intentAtGrant != c.intent or st.attempts.get(a).actual != c.observation or c.observation == NoObservation or c.observation == Lost or c.payload < 0 or c.payload > 1) InvalidData
        else if (rr.inbox.length() >= QUEUE_LIMIT) ResourceLimit else NoError
      }
      | LossCommand => {
        if (st.observationIds.get(c.observationId).valid) { if (observationEqual(st, c)) NoError else KeyConflict }
        else if (st.attempts.get(a).owner != c.owner or st.attempts.get(a).provider != c.provider or st.attempts.get(a).resource != c.resource or st.attempts.get(a).generation != c.generation or st.attempts.get(a).domain != c.domain or st.attempts.get(a).intentAtGrant != c.intent or st.owners.get(c.owner).reachable or (st.attempts.get(a).phase != Admitted and st.attempts.get(a).phase != UnknownAttempt) or c.observation != Lost) InvalidData
        else if (rr.inbox.length() >= QUEUE_LIMIT) ResourceLimit else NoError
      }
      | ResolutionCommand =>
        if (c.source < 0 or c.source > 1 or c.evidence < 1 or c.evidence > 2 or c.payload < 0 or c.payload > 1 or not(Set(AuditOp, SettleOp, RepeatOp).contains(c.decision))) InvalidData
        else if (c.revision != ef.revision) StalePermission
        else if (c.decision != AuditOp and ef.result != NoResult) AlreadyResolved
        else if (canResolve(st, e, c.revision, c.decision)) NoError else InvalidTransition
      | ModeCommand => if (c.epoch != rr.host) StalePermission else if (canControl(st, r, c.mode)) NoError else InvalidTransition
      | HostCommand => if (c.epoch != rr.host) StalePermission else if (canTakeover(st, r)) NoError else InvalidTransition
      | ControllerCommand => if (c.epoch != rr.controller) StalePermission else if (canTakeover(st, r)) NoError else InvalidTransition
      | BusinessCommand => {
        val held = {...st, proposals: st.proposals.set(0, commandProposal(c))}
        if (not(currentProposal(held, 0))) StalePermission else if (canCommit(held, 0)) NoError else InvalidTransition
      }
      | FailureCommand => {
        val held = {...st, proposals: st.proposals.set(0, commandProposal(c))}
        if (not(currentProposal(held, 0))) StalePermission else if (canFail(held, 0)) NoError else InvalidTransition
      }
      | DispositionCommand => if (c.epoch != rr.host or c.revision != rr.revision or c.cursor != rr.cursor) StalePermission else if (canDispose(st, r)) NoError else InvalidTransition
      | BranchCommand => if (canFork(st, r, c.dst, c.boundary, c.validation)) NoError else NotStable
      | ArchiveCommand => if (c.validation != ValidImport) importError(c.validation) else if (canFork(st, r, c.dst, c.boundary, c.validation)) NoError else NotStable
    }
  }
  pure def commandError(st: State, id: int, c: Command): Error =
    if (not(st.authenticated)) Unauthenticated
    else if (not(st.permissions.contains(commandOperation(c)))) Forbidden
    else if (not(COMMAND_IDS.contains(id))) ResourceLimit
    else {
      val saved = st.commandReceipts.get(id)
      if (saved.valid) { if (saved.body == c) NoError else KeyConflict }
      else if (not(RUNS.contains(c.runId)) or not(RUNS.contains(c.resource)) or not(RUNS.contains(c.provider)) or not(RUNS.contains(c.dst)) or not(SLOTS.contains(c.slot)) or not(ATTEMPT_SLOTS.contains(c.attempt)) or not(OWNERS.contains(c.owner)) or not(COMMANDS.contains(c.inputId)) or not(OBSERVATION_IDS.contains(c.observationId))) InvalidData else freshBodyError(st, c)
    }
  pure def nextCommandId(st: State): int = COMMAND_IDS.filter(k => not(st.commandReceipts.get(k).valid)).fold(COMMAND_LIMIT, (acc, k) => if (k < acc) k else acc)
  pure def admissionEnvelope(st: State, e: EffectId, a: AttemptId, owner: int, revision: int, controller: int): Command = {
    val pr = resolvedProvider(st, e._1)
    {...emptyCommand, tag: AdmissionCommand, runId: e._1, slot: e._2, attempt: a._2, owner: owner, provider: providerId(st, e._1), resource: st.effects.get(e).resource, generation: pr.generation, domain: pr.domain, intent: st.effects.get(e).intent, revision: revision, epoch: controller}
  }
  pure def observationEnvelope(st: State, a: AttemptId, observation: Observation): Command = {
    val at = st.attempts.get(a)
    val free = OBSERVATION_IDS.filter(k => not(st.observationIds.get(k).valid)).fold(8, (acc, k) => if (k < acc) k else acc)
    {...emptyCommand, tag: if (observation == Lost) LossCommand else ObservationCommand, runId: a._1._1, slot: a._1._2, attempt: a._2, owner: at.owner, provider: at.provider, resource: at.resource, generation: at.generation, domain: at.domain, intent: at.intentAtGrant, observationId: free, observation: observation}
  }
  pure def dispositionEnvelope(st: State, r: int): Command = {...emptyCommand, tag: DispositionCommand, runId: r, epoch: st.runs.get(r).host, revision: st.runs.get(r).revision, cursor: st.runs.get(r).cursor}
  pure def resolutionEnvelope(e: EffectId, revision: int, op: Operation): Command = {...emptyCommand, tag: ResolutionCommand, runId: e._1, slot: e._2, revision: revision, decision: op}
  pure def controlEnvelope(st: State, r: int, mode: Mode): Command = {...emptyCommand, tag: ModeCommand, runId: r, mode: mode, epoch: st.runs.get(r).host}
  pure def takeoverEnvelope(st: State, r: int, controller: bool): Command = {...emptyCommand, tag: if (controller) ControllerCommand else HostCommand, runId: r, epoch: if (controller) st.runs.get(r).controller else st.runs.get(r).host}
  pure def applyCommandBody(st: State, c: Command): State = {
    val r = c.runId
    val e = (r, c.slot)
    val a = (e, c.attempt)
    match c.tag {
      | CreationCommand => {
        val q = if (c.progress == Ready) List(input(Continuation, (r, 0), 0, -1)) else List()
        val b = {...emptyBoundary, valid: true, app: c.payload, progress: c.progress, definition: c.definition}
        mark(putRun(st, r, {...emptyRun(true), scope: st.runs.get(r).scope, requiredResource: c.resource, definition: c.definition, app: c.payload, progress: c.progress, inbox: q, boundaries: List(b)}), "start")
      }
      | InputCommand => {
        val old = st.inputIds.get((r, c.inputId))
        val rr = st.runs.get(r)
        if (old.valid) mark(st, "inputReplay")
        else {...mark(putRun(st, r, {...rr, inbox: rr.inbox.append(input(External, (r, 0), c.payload, c.inputId))}), "input"), inputIds: st.inputIds.set((r, c.inputId), {valid: true, payload: c.payload, sequence: rr.inbox.length()})}
      }
      | AdmissionCommand => applyAdmit(st, e, a, c.owner)
      | ObservationCommand => if (st.observationIds.get(c.observationId).valid) mark(st, "observationReplay") else {
        val updated = applyObservePayload(st, a, c.payload)
        {...updated, observationIds: st.observationIds.set(c.observationId, {valid: true, provider: c.provider, resource: c.resource, attempt: a, owner: c.owner, generation: c.generation, domain: c.domain, intent: c.intent, observation: c.observation, payload: c.payload})}
      }
      | LossCommand => if (st.observationIds.get(c.observationId).valid) mark(st, "observationReplay") else {
        val updated = applyLose(st, a)
        {...updated, observationIds: st.observationIds.set(c.observationId, {valid: true, provider: c.provider, resource: c.resource, attempt: a, owner: c.owner, generation: c.generation, domain: c.domain, intent: c.intent, observation: Lost, payload: c.payload})}
      }
      | ResolutionCommand => {
        val updated = applyResolvePayload(st, e, c.decision, c.payload, c.source, c.evidence)
        val fact: ResolutionFact = {effect: e, operation: c.decision, revision: c.revision, source: c.source, evidence: c.evidence, payload: c.payload}
        {...updated, resolutions: st.resolutions.union(Set(fact))}
      }
      | ModeCommand => applyControl(st, r, c.mode)
      | HostCommand => applyTakeover(st, r, false)
      | ControllerCommand => applyTakeover(st, r, true)
      | BusinessCommand => applyCommit({...st, proposals: st.proposals.set(0, commandProposal(c))}, 0)
      | FailureCommand => applyFail({...st, proposals: st.proposals.set(0, commandProposal(c))}, 0)
      | DispositionCommand => applyDispose(st, r)
      | BranchCommand => applyFork(st, r, c.dst, c.boundary)
      | ArchiveCommand => applyFork(st, r, c.dst, c.boundary)
    }
  }
  pure def applyCommand(st: State, id: int, c: Command): State = {
    val saved = st.commandReceipts.get(id)
    if (saved.valid) {...mark(st, "commandRetry"), acknowledged: true, receiptReads: st.receiptReads + 1}
    else {
      val changed = applyCommandBody(st, c)
      // One command is one Run history revision, independent of how many records
      // its pure update changes. Existing input/observation IDs have separate roles.
      val updated = putRun(changed, c.runId, {...changed.runs.get(c.runId), history: st.runs.get(c.runId).history + 1})
      val receipt: CommandReceipt = {valid: true, body: c, history: updated.runs.get(c.runId).history, stateRevision: updated.runs.get(c.runId).revision, executionRevision: updated.effects.get((c.runId, c.slot)).revision}
      {...updated, commandReceipts: st.commandReceipts.set(id, receipt), acknowledged: true}
    }
  }
  var s: State
  // Keep only the previous facts read by transition assertions; no duplicate local
  // providers/proposals/queues. This reduces symbolic state without losing a seam.
  type Previous = { view: View, receipts: int -> Receipt, boundaries: int -> List[Boundary] }
  pure def snapshot(st: State): Previous = {view: project(st), receipts: st.receipts, boundaries: RUNS.mapBy(r => st.runs.get(r).boundaries)}
  var previousState: Previous
  val previous = previousState.view
  action advance(updated: State): bool = all { s' = updated, previousState' = snapshot(s) }
  action init = all { s' = initial, previousState' = snapshot(initial) }
  action command(id: int, body: Command): bool = all { commandError(s, id, body) == NoError, advance(applyCommand(s, id, body)) }
  action rejectCommand(id: int, body: Command): bool = all { commandError(s, id, body) != NoError, advance({...mark(s, "commandRejected"), error: commandError(s, id, body)}) }
  action freshObservation(body: Command): bool = { nondet id = OBSERVATION_IDS.filter(k => not(s.observationIds.get(k).valid)).oneOf() freshCommand({...body, observationId: id}) }
  action freshCommand(body: Command): bool = { nondet id = COMMAND_IDS.filter(k => not(s.commandReceipts.get(k).valid)).oneOf() command(id, body) }
  action send(body: Command): bool = command(nextCommandId(s), body)
  action submit(r: int, key: int, payload: int): bool = send({...emptyCommand, runId: r, inputId: key, payload: payload})
  action commitEnvelope(p: int): bool = send(proposalCommand(s, p, BusinessCommand))
  action disposeEnvelope(r: int): bool = send(dispositionEnvelope(s, r))
  action setMode(r: int, mode: Mode): bool = send(controlEnvelope(s, r, mode))
  action claim(r: int, controller: bool): bool = send(takeoverEnvelope(s, r, controller))
  action authorize(e: EffectId, a: AttemptId, owner: int, revision: int, controller: int): bool = send(admissionEnvelope(s, e, a, owner, revision, controller))
  action report(a: AttemptId, owner: int): bool = all {owner == s.attempts.get(a).owner, send(observationEnvelope(s, a, s.attempts.get(a).actual))}
  action reportLoss(a: AttemptId): bool = send(observationEnvelope(s, a, Lost))
  action decide(e: EffectId, revision: int, op: Operation): bool = send(resolutionEnvelope(e, revision, op))
  action branchEnvelope(src: int, dst: int, boundary: int, check: ImportCheck): bool = send({...emptyCommand, tag: BranchCommand, runId: src, dst: dst, boundary: boundary, validation: check})
  action appendInput(r: int, key: int, payload: int): bool = all { canInput(s, r, key), advance(applyInput(s, r, key, payload)) }
  action evaluate(r: int, p: int, kind: ProposalKind, slot: int, policy: Policy): bool = all { canEvaluate(s, r, kind, slot), s.runs.get(r).definition == 0 or policy == NonRepeatable, advance(applyEvaluate(s, r, p, kind, slot, policy)) }
  action commit(p: int): bool = all { canCommit(s, p), advance(applyCommit(s, p)) }
  action dispose(r: int): bool = all { canDispose(s, r), advance(applyDispose(s, r)) }
  action failRun(p: int): bool = all { canFail(s, p), advance(applyFail(s, p)) }
  action control(r: int, mode: Mode): bool = all { canControl(s, r, mode), advance(applyControl(s, r, mode)) }
  action takeover(r: int, controller: bool): bool = all { canTakeover(s, r), advance(applyTakeover(s, r, controller)) }
  action admit(e: EffectId, a: AttemptId, owner: int, revision: int, controller: int): bool = all { canAdmit(s, e, a, owner, revision, controller), advance(applyAdmit(s, e, a, owner)) }
  action enter(a: AttemptId, owner: int): bool = all { canEnter(s, a, owner), advance(applyEnter(s, a, owner)) }
  action precheckReject(a: AttemptId): bool = all { canPrecheckReject(s, a), advance(applyPrecheckReject(s, a)) }
  action complete(a: AttemptId, observation: Observation): bool = all { canComplete(s, a), observation == Success or observation == Failure, advance(applyComplete(s, a, observation)) }
  action lose(a: AttemptId): bool = all { canLose(s, a), advance(applyLose(s, a)) }
  action observe(a: AttemptId, owner: int): bool = all { canObserve(s, a, owner), advance(applyObserve(s, a)) }
  action resolve(e: EffectId, revision: int, op: Operation): bool = all { canResolve(s, e, revision, op), advance(applyResolve(s, e, op)) }
  pure def canControllerReady(st: State, r: int): bool = st.runs.get(r).exists and st.runs.get(r).externalController and not(st.runs.get(r).controllerReady)
  action controllerReady(r: int): bool = all { canControllerReady(s, r), advance(mark(putRun(s, r, {...s.runs.get(r), controllerReady: true}), "controllerReady")) }
  pure def canAutomaticAdmit(st: State, e: EffectId, a: AttemptId, owner: int, revision: int, controller: int): bool = not(st.runs.get(e._1).externalController) and canAdmit(st, e, a, owner, revision, controller)
  action automaticAdmit(e: EffectId, a: AttemptId, owner: int, revision: int, controller: int): bool = all { canAutomaticAdmit(s, e, a, owner, revision, controller), advance(applyAdmit(s, e, a, owner)) }
  action ownerFault(owner: int, death: bool): bool = all { canOwnerFault(s, owner, death), advance(applyOwnerFault(s, owner, death)) }
  action reconnect(owner: int): bool = all { canReconnect(s, owner), advance(applyReconnect(s, owner)) }
  action replaceProvider(r: int, domain: bool): bool = all { s.runs.get(r).exists, advance(applyProvider(s, r, domain)) }
  action fork(src: int, dst: int, boundary: int, check: ImportCheck): bool = all { canFork(s, src, dst, boundary, check), advance(applyFork(s, src, dst, boundary)) }
  action rejectImport(check: ImportCheck): bool = all { check != ValidImport, advance({...mark(s, "rejectImport"), error: importError(check)}) }
  action retryInput(r: int, key: int, payload: int): bool = all { canRetryInput(s, r, key, payload), advance(applyRetryInput(s)) }
  action rejectInput(r: int, key: int, payload: int): bool = all { inputError(s, r, key, payload) != NoError, advance(applyRejectInput(s, r, key, payload)) }
  action loseAcknowledgement = all { s.acknowledged, advance({...mark(s, "lostAck"), error: CommitUnknown}) }
  action rejectProposal(p: int): bool = all { s.proposals.get(p).valid, not(currentProposal(s, p)), advance({...mark(s, "stale"), error: StalePermission, proposals: s.proposals.setBy(p, pp => {...pp, valid: false})}) }
  action loseProposal(p: int): bool = all { s.proposals.get(p).valid, advance({...mark(s, "lostProposal"), proposals: s.proposals.setBy(p, pp => {...pp, valid: false})}) }
  action writeAvailability = advance({...mark(s, "writes"), writes: not(s.writes)})
  action uiConnection = advance({...mark(s, "ui"), ui: not(s.ui)})
  action authentication = advance({...mark(s, "auth"), authenticated: not(s.authenticated)})
  action permission(op: Operation): bool = advance({...mark(s, "permission"), permissions: if (s.permissions.contains(op)) s.permissions.exclude(Set(op)) else s.permissions.union(Set(op))})
  action role(role: Role): bool = advance({...mark(s, "role"), roles: if (s.roles.contains(role)) s.roles.exclude(Set(role)) else s.roles.union(Set(role))})
  action scopeIsolation(scope: int): bool = advance({...mark(s, "scope"), scopes: s.scopes.setBy(scope, sc => {...sc, isolated: not(sc.isolated)})})
  action resourceAvailability(resource: int): bool = advance({...mark(s, "resource"), resources: s.resources.setBy(resource, res => {...res, available: not(res.available)})})
  action resourcePermission(resource: int): bool = advance({...mark(s, "resourcePermission"), resources: s.resources.setBy(resource, res => {...res, permitted: not(res.permitted)})})
  action providerResource(provider: int, resource: int): bool = advance({...mark(s, "providerResource"), providers: s.providers.setBy(provider, pr => {...pr, resource: resource})})
  action failureDeclaration(provider: int): bool = advance({...mark(s, "declaration"), providers: s.providers.setBy(provider, pr => {...pr, failureConclusive: not(pr.failureConclusive)})})
  pure def readError(st: State, op: Operation, r: int, boundary: int, resource: int): Error =
    if (not(st.authenticated)) Unauthenticated else if (not(st.permissions.contains(op))) Forbidden
    else if (not(st.roles.contains(AuthorityRole))) AuthorityUnavailable
    else if (op == ResourceOp) { if (not(st.resources.get(resource).permitted)) Forbidden else if (not(st.resources.get(resource).available)) UnavailableResource else NoError }
    else if (not(st.runs.get(r).exists)) InvalidData
    else if (op == ExportOp) { if (not(st.runs.get(r).boundaries.indices().contains(boundary))) InvalidData else if (not(st.runs.get(r).boundaries.nth(boundary).valid)) NotStable else NoError }
    else NoError
  action inspect(r: int): bool = all {readError(s, InspectOp, r, 0, 0) == NoError, advance({...mark(s, "inspect"), queryReads: s.queryReads + 1})}
  action exportBoundary(r: int, boundary: int): bool = all {readError(s, ExportOp, r, boundary, 0) == NoError, advance({...mark(s, "export"), exports: s.exports.union(Set((r, s.runs.get(r).boundaries.nth(boundary))))})}
  action resourceAccess(resource: int): bool = all {readError(s, ResourceOp, 0, 0, resource) == NoError, advance(mark(s, "resourceAccess"))}
  action rejectRead(op: Operation, r: int, boundary: int, resource: int): bool = all {readError(s, op, r, boundary, resource) != NoError, advance({...mark(s, "readRejected"), error: readError(s, op, r, boundary, resource)})}
  action providerFault(r: int, fault: ProviderFault): bool = all { s.runs.get(r).exists, advance(applyProviderFault(s, r, fault)) }
  // Select enabled participants inside each component action. A random unused ID
  // must not truncate exploration or crowd out a legal transition on another Run.
  action computeStep = any {
    { nondet r = RUNS.filter(r => canDispose(s, r)).oneOf() freshCommand({...emptyCommand, tag: DispositionCommand, runId: r, epoch: s.runs.get(r).host, revision: s.runs.get(r).revision, cursor: s.runs.get(r).cursor}) },
    { nondet p = PROPOSALS.filter(p => canCommit(s, p)).oneOf() freshCommand(proposalCommand(s, p, BusinessCommand)) },
    { nondet p = PROPOSALS.filter(p => canFail(s, p)).oneOf() freshCommand(proposalCommand(s, p, FailureCommand)) },
    {
      nondet r = RUNS.filter(r => active(s, r) and hasHead(s, r) and not(obsolete(s, r))).oneOf()
      nondet p = PROPOSALS.oneOf()
      nondet slot = SLOTS.oneOf()
      nondet kind = Set(InvokeStep, ContinueStep, WaitStep, FinishStep, FaultStep).filter(k => canEvaluate(s, r, k, slot)).oneOf()
      nondet policy = Set(NonRepeatable, Idempotent, Deduplicated).filter(policy => s.runs.get(r).definition == 0 or policy == NonRepeatable).oneOf()
      evaluate(r, p, kind, slot, policy)
    },
  }
  action executionStep = any {
    {
      nondet e = EFFECTS.filter(e => stAdmittable(s, e)).oneOf()
      nondet ai = ATTEMPT_SLOTS.filter(ai => s.attempts.get((e, ai)).phase == Unused).oneOf()
      nondet owner = OWNERS.filter(o => canAdmit(s, e, (e, ai), o, s.effects.get(e).revision, s.runs.get(e._1).controller)).oneOf()
      freshCommand(admissionEnvelope(s, e, (e, ai), owner, s.effects.get(e).revision, s.runs.get(e._1).controller))
    },
    { nondet a = ATTEMPTS.filter(a => canEnter(s, a, s.attempts.get(a).owner)).oneOf() enter(a, s.attempts.get(a).owner) },
    { nondet a = ATTEMPTS.filter(a => canPrecheckReject(s, a)).oneOf() precheckReject(a) },
    { nondet a = ATTEMPTS.filter(a => canComplete(s, a)).oneOf() nondet observation = Set(Success, Failure).oneOf() complete(a, observation) },
    { nondet a = ATTEMPTS.filter(a => canLose(s, a)).oneOf() freshObservation(observationEnvelope(s, a, Lost)) },
    { nondet a = ATTEMPTS.filter(a => canObserve(s, a, s.attempts.get(a).owner)).oneOf() freshObservation(observationEnvelope(s, a, s.attempts.get(a).actual)) },
    { nondet op = Set(AuditOp, SettleOp, RepeatOp).oneOf() nondet e = EFFECTS.filter(e => canResolve(s, e, s.effects.get(e).revision, op)).oneOf() freshCommand({...emptyCommand, tag: ResolutionCommand, runId: e._1, slot: e._2, decision: op, revision: s.effects.get(e).revision}) },
  }
  pure def stAdmittable(st: State, e: EffectId): bool = ATTEMPT_SLOTS.exists(ai => OWNERS.exists(o => canAdmit(st, e, (e, ai), o, st.effects.get(e).revision, st.runs.get(e._1).controller)))
  action gatewayStep = any {
    { nondet r = RUNS.filter(r => not(s.runs.get(r).exists)).oneOf() nondet definition = Set(0, 1, 2).oneOf() nondet progress = Set(Ready, Waiting).oneOf() freshCommand({...emptyCommand, tag: CreationCommand, runId: r, definition: definition, progress: progress}) },
    { nondet r = RUNS.filter(r => s.runs.get(r).exists).oneOf() nondet key = COMMANDS.oneOf() freshCommand({...emptyCommand, tag: InputCommand, runId: r, inputId: key, payload: 1}) },
    { nondet key = COMMAND_IDS.filter(k => s.commandReceipts.get(k).valid).oneOf() command(key, s.commandReceipts.get(key).body) },
    { nondet key = COMMAND_IDS.filter(k => s.commandReceipts.get(k).valid).oneOf() rejectCommand(key, {...s.commandReceipts.get(key).body, payload: s.commandReceipts.get(key).body.payload + 1}) },
    {nondet r = RUNS.oneOf() inspect(r)},
    {nondet r = RUNS.oneOf() nondet b = s.runs.get(r).boundaries.indices().oneOf() exportBoundary(r, b)},
    {nondet resource = RUNS.oneOf() resourceAccess(resource)},
    loseAcknowledgement,
    {
      nondet src = RUNS.filter(r => s.runs.get(r).exists).oneOf()
      nondet dst = RUNS.filter(r => not(s.runs.get(r).exists)).oneOf()
      nondet b = s.runs.get(src).boundaries.indices().filter(i => s.runs.get(src).boundaries.nth(i).valid).oneOf()
      nondet tag = Set(BranchCommand, ArchiveCommand).oneOf()
      freshCommand({...emptyCommand, tag: tag, runId: src, dst: dst, boundary: b})
    },
  }
  action controlStep = {
    nondet r = RUNS.filter(r => s.runs.get(r).exists).oneOf()
    nondet p = PROPOSALS.oneOf()
    any { freshCommand({...emptyCommand, tag: ModeCommand, runId: r, mode: Active, epoch: s.runs.get(r).host}), freshCommand({...emptyCommand, tag: ModeCommand, runId: r, mode: Suspended, epoch: s.runs.get(r).host}), freshCommand({...emptyCommand, tag: HostCommand, runId: r, epoch: s.runs.get(r).host}), freshCommand({...emptyCommand, tag: ControllerCommand, runId: r, epoch: s.runs.get(r).controller}), controllerReady(r), rejectProposal(p), loseProposal(p) }
  }
  action environmentStep = {
    nondet owner = OWNERS.oneOf()
    nondet r = RUNS.filter(r => s.runs.get(r).exists).oneOf()
    nondet fault = Set(ProviderAbsent, IncompatibleProvider, DependencyAbsent, ProtectionExpired).oneOf()
    nondet op = OPERATIONS.oneOf()
    nondet roleKind = Set(InteractionRole, ComputeRole, ExecuteRole, AuthorityRole).oneOf()
    nondet resource = RUNS.oneOf()
    any { role(roleKind), scopeIsolation(r), resourceAvailability(resource), resourcePermission(resource), providerResource(r, resource), failureDeclaration(r), all { s.grants.exists(g => g.owner == owner), ownerFault(owner, false) }, all { s.grants.exists(g => g.owner == owner), ownerFault(owner, true) }, reconnect(owner), replaceProvider(r, false), replaceProvider(r, true), providerFault(r, fault), writeAvailability, uiConnection, authentication, permission(op) }
  }
  action step = any { computeStep, executionStep, gatewayStep, controlStep, environmentStep }
  val inputWitness = s.performed.contains("input")
  val commitWitness = s.performed.contains("commit")
  // Global obligations inspect retained evidence and previous-state projections.
  val G01 = and {
    previousState.receipts.keys().forall(k => not(previousState.receipts.get(k).valid) or s.receipts.get(k) == previousState.receipts.get(k)),
    EFFECTS.forall(e => not(previous.effects.get(e).exists) or (s.effects.get(e).exists and s.effects.get(e).intent == previous.effects.get(e).intent and s.effects.get(e).token == previous.effects.get(e).token and s.effects.get(e).resource == previous.effects.get(e).resource and s.effects.get(e).operation == previous.effects.get(e).operation and s.effects.get(e).policy == previous.effects.get(e).policy and s.effects.get(e).failureConclusive == previous.effects.get(e).failureConclusive)),
    RUNS.forall(r => previous.runs.get(r).exists implies (s.runs.get(r).exists and s.runs.get(r).history >= previous.runs.get(r).history)),
  }
  val G02 = and {
    s.grants.exclude(previous.grants).forall(g => previous.attempts.keys().filter(a => a._1 == g.attempt._1 and (previous.attempts.get(a).phase == UnknownAttempt or (previous.effects.get(a._1).phase == Unknown and not(previous.effects.get(a._1).failureConclusive) and previous.attempts.get(a).observed.contains(Failure)))).forall(a => previous.attempts.get(a).owner != g.owner)),
    s.entries.forall(en => s.grants.exists(g => g.attempt == en.attempt and g.owner == en.owner and g.provider == en.provider and g.resource == en.resource and g.generation == en.generation and g.domain == en.domain and g.intent == en.intent and g.token == en.token)),
    ATTEMPTS.forall(a => s.attempts.get(a).calls <= 1 and s.grants.filter(g => g.attempt == a).size() <= 1),
    s.grants.forall(g => (g.priorUnknownDomains.size() == 0 or g.permit > 0 or g.policy == Idempotent or (g.policy == Deduplicated and g.protection and g.priorUnknownDomains == Set(g.domain))) and (not(g.externalController) or g.controllerReady) and g.active and g.controller == g.currentController and s.effects.get(g.attempt._1).exists and s.effects.get(g.attempt._1).intent == g.intent and s.attempts.get(g.attempt).owner == g.owner),
    s.grants.filter(g => g.permit > 0).forall(g => s.grants.filter(h => h.attempt._1 == g.attempt._1 and h.permit == g.permit).size() == 1),
    EFFECTS.forall(e => ATTEMPTS.filter(a => a._1 == e and s.attempts.get(a).phase == Admitted).size() <= 1),
  }
  val G03 = and {
    EFFECTS.forall(e => {
      val ef = s.effects.get(e)
      val unresolvedEarlier = ATTEMPTS.exists(a => a._1 == e and s.attempts.get(a).phase == UnknownAttempt)
      and { ef.replyCount <= 1, (ef.result != NoResult) iff (ef.replyCount == 1), s.outcomes.filter(o => o.effect == e).forall(o => o.result != ErrorResult or o.settled or (o.unresolvedAtChoice.size() == 0 and ef.failureConclusive)),
        not(unresolvedEarlier) or ef.result != NoResult or ef.phase == Unknown or ef.phase == Executing,
        s.outcomes.filter(o => o.effect == e).size() == ef.replyCount,
        s.outcomes.filter(o => o.effect == e).forall(o => o.payload == ef.resultPayload),
        previous.effects.get(e).result == NoResult or (ef.result == previous.effects.get(e).result and ef.resultPayload == previous.effects.get(e).resultPayload),
        ef.result == NoResult or ef.settled or ATTEMPTS.exists(a => a._1 == e and s.attempts.get(a).observed.contains(ef.provenance)),
        s.runs.get(e._1).inbox.select(i => i.kind == TerminalReply and i.effect == e).length() == ef.replyCount,
      }
    }),
    ATTEMPTS.forall(a => previous.attempts.get(a).observed.subseteq(s.attempts.get(a).observed)),
    ATTEMPTS.forall(a => {
      val at = s.attempts.get(a)
      (not(at.observed.contains(Lost)) or at.observed.contains(Success) or at.observed.contains(Failure) or at.observed.contains(NotExecuted) or at.phase == UnknownAttempt) and
      (not(at.observed.contains(NotExecuted)) or at.calls == 0)
    }),
  }
  val G04 = and {
    s.commits.forall(f => f.host == f.currentHost and f.active and (if (f.disposition == Applied) f.newRevision == f.oldRevision + 1 and f.appAfter == f.appBefore + 1 and (f.kind != Continuation or f.inputRevision == f.oldRevision) and (f.kind != Uncertainty or f.terminalAtCommit == NoResult) and (f.kind != TerminalReply or f.terminalAtCommit != NoResult) and f.created.forall(e => s.effects.get(e).exists) else f.newRevision == f.oldRevision and f.appAfter == f.appBefore)),
    RUNS.forall(r => s.runs.get(r).cursor >= 0 and s.runs.get(r).cursor <= s.runs.get(r).inbox.length() and s.runs.get(r).inbox.indices().forall(i => (i < s.runs.get(r).cursor) iff (s.runs.get(r).inbox.nth(i).disposition != Queued))),
    s.commits.forall(f => s.commits.filter(g => g.runId == f.runId and g.cursor == f.cursor).size() == 1),
  }
  val G05 = and {
    RUNS.forall(r => s.runs.get(r).lifetime != Finished or EFFECTS.filter(e => e._1 == r).forall(e => not(s.effects.get(e).exists) or s.effects.get(e).phase == Consumed)),
    RUNS.forall(r => previous.runs.get(r).lifetime == Open or (s.runs.get(r).lifetime == previous.runs.get(r).lifetime and s.runs.get(r).mode == previous.runs.get(r).mode and s.runs.get(r).host == previous.runs.get(r).host and s.runs.get(r).controller == previous.runs.get(r).controller)),
    EFFECTS.forall(e => s.effects.get(e).phase != Consumed or s.runs.get(e._1).inbox.indices().exists(idx => { val i = s.runs.get(e._1).inbox.nth(idx) i.kind == TerminalReply and i.effect == e and i.disposition == Applied })),
    RUNS.forall(r => s.runs.get(r).lifetime != Failed or s.runs.get(r).inbox.indices().forall(idx => s.runs.get(r).inbox.nth(idx).disposition != Queued)),
  }
  val G06 = and {
    RUNS.forall(r => {
      val rr = s.runs.get(r)
      rr.parent < 0 or (rr.origin.valid and s.runs.get(rr.parent).boundaries.indices().exists(idx => s.runs.get(rr.parent).boundaries.nth(idx) == rr.origin) and rr.origin.prefix.forall(e => e._1 != r) and rr.origin.results.map(x => x._1) == rr.origin.prefix)
    }),
    s.grants.forall(g => g.token._1 == g.attempt._1._1),
    RUNS.forall(r => s.runs.get(r).inbox.indices().forall(idx => { val i = s.runs.get(r).inbox.nth(idx) i.kind == External or i.effect._1 == r })),
    RUNS.forall(r => previous.runs.get(r).exists implies previousState.boundaries.get(r).indices().forall(i => s.runs.get(r).boundaries.nth(i) == previousState.boundaries.get(r).nth(i))),
  }
  // Model-level dependency direction. Actual imports/APIs need implementation evidence.
  pure val dependencyEdges = Set((1, 0), (2, 0), (2, 1), (3, 0), (3, 1), (3, 2), (4, 3), (5, 4))
  val G07 = dependencyEdges.forall(edge => edge._1 > edge._2) and s.effects.keys() == EFFECTS and s.runs.keys() == RUNS
  val G08 = usefulEnabled(s) or classifiedBlocked(s)
  val referenceSafety = allowed(previous, project(s))
  val architectureSafety = and { G01, G02, G03, G04, G05, G06, G07, G08, referenceSafety }
  // Direct alias: no integer truth-indicator encoding is used.
  val modelCheckSafety = architectureSafety
  val admissionWitness = s.performed.contains("admit")
  val entryWitness = s.performed.contains("enter")
  val unknownWitness = s.performed.contains("unknown")
  val observationWitness = s.performed.contains("observe")
  val repeatWitness = s.performed.contains("repeat")
  val settlementWitness = s.performed.contains("settle")
  val consumptionWitness = EFFECTS.exists(e => s.effects.get(e).phase == Consumed)
  val recoveryConsumedWitness = EFFECTS.exists(e => s.effects.get(e).phase == Consumed and ATTEMPTS.filter(a => a._1 == e and s.attempts.get(a).phase != Unused).size() > 1)
  val branchNewWorkWitness = RUNS.exists(r => s.runs.get(r).parent >= 0 and EFFECTS.exists(e => e._1 == r and s.effects.get(e).exists))
  val forkWitness = s.performed.contains("fork")
  val finishedWitness = RUNS.exists(r => s.runs.get(r).lifetime == Finished)
  val failedWitness = RUNS.exists(r => s.runs.get(r).lifetime == Failed)
  val disposalWitness = s.performed.contains("dispose")

  val evaluateWitness = s.performed.contains("evaluate")
  val precheckWitness = s.performed.contains("precheck")
  val completeWitness = s.performed.contains("complete")
  val auditWitness = s.performed.contains("audit")
  val suspendWitness = s.performed.contains("suspend")
  val resumeWitness = s.performed.contains("resume")
  val takeoverWitness = s.performed.contains("takeover")
  val controllerReadyWitness = s.performed.contains("controllerReady")
  val controllerWitness = s.performed.contains("controller")
  val ownerDeathWitness = s.performed.contains("ownerDeath")
  val disconnectWitness = s.performed.contains("disconnect")
  val reconnectWitness = s.performed.contains("reconnect")
  val providerWitness = s.performed.contains("provider")
  val providerFaultWitness = s.performed.contains("providerFault")
  val retryWitness = s.performed.contains("retry") or s.performed.contains("commandRetry")
  val rejectWitness = s.performed.contains("reject") or s.performed.contains("commandRejected")
  val lostAckWitness = s.performed.contains("lostAck")
  val staleWitness = s.performed.contains("stale")
  val lostProposalWitness = s.performed.contains("lostProposal")
  val writesWitness = s.performed.contains("writes")
  val uiWitness = s.performed.contains("ui")
  val authWitness = s.performed.contains("auth")
  val permissionWitness = s.performed.contains("permission")

  pure val effect = (0, 0)
  pure val attempt = (effect, 0)
  pure val recoveryFixture = {
    val st0 = applyCommand(initial, 0, {...emptyCommand, inputId: 0, payload: 1})
    val evaluated = applyEvaluate(st0, 0, 0, InvokeStep, 0, NonRepeatable)
    val st1 = applyCommand(evaluated, 1, proposalCommand(evaluated, 0, BusinessCommand))
    val st2 = applyCommand(st1, 2, admissionEnvelope(st1, effect, attempt, 0, 0, 0))
    val st3 = applyOwnerFault(applyEnter(st2, attempt, 0), 0, false)
    applyCommand(st3, 3, observationEnvelope(st3, attempt, Lost))
  }
  action recoveryInit = all { s' = recoveryFixture, previousState' = snapshot(recoveryFixture) }
}
module architectureSmall {
  import architecture(RUNS = Set(0), SLOTS = Set(0), ATTEMPT_SLOTS = Set(0, 1), QUEUE_LIMIT = 8, COMMAND_LIMIT = 32).*
}
module architectureAnalysis {
  import architecture(RUNS = Set(0, 1), SLOTS = Set(0, 1), ATTEMPT_SLOTS = Set(0, 1, 2), QUEUE_LIMIT = 12, COMMAND_LIMIT = 32).*
}

// All components/faults remain enabled; reduced cardinalities for symbolic checks.
module architectureBounded {
  import architecture(RUNS = Set(0, 1), SLOTS = Set(0), ATTEMPT_SLOTS = Set(0, 1), QUEUE_LIMIT = 4, COMMAND_LIMIT = 10).*
}

// Same global state/transition functions, with a documented reachable recovery fixture.
module architectureRecoveryAnalysis {
  import architectureTypes.* from "./types"
  import architecture(RUNS = Set(0, 1), SLOTS = Set(0, 1), ATTEMPT_SLOTS = Set(0, 1, 2), QUEUE_LIMIT = 12, COMMAND_LIMIT = 32).*

}

// Conditional progress is deliberately stronger than fairness: a deterministic
// scheduler serves one restored-availability recovery, with no further faults or
// input generation. It uses the SAME authority/provider/FIFO transition functions.
module architectureProgressAnalysis {
  import architectureTypes.* from "./types"
  import architecture(RUNS = Set(0, 1), SLOTS = Set(0, 1), ATTEMPT_SLOTS = Set(0, 1, 2), QUEUE_LIMIT = 12, COMMAND_LIMIT = 32).*
  pure val nextAttempt = (effect, 1)
  pure def progressRank(st: State): int = {
    val ef = st.effects.get(effect)
    val at = st.attempts.get(nextAttempt)
    if (ef.phase == Consumed) 0
    else if (ef.result != NoResult) {
      if (obsolete(st, 0)) 4
      else if (currentProposal(st, 0)) 2 else 3
    }
    else if (at.phase == Admitted) {
      if (not(at.entered)) 7 else if (at.actual == NoObservation) 6 else 5
    }
    else if (ef.permit > 0) 8 else 9
  }
  pure def progressMove(st: State): State = {
    val ef = st.effects.get(effect)
    val at = st.attempts.get(nextAttempt)
    if (ef.result != NoResult) {
      if (obsolete(st, 0)) applyCommand(st, nextCommandId(st), dispositionEnvelope(st, 0))
      else if (currentProposal(st, 0)) applyCommand(st, nextCommandId(st), proposalCommand(st, 0, BusinessCommand))
      else applyEvaluate(st, 0, 0, WaitStep, 0, NonRepeatable)
    }
    else if (at.phase == Admitted) {
      if (not(at.entered)) applyEnter(st, nextAttempt, 1)
      else if (at.actual == NoObservation) applyComplete(st, nextAttempt, Success)
      else applyCommand(st, nextCommandId(st), observationEnvelope(st, nextAttempt, st.attempts.get(nextAttempt).actual))
    }
    else if (ef.permit > 0) applyCommand(st, nextCommandId(st), admissionEnvelope(st, effect, nextAttempt, 1, ef.revision, st.runs.get(0).controller))
    else applyCommand(st, nextCommandId(st), resolutionEnvelope(effect, ef.revision, RepeatOp))
  }
  pure def canProgress(st: State): bool = {
    val ef = st.effects.get(effect)
    val at = st.attempts.get(nextAttempt)
    if (ef.phase == Consumed) false
    else if (ef.result != NoResult) {
      if (obsolete(st, 0)) commandError(st, nextCommandId(st), dispositionEnvelope(st, 0)) == NoError
      else if (currentProposal(st, 0)) commandError(st, nextCommandId(st), proposalCommand(st, 0, BusinessCommand)) == NoError
      else canEvaluate(st, 0, WaitStep, 0)
    }
    else if (at.phase == Admitted) {
      if (not(at.entered)) canEnter(st, nextAttempt, 1)
      else if (at.actual == NoObservation) canComplete(st, nextAttempt)
      else commandError(st, nextCommandId(st), observationEnvelope(st, nextAttempt, at.actual)) == NoError
    }
    else if (ef.permit > 0) commandError(st, nextCommandId(st), admissionEnvelope(st, effect, nextAttempt, 1, ef.revision, st.runs.get(0).controller)) == NoError
    else commandError(st, nextCommandId(st), resolutionEnvelope(effect, ef.revision, RepeatOp)) == NoError
  }
  var age: int
  var priorRank: int
  action progressInit = all { recoveryInit, age' = 0, priorRank' = progressRank(recoveryFixture) }
  action progressStep = all { canProgress(s), advance(progressMove(s)), age' = age + 1, priorRank' = progressRank(s) }
  val progressEnvelopeComplete = s.effects.get(effect).phase == Consumed and s.commandReceipts.keys().filter(k => s.commandReceipts.get(k).valid).size() == 9
  val conditionalProgress = (age == 0 or progressRank(s) < priorRank) and (age < 8 or s.effects.get(effect).phase == Consumed)
  val conditionalSafety = architectureSafety and conditionalProgress and (s.effects.get(effect).phase == Consumed or canProgress(s))
}
