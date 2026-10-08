// Independent observable transition rules. No component eligibility helper is imported.
// Internal events may have the same projection; this is a relation, not executable stutter.
module architectureReference {
  import architectureTypes.* from "./types"
  type RunView = { exists: bool, definition: int, scope: int, requiredResource: int, app: int, revision: int, history: int, cursor: int, mode: Mode, lifetime: Lifetime, host: int, controller: int, externalController: bool, controllerReady: bool, headKind: Kind, headEffect: EffectId, headRevision: int, length: int, progress: Progress, result: int, inbox: List[Input] }
  type EffectView = { exists: bool, operation: int, resource: int, intent: int, token: EffectId, resultPayload: int, policy: Policy, failureConclusive: bool, phase: Phase, revision: int, result: Result, permit: int }
  type AttemptView = { phase: AttemptPhase, provider: int, resource: int, owner: int, domain: int, generation: int, intent: int, actual: Observation, calls: int, observed: Set[Observation] }
  type ProviderView = { id: int, resource: int, resourceAvailable: bool, resourcePermitted: bool, generation: int, domain: int, present: bool, compatible: bool, dependencies: bool, protection: bool }
  type View = { roles: Set[Role], exports: Set[(int, Boundary)], runs: int -> RunView, effects: EffectId -> EffectView, attempts: AttemptId -> AttemptView, providers: int -> ProviderView, permissions: Set[Operation], writes: bool, authenticated: bool, liveOwners: Set[int], lostOwners: Set[int], inputs: Set[(int, int, Kind, EffectId)], intents: Set[(EffectId, int)], grants: Set[Grant], entries: Set[Entry], outcomes: Set[OutcomeFact], commits: Set[CommitFact], lineage: Set[(int, int, Boundary)], boundaries: int -> List[Boundary], receipts: Set[(int, CommandReceipt)], resolutions: Set[ResolutionFact], inputKeys: Set[((int, int), InputKey)], observationKeys: Set[(int, ObservationKey)] }
  pure def project(st: State): View = {
    val rs = st.runs.keys()
    val runView = rs.mapBy(r => {
      val rr = st.runs.get(r)
      val h = if (rr.cursor < rr.inbox.length() and rr.cursor >= 0) rr.inbox.nth(rr.cursor) else {kind: External, effect: (r, 0), revision: 0, disposition: Queued, key: -1}
      {exists: rr.exists, definition: rr.definition, scope: rr.scope, requiredResource: rr.requiredResource, app: rr.app, revision: rr.revision, history: rr.history, cursor: rr.cursor, mode: rr.mode, lifetime: rr.lifetime, host: rr.host, controller: rr.controller, externalController: rr.externalController, controllerReady: rr.controllerReady, headKind: h.kind, headEffect: h.effect, headRevision: h.revision, length: rr.inbox.length(), progress: rr.progress, result: rr.result, inbox: rr.inbox}
    })
    {roles: st.roles, exports: st.exports, runs: runView, effects: st.effects.keys().mapBy(e => {exists: st.effects.get(e).exists, operation: st.effects.get(e).operation, resource: st.effects.get(e).resource, intent: st.effects.get(e).intent, token: st.effects.get(e).token, resultPayload: st.effects.get(e).resultPayload, policy: st.effects.get(e).policy, failureConclusive: st.effects.get(e).failureConclusive, phase: st.effects.get(e).phase, revision: st.effects.get(e).revision, result: st.effects.get(e).result, permit: st.effects.get(e).permit}), attempts: st.attempts.keys().mapBy(a => {phase: st.attempts.get(a).phase, provider: st.attempts.get(a).provider, resource: st.attempts.get(a).resource, owner: st.attempts.get(a).owner, domain: st.attempts.get(a).domain, generation: st.attempts.get(a).generation, intent: st.attempts.get(a).intentAtGrant, actual: st.attempts.get(a).actual, calls: st.attempts.get(a).calls, observed: st.attempts.get(a).observed}), providers: rs.mapBy(r => {
      val sc = st.scopes.get(st.runs.get(r).scope)
      val id = if (st.providers.get(sc.provider).present or sc.parent < 0 or sc.isolated) sc.provider else st.scopes.get(sc.parent).provider
      val pr = st.providers.get(id)
      {id: id, resource: pr.resource, resourceAvailable: st.resources.get(pr.resource).available, resourcePermitted: st.resources.get(pr.resource).permitted, generation: pr.generation, domain: pr.domain, present: pr.present, compatible: pr.compatible, dependencies: pr.dependencies, protection: pr.protection}
    }), permissions: st.permissions, writes: st.writes, authenticated: st.authenticated, liveOwners: st.owners.keys().filter(o => st.owners.get(o).alive), lostOwners: st.owners.keys().filter(o => not(st.owners.get(o).reachable)), inputs: rs.map(r => st.runs.get(r).inbox.indices().map(i => (r, i, st.runs.get(r).inbox.nth(i).kind, st.runs.get(r).inbox.nth(i).effect))).flatten(), intents: st.effects.keys().filter(e => st.effects.get(e).exists).map(e => (e, st.effects.get(e).intent)), grants: st.grants, entries: st.entries, outcomes: st.outcomes, commits: st.commits, lineage: rs.filter(r => st.runs.get(r).parent >= 0).map(r => (r, st.runs.get(r).parent, st.runs.get(r).origin)), boundaries: rs.mapBy(r => st.runs.get(r).boundaries), receipts: st.commandReceipts.keys().filter(k => st.commandReceipts.get(k).valid).map(k => (k, st.commandReceipts.get(k))), resolutions: st.resolutions, inputKeys: st.inputIds.keys().filter(k => st.inputIds.get(k).valid).map(k => (k, st.inputIds.get(k))), observationKeys: st.observationIds.keys().filter(k => st.observationIds.get(k).valid).map(k => (k, st.observationIds.get(k)))}
  }
  pure def grantAllowed(before: View, g: Grant): bool = {
    val r = before.runs.get(g.attempt._1._1)
    val e = before.effects.get(g.attempt._1)
    val pr = before.providers.get(g.attempt._1._1)
    val unknown = before.attempts.keys().filter(a => a._1 == g.attempt._1 and (before.attempts.get(a).phase == UnknownAttempt or (e.phase == Unknown and not(e.failureConclusive) and before.attempts.get(a).observed.contains(Failure))))
    and { before.writes, before.roles.contains(AuthorityRole), before.authenticated, before.permissions.contains(AdmitOp), r.mode == Active, r.lifetime == Open,
      e.exists, e.result == NoResult, g.revision == e.revision, g.controller == r.controller, g.intent == e.intent,
      before.attempts.get(g.attempt).phase == Unused, before.liveOwners.contains(g.owner), unknown.forall(a => before.attempts.get(a).owner != g.owner),
      not(before.attempts.keys().exists(a => a._1 == g.attempt._1 and before.attempts.get(a).phase == Admitted)),
      pr.present, pr.compatible, pr.dependencies, pr.resourceAvailable, pr.resourcePermitted, before.permissions.contains(ResourceOp), g.provider == pr.id, g.resource == pr.resource, g.resource == e.resource, g.generation == pr.generation, g.domain == pr.domain,
      not(r.externalController) or r.controllerReady, g.permit == e.permit,
      (unknown.size() == 0 and e.phase != Unknown) or e.permit > 0 or e.policy == Idempotent or (e.policy == Deduplicated and pr.protection and unknown.forall(a => before.attempts.get(a).domain == pr.domain)),
    }
  }
  pure def commitAllowed(before: View, c: CommitFact): bool = {
    val r = before.runs.get(c.runId)
    val terminal = before.effects.get(r.headEffect).result
    and { before.writes, before.roles.contains(AuthorityRole), before.authenticated, before.permissions.contains(ControlOp), r.mode == Active, r.lifetime == Open,
      r.cursor >= 0, r.cursor < r.length, c.cursor == r.cursor, c.oldRevision == r.revision, c.host == r.host, c.kind == r.headKind,
      c.inputRevision == r.headRevision, c.effect == r.headEffect,
      if (c.disposition == Applied) (c.kind != Continuation or r.headRevision == r.revision) and (c.kind != Uncertainty or terminal == NoResult)
      else if (c.disposition == StaleContinuation) r.headKind == Continuation and r.headRevision != r.revision
      else c.disposition == ObsoleteUncertainty and r.headKind == Uncertainty and terminal != NoResult,
    }
  }
  pure def receiptAllowed(before: View, pair: (int, CommandReceipt)): bool = {
    val saved = pair._2
    val c = saved.body
    val r = before.runs.get(c.runId)
    val e = before.effects.get((c.runId, c.slot))
    val op = if (c.tag == CreationCommand) CreateOp else if (c.tag == AdmissionCommand) AdmitOp else if (c.tag == InputCommand) InputOp else if (c.tag == ObservationCommand or c.tag == LossCommand) ObserveOp else if (c.tag == ResolutionCommand) c.decision else if (c.tag == BranchCommand or c.tag == ArchiveCommand) ForkOp else ControlOp
    and { before.writes, before.roles.contains(AuthorityRole), before.authenticated, before.permissions.contains(op), saved.history == r.history + 1,
      not(before.receipts.exists(old => old._1 == pair._1)),
      if (c.tag == AdmissionCommand) c.revision == e.revision and c.intent == e.intent and c.epoch == r.controller and c.provider == before.providers.get(c.runId).id and c.resource == e.resource and c.generation == before.providers.get(c.runId).generation and c.domain == before.providers.get(c.runId).domain else true,
      if (c.tag == CreationCommand) not(r.exists) and c.definition >= 0 and c.definition <= 2 and (c.progress == Ready or c.progress == Waiting) else true,
      if (c.tag == ResolutionCommand) c.revision == e.revision and c.source >= 0 and c.source <= 1 and c.evidence > 0 and c.evidence <= 2 else true,
      if (c.tag == ModeCommand or c.tag == HostCommand or c.tag == BusinessCommand or c.tag == FailureCommand or c.tag == DispositionCommand) c.epoch == r.host else true,
      if (c.tag == ObservationCommand or c.tag == LossCommand) c.provider == before.attempts.get(((c.runId, c.slot), c.attempt)).provider and c.resource == before.attempts.get(((c.runId, c.slot), c.attempt)).resource and c.owner == before.attempts.get(((c.runId, c.slot), c.attempt)).owner and c.generation == before.attempts.get(((c.runId, c.slot), c.attempt)).generation and c.domain == before.attempts.get(((c.runId, c.slot), c.attempt)).domain and c.intent == before.attempts.get(((c.runId, c.slot), c.attempt)).intent else true,
      if (c.tag == ModeCommand or c.tag == HostCommand or c.tag == ControllerCommand) r.lifetime == Open else true,
      if (c.tag == ControllerCommand) c.epoch == r.controller else true,
      if (c.tag == BusinessCommand and r.definition != 0) {
        val expected = if (r.definition == 1) {if (r.app == 0 or r.app == 2) InvokeStep else if (r.app == 1) ContinueStep else FinishStep} else if (r.app < 2) InvokeStep else FinishStep
        val operation = if (r.definition == 2) {if (r.app == 0) 1 else 0} else if (r.app < 2) 0 else 1
        c.stepKind == expected and c.operation == operation and c.resource == r.requiredResource and c.policy == NonRepeatable
      } else true,
      if (c.tag == BusinessCommand or c.tag == FailureCommand or c.tag == DispositionCommand) c.revision == r.revision and c.cursor == r.cursor else true,
    }
  }

  pure def allowed(before: View, after: View): bool = and {
    before.receipts.subseteq(after.receipts), before.inputKeys.subseteq(after.inputKeys), before.observationKeys.subseteq(after.observationKeys), before.resolutions.subseteq(after.resolutions),
    after.observationKeys.exclude(before.observationKeys).forall(pair => {
      val k = pair._2
      val at = before.attempts.get(k.attempt)
      and {before.writes, before.roles.contains(AuthorityRole), before.authenticated, before.permissions.contains(ObserveOp), at.phase != Unused, k.provider == at.provider, k.resource == at.resource, k.owner == at.owner, k.generation == at.generation, k.domain == at.domain, k.intent == at.intent,
        k.payload >= 0, k.payload <= 1,
        if (k.observation == Lost) before.lostOwners.contains(k.owner) and (at.phase == Admitted or at.phase == UnknownAttempt)
        else k.observation != NoObservation and k.observation == at.actual,
      }
    }),
    after.receipts.exclude(before.receipts).forall(pair => receiptAllowed(before, pair) and after.runs.get(pair._2.body.runId).history == pair._2.history and after.runs.get(pair._2.body.runId).revision == pair._2.stateRevision and after.effects.get((pair._2.body.runId, pair._2.body.slot)).revision == pair._2.executionRevision),
    after.resolutions.exclude(before.resolutions).forall(f => before.effects.get(f.effect).exists and f.revision == before.effects.get(f.effect).revision and f.source >= 0 and f.source <= 1 and f.evidence >= 1 and f.evidence <= 2 and before.permissions.contains(f.operation)),
    before.inputs.subseteq(after.inputs), before.intents.subseteq(after.intents),
    before.grants.subseteq(after.grants), before.entries.subseteq(after.entries), before.exports.subseteq(after.exports),
    after.exports.exclude(before.exports).forall(x => before.authenticated and before.roles.contains(AuthorityRole) and before.permissions.contains(ExportOp) and x._2.valid and before.boundaries.get(x._1).indices().exists(i => before.boundaries.get(x._1).nth(i) == x._2)),
    before.outcomes.subseteq(after.outcomes), before.commits.subseteq(after.commits), before.lineage.subseteq(after.lineage),
    after.intents.exclude(before.intents).forall(i => after.commits.exclude(before.commits).exists(c => c.created.contains(i._1))),
    after.grants.exclude(before.grants).forall(g => grantAllowed(before, g)),
    after.entries.exclude(before.entries).forall(en => before.roles.contains(ExecuteRole) and before.providers.get(en.attempt._1._1).id == en.provider and before.providers.get(en.attempt._1._1).resource == en.resource and before.providers.get(en.attempt._1._1).resourceAvailable and before.providers.get(en.attempt._1._1).resourcePermitted and before.permissions.contains(ResourceOp) and before.grants.exists(g => g.attempt == en.attempt and g.owner == en.owner and g.provider == en.provider and g.resource == en.resource and g.generation == en.generation and g.domain == en.domain and g.intent == en.intent and g.token == en.token)),
    after.outcomes.exclude(before.outcomes).forall(o =>
      not(before.outcomes.exists(old => old.effect == o.effect)) and
      after.inputs.exclude(before.inputs).filter(i => i._3 == TerminalReply and i._4 == o.effect).size() == 1 and
      (if (o.settled) before.effects.get(o.effect).phase == Unknown and after.resolutions.exclude(before.resolutions).exists(f => f.effect == o.effect and f.operation == SettleOp)
       else (o.provenance == Success or o.provenance == Failure) and before.attempts.keys().exists(a => a._1 == o.effect and before.attempts.get(a).actual == o.provenance) and (o.result != ErrorResult or before.effects.get(o.effect).failureConclusive and not(before.attempts.keys().exists(a => a._1 == o.effect and before.attempts.get(a).phase == UnknownAttempt and after.attempts.get(a).phase == UnknownAttempt))))),
    after.runs.keys().forall(r => {
      val old = before.runs.get(r)
      val now = after.runs.get(r)
      if (old.lifetime == Open and now.lifetime == Failed) and {
        before.writes, before.roles.contains(AuthorityRole), before.authenticated, before.permissions.contains(ControlOp), old.mode == Active,
        old.cursor >= 0, old.cursor < old.length,
        old.headKind != Continuation or old.headRevision == old.revision,
        old.headKind != Uncertainty or before.effects.get(old.headEffect).result == NoResult,
        now.app == old.app, now.revision == old.revision, now.cursor == now.length,
      } else if (old.exists and (now.mode != old.mode or now.host != old.host or now.controller != old.controller))
        old.lifetime == Open and before.writes and before.authenticated and before.permissions.contains(ControlOp)
      else if (old.exists and old.lifetime != Open) now.result == old.result and now.app == old.app else true
    }),
    after.commits.exclude(before.commits).forall(c => commitAllowed(before, c)),
    after.runs.keys().forall(r => after.runs.get(r).app == before.runs.get(r).app or after.commits.exclude(before.commits).exists(c => c.runId == r and c.appAfter == after.runs.get(r).app and c.disposition == Applied) or after.lineage.exclude(before.lineage).exists(l => l._1 == r and l._3.app == after.runs.get(r).app) or after.receipts.exclude(before.receipts).exists(pair => pair._2.body.tag == CreationCommand and pair._2.body.runId == r and pair._2.body.payload == after.runs.get(r).app)),
    after.runs.keys().forall(r => {
      val old = before.runs.get(r)
      val now = after.runs.get(r)
      if (old.exists) now.definition == old.definition and now.requiredResource == old.requiredResource and (now.history == old.history or now.history == old.history + 1)
      else if (now.exists and not(after.lineage.exists(l => l._1 == r)))
        after.receipts.exclude(before.receipts).exists(pair => {
          val c = pair._2.body
          c.tag == CreationCommand and c.runId == r and now.definition == c.definition and now.app == c.payload and now.progress == c.progress and now.lifetime == Open and now.mode == Active and now.revision == 0 and now.cursor == 0 and now.host == 0 and now.controller == 0 and now.requiredResource == c.resource and now.length == (if (c.progress == Ready) 1 else 0) and now.inbox.indices().forall(i => now.inbox.nth(i).kind == Continuation and now.inbox.nth(i).effect._1 == r and now.inbox.nth(i).revision == 0)
        }) else true
    }),
    after.runs.keys().forall(r => after.runs.get(r).cursor >= 0 and after.runs.get(r).cursor <= after.runs.get(r).length),
    after.runs.keys().filter(r => before.runs.get(r).exists).forall(r => after.boundaries.get(r).indices().filter(i => i >= before.boundaries.get(r).length()).forall(i => {
      val b = after.boundaries.get(r).nth(i)
      val rr = after.runs.get(r)
      val es = after.effects.keys().filter(e => e._1 == r and after.effects.get(e).exists)
      val stableNow = rr.lifetime != Failed and es.forall(e => after.effects.get(e).phase == Consumed) and rr.inbox.indices().forall(j => j < rr.cursor or (rr.inbox.nth(j).kind != TerminalReply and rr.inbox.nth(j).kind != Uncertainty))
      b.valid == stableNow and b.app == rr.app and b.revision == rr.revision and b.cursor == rr.cursor and b.definition == rr.definition and b.result == rr.result and b.progress == rr.progress and b.lifetime == rr.lifetime and b.prefix == es and b.results == es.map(e => (e, after.effects.get(e).result, after.effects.get(e).resultPayload)) and b.events == rr.inbox.indices().filter(j => j < rr.cursor).map(j => (j, rr.inbox.nth(j).kind, rr.inbox.nth(j).effect, rr.inbox.nth(j).disposition))
    })),
    after.lineage.exclude(before.lineage).forall(l => {
      val b = l._3
      val r = after.runs.get(l._1)
      and {before.writes, before.roles.contains(AuthorityRole), before.authenticated, before.permissions.contains(ForkOp), l._1 != l._2, not(before.runs.get(l._1).exists), before.runs.get(l._2).exists,
        before.boundaries.get(l._2).indices().exists(i => before.boundaries.get(l._2).nth(i) == b), b.valid, b.lifetime != Failed,
        r.exists, r.definition == b.definition, r.mode == Suspended, r.app == b.app, r.revision == b.revision, r.result == b.result, r.progress == b.progress, r.lifetime == b.lifetime,
        r.cursor == 0, r.host == 0, r.controller == 0, not(r.externalController),
        r.length == (if (b.progress == Ready) 1 else 0),
        r.inbox.indices().forall(i => r.inbox.nth(i).kind == Continuation and r.inbox.nth(i).effect._1 == l._1 and r.inbox.nth(i).revision == b.revision and r.inbox.nth(i).disposition == Queued),
        after.effects.keys().filter(e => e._1 == l._1).forall(e => not(after.effects.get(e).exists) and after.effects.get(e).permit == 0),
        after.attempts.keys().filter(a => a._1._1 == l._1).forall(a => after.attempts.get(a).phase == Unused),
      }
    }),
  }
}
