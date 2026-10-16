# Agent Orchestration and Node Role Composition — Execution Plan

## Final delivery bookkeeping

The user approved the five-commit split with "行". Work commits are 6b17a9a,
1987dcd, 8f67ebd, 82c8357 and 404c6b9. All revised-scope gates are accepted;
this record accompanies task archival, followed by the session journal.
Earlier unchecked review/commit checkpoints below are historical and superseded.
Physical-host acceptance was removed by the user; physical and live-provider
execution are not claimed. LSP coverage remains inconclusive.


## Parent accepted gate — 2026-10-16

Parent reviewed final independent86-test evidence (seed631927), AC matrix, actual
handoff and public admission/lifecycle source. Scoped child3 gate accepted; specs
synchronized, including guarded public Runtime submit and Agent/Node lifecycle.
Child4 may proceed under existing approval. Physical/release/live-provider evidence
remains separate; LSP inconclusive. Commit/archive deferred to final delivery.
Earlier pending/blocked checkpoints below are historical.

## CURRENT independent acceptance gate — blocker closed

- [x] Load curated check context, task and parent/prerequisite contracts and preceding independent lifecycle disposition.
- [x] Independently review public Runtime admission and complete Agent/Node integration; no remaining scoped blocker or product repair required.
- [x] Execute impacted Runtime32/Agent4/Node50 tests on named VM, seed631927:86 passed, no exclusions, all six distributed cases.
- [x] Verify four delayed admission stages observe owner DOWN before resume/no late execution; preserve nested cleanup, restart/idempotent inventory, terminal/ack retirement and correlations.
- [x] Compile warnings-as-errors, format, strict scoped Credo, existing-PLT Dialyzer, production dependency trees and whitespace pass; index empty.
- [x] Publish CURRENT check-report/verification/handoff with exact commands, hashes, AC1–AC5 and parent disposition and limitations.
- [x] Parent accepted child3/handoff, synchronized executable specs and activated child4; work committed in 8f67ebd.

Independent recommendation: **accept child3 and consumer handoff**. The last public
Runtime boundary blocker is closed. Later implementation/review checkpoints below
are historical. LSP remains inconclusive; physical/release/live-provider parent
criteria retain separate gates. This recheck changes only four child report/plan
files, preserving product source/tests and all unrelated dirty work/SBOM.

## Public Runtime admission repair — current implementation checkpoint

- [x] Reproduce public invalid_operation versus private OperationOwner ready-ref
  parity failure before source edits (`/tmp/admission-before.log`).
- [x] Keep Runtime-owned validation/live byte caps/IDs/refs/specs/error normalization;
  add optional local require_live_owner guard, including ignored startup.
- [x] Monitor before blocking init limits read; check liveness after that read and
  before/after selection; reject delayed dead-owner dispatch without retries.
- [x] Remove all private coordinator construction from OperationOwner.
- [x] Add public/consumer error parity, changed-cap/unavailable/capacity, dead-owner
  and four blocked-admission-stage DOWN-before-resume/no-late-work regressions.
- [x] Preserve generic healthy/remote-owner compatibility and guarded healthy work.
- [x] Run impacted86 named tests, seed458366, including both distributed suites;
  final affected47 tests, seed750289, after test alias/docs/remote-owner assertions.
- [x] Final compile/format/strict scoped Credo/existing-PLT Dialyzer/dependency/
  whitespace/index pass; document intermediate warnings/findings separately.
- [x] Publish exact changed files/commands/logs/hashes and limitations in current
  check-report/verification/handoff. LSP remains inconclusive.
- [ ] Independent recheck and parent acceptance; child4 remains blocked.

Current status is **ready for independent recheck only**, superseding earlier
implementation dispositions below. No child acceptance, task-state/index/commit,
root/config/dependency/lock/spec edits or external calls were performed.

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Activation Gate

Prerequisite gate satisfied on 2026-10-16: parent accepted child 1 and child 2
implementation/check evidence and their actual handoffs. Consume
`../10-16-operation-runtime/handoff.md` and `../10-16-harness-providers/handoff.md`
plus linked executable specs. Commit/archive bookkeeping is deferred to final
delivery; no speculative or weakened upstream contracts are authorized.

User approval of the complete parent/child plan authorizes sequential activation
without asking again for unchanged steps. Start only this child when its
prerequisites pass. Load before-dev context; one implementation writer at a time,
then Trellis quality check. Worker agents do not commit.

## Ordered Checklist

- [x] Verify child 1/2 handoffs; implement isolated caller/executor integration adapters.
- [x] Implement authority identity island, responsive Agent commands/loop and parallel joins.
- [x] Implement bounded snapshots/subscriptions, context/step/pending limits and turn-stop races.
- [x] Implement API-driven delegation/peer correlation/monitor/cleanup semantics.
- [x] Implement Node role configuration, provider lifecycle/readiness and coupled supervision.
- [x] Run multi-node/fault/role tests and publish CLI/release-facing contracts.
- [x] Run active changed-file diagnostics where available; absent LSP coverage is recorded.
- [x] Review parent AC mapping and this child acceptance; record verification/handoff.
- [ ] Update applicable executable-contract specs and follow finish-work process (parent-owned, outside this worker's exclusive write scope; independent trellis-check pending).

Implementation evidence: `verification.md` records the 91-test umbrella run before
bounded recovery closure, final-source 26-test Agent/Node named run including two
distributed tests, compile/format/Credo/Dialyzer/dependency/xref/whitespace gates,
and partial LSP coverage. `handoff.md` documents current public contracts. These
checks attest implementation evidence; they do not replace independent acceptance,
physical-host release testing, or parent-owned final bookkeeping.

## Validation

```bash
cd apps/beamlet_agent && mix test
cd apps/beamlet_node && mix test
# Root distributed-tag run must exercise actual loop, delegation and role faults.
```

Also run parent applicable formatting/compile/static/dependency/whitespace gates.
Commands are prospective, not passing evidence. For distributed tests, use isolated
names/cookies, bounded peer startup and teardown, message barriers and alternative
control for partition tests. Report actual executed test counts and skip reasons.
Consult parent implement.md for full integration and external-evidence requirements.

## Pause / Rollback Point

Do not block a GenServer callback awaiting model/Tool/child completion. Do not reserve executor capacity while waiting for Agents. Pause if contract changes would weaken result identity or introduce runtime→Harness dependencies.
On failure, preserve unrelated source/index changes and repair the owning seam;
do not continue adding dependent features to conceal a failed gate.


## Independent review disposition

Independent full Agent/Node review and scoped repairs completed; **acceptance
blocked**, not ready for child 4. See check-report.md for acceptance matrix and
verification.md for 34-test named-VM run plus quality gates. Remaining work:

- [ ] Move blocking infrastructure submission/control out of Agent callbacks with
  bounded ownership and late-created-work cleanup (Directory suspension repro).
- [ ] Gate delayed child creation against queued parent stop/loss before input.
- [ ] Bind progress attempt/sequence and terminal metadata to pending generation.
- [ ] Validate complete peer request/reply/retained envelopes against byte caps.
- [ ] Recheck these fixes with focused/distributed regressions before accepting.

Earlier completed implementation checkboxes describe delivered behavior, not an
independent acceptance sign-off. Parent owns spec/final bookkeeping as before.

## Remediation checkpoint

Loaded all curated context and current review artifacts. Confirmed five blockers in
Server/Caller/Delegation source. Plan: bounded operation owners isolate submit,
ack and cancellation, keep cleanup slots until DOWN and gate late submissions;
startup authorization barrier precedes child input; partial admission retains
monitors; progress binds attempt/sequence; peer sizing includes wire and retained
wrappers. Historical stall demonstration remains historical evidence only.
Acceptance remains blocked until final behavioral and static gates pass.

## Remediation final checkpoint

- [x] Isolate submit/ack/cancel and helper admission from live Agent callbacks.
- [x] Gate delayed child input on live parent authorization and queued stop/loss.
- [x] Retain partial admission cleanup accounting until DOWN.
- [x] Bind progress attempt/sequence/turn/ref and terminal metadata.
- [x] Count complete peer wire/retained envelopes at 8192-byte boundaries.
- [x] Run 42 impacted named-VM tests including both distributed tests, compile,
  format, strict scoped Credo, existing-PLT Dialyzer and whitespace.
- [ ] Parent independent recheck and final acceptance/bookkeeping.

See the current sections at the top of check-report.md, verification.md and
handoff.md; their older sections are explicitly historical evidence.

## Independent final recheck disposition

- [x] Independently review full source/context and execute final impacted gates.
- [x] Repair owner-loss-before-ready stuck turn with failing-then-passing regression.
- [x] Reject present/unavailable Directory instead of widening captured cap.
- [x] Final source: 44 passed including both distributed tests; compile/format/
  strict scoped Credo/existing-PLT Dialyzer/dependency/whitespace pass.
- [ ] Bound operation-owner admission and attach ownership to authority lifecycle.
- [ ] Bound delegation launcher/helper admission/cleanup across parent loss/stalls.
- [ ] Keep live terminal owners accounted until actual retirement, including ack block.
- [ ] Independently recheck lifecycle fixes, nested cleanup and final acceptance.

**Child 3 acceptance remains blocked; child 4 must not start.** Durable current
check-report/verification/handoff supersede older ready-for-recheck claims. The
remaining repair is a coordinated Agent-side lifecycle change, not an upstream
contract/spec/root change. LSP coverage remains inconclusive. Parent retains
bookkeeping/commit/spec work.

## Lifecycle redesign checkpoint (before source edits)

Use a nonblocking lifecycle controller per retained operation/delegation slot.
The controller monitors Agent and authority, owns a linked blocking worker, and
uses a fixed admission/total deadline. Stop/loss interrupts the worker with kill;
controller retirement waits for worker DOWN. Delegation workers link admitted
helpers; helpers link child Agents, so suspension cannot defer ownership loss.
Late admission must check/link the dead owner before business work. Operations
use an Agent-local guarded coordinator start seam to reject dead ownership before
Runtime initialization/dispatch. No replacement admission or retry occurs.
Terminal acceptance retains slots through controller DOWN; model/tool transitions
wait asynchronously for retired capacity. Authority infrastructure shutdown must
have finite shutdown bounds even when supervisors are suspended. Controller and
worker are both charged to one slot (at most two processes per operation, plus
one Task helper per delegation); nested children retain their own bounded slots.
Validation must assert DOWN before resuming suspended infrastructure, then assert
late creation cannot execute. Acceptance remains blocked pending implementation
and independent recheck.

## Lifecycle repair final checkpoint

- [x] Persist pre-edit lifecycle design above; implement controller/worker ownership.
- [x] Add authority Resources registry, per-kind quotas, group DOWN retirement,
  rejected/stale admission cleanup and VM-local old-generation readiness fence.
- [x] Preserve owner-loss-before-ready and present-Directory cap repairs.
- [x] Add eight lifecycle regressions, including actual DOWN before infrastructure
  resumes, forced registry restart, nested suspension and real native progress/ack.
- [x] Reconstructed pre-repair three-probe comparison fails intended assertions;
  final52 named tests pass, both distributed tests executed, seed318484.
- [x] Compile/format/strict scoped Credo/existing-PLT Dialyzer pass.
- [x] Save exact executable hashes, failed intermediates, ownership/counts and
  Implicit Assumption / Test Coverage Gap retrospective in current child reports.
- [ ] Independent recheck and acceptance (parent-owned); child4 remains blocked.

Registration-stage controllers monitor Agent/Resources before requesting quota;
no worker exists until quota grant. Resource-group accounting survives controller
kill and retains recorded workers/helpers/children until DOWN. New authority
readiness fences the previous VM-local PID inventory; no business state persists.
Healthy tool/model transitions wait asynchronously for completed-group retirement.
See current check-report/verification/handoff; older statuses are historical.


## Public Runtime admission repair — parent authorization

Parent authorizes the narrow owning-seam repair documented in design.md. Earlier
Agent/Node-only worker scopes are superseded solely for Runtime public submit,
coordinator admission and their focused tests. Preserve default generic submit
compatibility, all validation/current deployment caps/error normalization and
no-retry semantics; use optional local-owner guarding without callable injection.
Remove private Runtime construction from OperationOwner. Preserve every accepted
lifecycle/accounting fix. Reproduce parity failure before repair, then run impacted
Runtime/Agent/Node tests including distributed tests and static gates. Save exact
commands and limitations in current child reports. No dependency/root/config/spec/
task-state/index/commit edits by workers. Child 4 waits for independent recheck.

## Independent coordinated-lifecycle recheck — current disposition

- [x] Review curated context, parent/prerequisite contracts and complete scoped source.
- [x] Independently execute actual-DOWN, nested/restart/blocked-ack regressions and both distributed tests.
- [x] Repair duplicate Resources registration/tracking inventory with failing-before/passing-after test.
- [x] Final named53 tests, seed408204; compile/format/strict scoped Credo/existing-PLT Dialyzer/deps/whitespace pass.
- [x] Probe actual1024-per-kind registry rejection and fixed5s blocked-admission timeout.
- [ ] Parent coordinate public Runtime guarded submit seam; private coordinator adapter remains a boundary blocker.
- [ ] Recheck seam/parity and publish accepted consumer handoff before child4.

Current check-report/verification/handoff supersede earlier statuses. LSP remains
inconclusive; no upstream/root/config/lock/spec/parent/task-state/index/commit writes.
