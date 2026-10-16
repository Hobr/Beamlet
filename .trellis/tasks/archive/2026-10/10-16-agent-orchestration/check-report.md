# CURRENT independent acceptance gate — public admission blocker CLOSED

Fresh independent review recommends **parent acceptance of child 3 and its consumer
handoff**. No remaining scoped blocker was found. This recommendation does not
change task state or accept parent physical/release/live-provider criteria. Parent
may record child acceptance, synchronize executable specs, and then activate child4.
This CURRENT section supersedes all earlier pending/blocked dispositions below.

## Findings before and after

The preceding independent lifecycle review accepted bounded controller/worker
cleanup, terminal retirement and restart fencing but blocked private coordinator
construction. The public repair closes that concrete ownership defect:
OperationOwner calls only Runtime.submit/ack; Runtime owns Operation validation,
live Directory operation_bytes, owner/sink validation, IDs/specs/refs, capacity and
unavailable normalization. Source review and independent execution confirm this;
prior implementation counts were not used as contract proof. No product repair
or test change was needed in this recheck.

Runtime's optional require_live_owner:true accepts only local owner PIDs. Default
submission still accepts a remote owner (real peer test) and healthy generic and
guarded work completes. Dead guarded startup returns unavailable, including
DynamicSupervisor :ignore; max_children returns capacity. budget_ms:0, reduced
current cap after authority boot, missing Directory/supervisor and consumer error
parity are exercised. No Agent/Harness import/dependency or callable injection was
added to Runtime, and no retry/replacement path was found.

The supervisor-invoked start rejects dead guarded ownership; init monitors before
its blocking limits read and checks after it. Dispatch checks before and after
selection. Four delayed regressions observe owner DOWN while public limits,
supervisor admission, init limits or selection remains suspended, then resume and
assert no worker/retained coordinator. Selection additionally observes coordinator
DOWN. These guards reject observed death; a death after the final check still uses
the installed monitor and existing best-effort cleanup. No atomic-death or external
rollback guarantee is implied.

Lifecycle integrity remains affirmative after public-submit integration: independent
execution includes actual controller/worker DOWN before supervisor/Directory resume,
Resources restart inventory fencing and idempotent registration/tracking, nested
suspended children/helpers, partial helper admission, genuine native progress and
terminal with coordinator suspended during acknowledgement, retained owner slots
until retirement, healthy follow-on input, progress attempt/sequence/terminal
correlation, peer full envelopes, subscriber credit/coalescing, complete invalid
batch rejection and reversed parallel Tool joins. Quota predicates and fixed5s/65s
timers were source-reviewed; this pass does not claim a new1024-slot load probe or
65-second elapsed-time test. All seven role subsets are checked structurally;
actual executor-only and combined-role paths are exercised.

## AC and parent disposition

| Gate | Independent contract evidence | Disposition |
| --- | --- | --- |
| Child AC1; parent AC3/AC6 Agent portions | Three-role real peer loop, executor-side workspace, wrong model/environment no fallback | Pass within same-host scope |
| Child AC2; parent AC7 | Whole invalid sibling batch dispatches zero; concurrent Agents reverse Tool completion and retain original IDs/order | Pass |
| Child AC3; parent AC8 | Zero-slot waiting parent, correlated child loss, nested stop/loss cleanup, late isolation and independent peers | Pass |
| Child AC4; parent AC9 Agent portion | Same-channel snapshot first, bounded credits/coalescing, sink DOWN and context bounds | Pass |
| Child AC5; parent AC10 Agent/Node portion | Registry/provider/gateway faults, restart fence, seven role configurations, executor-only and local gateway | Pass |
| Parent R1/R3/R7 admission boundary | Public submit/ack only; current caps, normalized failures, delayed-owner guards and remote default compatibility | Blocker closed |
| Parent AC12 scoped gate | Independent86 tests and static/dependency/whitespace gates below | Pass; LSP inconclusive |
| Parent AC2/AC11 physical, AC5 live smoke, AC10 release | Outside this gate | Pending parent/child4; no claim |

Independent final exact-source run: Runtime32 + Agent4 + Node50 = **86 passed**,
seed631927, no exclusions, all six distributed cases (Runtime4/Node2). Compile
warnings-as-errors, format, strict scoped Credo73 files/575 mods-funs, existing-PLT
Dialyzer0 errors, three production dependency trees and scoped whitespace pass.
Index remains empty. Exact commands, logs and hashes are in CURRENT verification.
Intentional gateway/Registry kill logs are expected fault evidence. No failed gate
was masked. Only four child report/plan files are written by this recheck.

Residual limits: active Expert processes exist but no callable complete current
changed-path diagnostic query is exposed; LSP is inconclusive. Same-host peers do
not prove physical-host behavior. No live/paid provider, release boot, hostile
filesystem confinement, hard RSS or external cancellation acceptance was attempted.
Existing dirty work and user SBOM were preserved; no staging or commits.

---

# Historical public Runtime admission repair — ready for independent recheck

The sole public-admission blocker is repaired in the authorized owning seam.
**This is implementation evidence only: child3 is not accepted and child4 must
not start until parent independent recheck/acceptance.** This section supersedes
all earlier dispositions below.

Before editing, `/tmp/admission-before.log` reproduced public rejection of
`budget_ms: 0` versus private OperationOwner returning a ready OperationRef.
After repair `/tmp/admission-after.log` shows both return invalid_operation,
with OperationOwner forwarding operation_failed and no ready ref.

Runtime.submit owns Operation validation, the current Directory operation_bytes
check, owner/sink validation, opaque ID/ref/spec creation, and normalization.
Optional `require_live_owner: true` requires a local PID; default mode retains
remote-owner compatibility. Ignored startup normalizes to unavailable, supervisor
max_children to capacity, and other startup errors/exits to unavailable. No retry,
callable injection, or Runtime dependency on Agent/Harness was introduced.
OperationOwner now calls only public Runtime.submit/ack and allocates no IDs/refs
or private coordinator specifications.

Runtime's supervisor-invoked start checks guarded ownership before starting;
init monitors owner before Directory.limits and checks liveness again after it.
Dispatch checks before and after Directory.select, so observed local owner death
during either blocking read cannot create late execution. Local liveness checks
are not an atomic guarantee against death after the final check; the installed
monitor and existing cleanup handle subsequent loss.

Behavioral evidence: new Runtime tests exercise healthy generic/guarded work,
invalid budget and owner/sink, changed/reduced live cap, retained capacity,
missing Directory/supervisor, dead local owner, and owner loss while public limits,
supervisor admission, init limits and selection are blocked. Each delayed case
asserts actual owner DOWN before infrastructure resumes, then no worker and zero
active coordinators. The selection case also observes coordinator DOWN. Distributed
coverage proves a remote owner works by default and is invalid in guarded mode.
New Node regression compares public and OperationOwner errors for malformed
Operation, cap reduced after authority startup, unavailable Directory/supervisor
and coordinator capacity. Existing lifecycle/down/retirement/quota/progress/ordered
batch regressions remain passing; no lifecycle/resource source was edited.

Validation: impacted named suite **86 passed (Runtime32 / Agent4 / Node50),
seed458366**, no exclusions, both distributed suites (six distributed cases).
After test aliases, public documentation and added remote-owner assertions,
only affected named tests reran: **47 passed (Runtime19 / Node28), seed750289**.
Final compile/warnings-as-errors, format, strict scoped Credo (73 files,575
mods/funs), existing-PLT Dialyzer (0 errors), production dependency trees for
Runtime/Agent/Node, scoped whitespace and empty index checks all exit0.
Exact commands/logs/hashes are in current verification.md.

Intermediate history: initial focused46 passed, seed521227, but generated constant
stage tests emitted compiler warnings. These were replaced by one runtime stage
loop before the86 run. Initial strict Credo had two test alias findings; fixed and
final scoped Credo passes. These are not final runner failures. Intentional fault
logs are expected. LSP absence/pending timeout remains inconclusive; no diagnostic
claim is made. No paid/provider/physical-host/release calls, commits, staging,
root/dependency/config/lock/spec/task-state edits or acceptance actions occurred.
Parent retains independent check, accepted handoff, spec and final bookkeeping.

---

# Historical independent lifecycle recheck — BLOCKED

Child4 must not start. Final exact-source independent named suite: **53 passed
(Agent4 + Node49), seed408204**, both real distributed tests included, no exclusions.
The previous three lifecycle blockers have affirmative regression evidence now;
one Runtime ownership-boundary blocker remains. This disposition supersedes every
older acceptance/readiness statement below.

## Findings and scoped repair

**Blocker — operation_owner.ex:15–36 bypasses the public Runtime contract.**
OperationOwner allocates the operation ID, constructs a DynamicSupervisor child
spec against Runtime.Coordinators, calls private OperationCoordinator.start_link,
and builds OperationRef. Runtime.submit instead validates Operation, checks the
current Directory operation_bytes ceiling, validates owner/sink PIDs, owns ID/spec
construction, normalizes max_children to capacity and other failures/exits to
unavailable. The adapter omits those entry checks and returns raw supervisor errors;
Server currently collapses them to dispatch_failed. Its owner/sink are local PIDs
by construction and Caller builds validated Operations against a captured cap, so
this is not a claim that malformed user input currently executes through Agent.
It is a concrete private-API dependency and duplicated Runtime responsibility,
contrary to parent R1/design ownership. Captured limits are not equivalent to the
public current-Directory check (e.g. independently composed Runtime replacement).

Independent exact-source probe: a valid Operation modified to budget_ms:0 returns
`{:error, :invalid_operation}` from Runtime.submit; the identical value through
OperationOwner produces operation_ready with an allocated coordinator/ref. No
invalid provider execution is claimed. `/tmp/child3-independent-probe.exs` and
`.log` record this and the pre-fix inventory reproduction. DynamicSupervisor still
applies coordinator capacity and Runtime still makes one attempt; no retry was
found. These facts do not justify bypassing the public entry contract.

**Concrete parent-owned Runtime seam proposal:** extend public Runtime.submit
with an optional `require_live_owner: true` mode, restricted to a local owner PID.
Keep all existing validation, live byte ceiling, ID/ref allocation, child spec and
error normalization in Runtime. Runtime's supervisor-invoked start/init path must
reject dead ownership before dispatch, including after a blocking Directory read;
monitor ownership before enqueueing dispatch. A queued admission whose controller
has died must create no execution and return a normalized unavailable error, with
no retry. The Agent worker then calls public submit with controller as owner/sink.
Keep the default generic API compatible. Add Runtime-owned delayed supervisor /
Directory admission, dead-owner, validation/capacity/error parity tests and rerun
scoped Agent lifecycle tests. Do not expose arbitrary start MFA/closures or weaken
validation. This proposal needs parent coordination; no upstream source was edited.

**Fixed — duplicate infrastructure inventory entries.** Resources previously
accepted repeated register for a live controller as separate slots, and repeated
track for one worker as separate monitors. Probe observed1→2 slots and102 inventory
entries for just2 PIDs after100 repeated tracks. Duplicate groups can also publish
retirement for the same controller at different times. Resources now ignores a PID
already inventoried before either registration or tracking, preserving its original
group/accounting. New regression failed before repair (3 slots instead of1), then
passed with exactly2 inventoried PIDs and group retirement after controller/linked
worker DOWN. Changed source only resources.ex and Node review_test.exs.

## Lifecycle evidence and limits

- Actual DOWN while Coordinators/Agents/Delegations/children remain suspended:
  independent final suite runs admission loss, authority teardown, nested child /
  grandchild cleanup, forced Resources restart and forced controller-loss tests.
  Resume happens after bounded DOWN assertions; delayed work does not execute.
- Genuine native progress and Runtime terminal plus suspended coordinator ack:
  live owners remain retained or are already dead; DOWN arrives before the next
  healthy input completes. Concurrent reversed Tool joins retain original IDs/order
  and complete context batches. Healthy context/model progression passes64 turns.
- Registration precedes worker creation/quota grant. Controller inventory is saved
  before grant; workers link both controller and Resources before business work;
  helpers link launcher/controller before child creation; child init links delegator.
  These links fence pre-track startup windows. Recorded helper/child DOWN keeps
  resource groups charged after controller death. Unknown late track kills its PID;
  dead stale registration cannot grant a worker. Duplicate messages are now inert.
- Manual quota probe admitted1024 operation controllers and1024 delegation
  controllers independently; the1025th of each kind was observed DOWN(:killed).
  A separate real suspended-admission probe observed controller DOWN after5003ms
  without stop/loss or supervisor resume, then zero late coordinators after resume.
  Fixed65s total deadline is source-reviewed, not independently waited out.
- Per-parent eight operation/delegation bounds are enforced by Server retained
  maps; per-kind1024 quotas by Resources and Task.Supervisor. Resource messages
  are internal trusted protocol, not a hostile-node boundary. Arbitrary forged
  unique-PID/kind floods are not supported or proven bounded. No new durable state
  exists: persistent_term contains only VM-local infrastructure PIDs, cleared at
  fenced startup, no prompts/results/IDs/business replay instructions.
- Role/readiness tests cover all seven configuration subsets, actual executor-only
  without Registry, combined local gateway, provider/gateway/Registry loss and
  same-host remote authority disconnect. Disconnect is observation, not proof of
  external cancellation. No fallback/retry/replay found. Absent Directory fallback,
  present-unavailable failure and owner-loss-before-ready regressions remain intact.

## Child and parent acceptance matrix

| Gate | Independent evidence | Disposition |
| --- | --- | --- |
| Child AC1; parent AC3/AC6 Agent placement portions | Real three-role model/workspace loop, wrong model/environment no fallback | Behavioral pass; public Runtime seam blocker prevents overall acceptance |
| Child AC2; parent AC7 | Invalid sibling zero dispatch; concurrent Agents/reversed Tools, ordered complete history | Pass |
| Child AC3; parent AC8 | Parallel children/zero parent pending, stop/loss/nested suspended cleanup, partition, peers | Pass within same-host/trusted-node scope |
| Child AC4; parent AC9 Agent portion | Snapshot first, credits/coalescing, sink DOWN, context/message caps | Pass |
| Child AC5; parent AC10 Agent/Node portion | Registry/provider/gateway faults, executor-only and combined local gateway | Pass; release boot remains child4 |
| Parent R1/R3/R7 ownership boundary | Runtime.submit parity probe and private coordinator dependency | **Blocked** on public guarded Runtime seam |
| Parent AC12 scoped checks | 53 tests, compile/format/Credo/Dialyzer/deps/whitespace | Pass; LSP inconclusive |
| Parent AC2 physical / AC5 live / AC10 release / AC11 deployment | Outside this review | Pending external/child4 work; no claims |

LSP: active Expert Agent/Node project processes were found through process
inspection. Available tools expose no standalone diagnostic-query/flush protocol;
read/edit feedback does not provide a complete current diagnostics sweep. Status
is **inconclusive**, not a clean result. No paid/live/release/physical-host or hard
RSS claims. Parent retains spec/task-state/commit bookkeeping. Existing dirty
upstream files, root/config/lock and SBOM were preserved; no index writes.

---

# Historical reports — superseded by CURRENT disposition above

# Independent coordinated-lifecycle recheck — checkpoint

Acceptance pending. Curated specs, prerequisite handoffs, parent contracts and historical blockers loaded. Reviewing Runtime public-submit parity and pre-track restart fencing in addition to actual DOWN and retirement behavior. Existing 52-test worker evidence is not independent acceptance. Child4 remains blocked.

---

# Lifecycle repair checkpoint — ready for independent recheck only

Child 4 remains blocked. This implementation pass repairs the three reviewed
lifecycle/accounting defects and records passing worker validation; it is not
independent acceptance. Historical blocked dispositions below describe earlier
source and remain useful reproduction evidence.

- Operation and delegation slots now have nonblocking lifecycle controllers.
  Blocking supervisor admission, Runtime acknowledgement and child control run
  in linked workers. Controllers can kill workers during admission/ack/cleanup,
  observe their DOWN and terminate without waiting for infrastructure to resume.
- Resources is an authority-supervised registry of controller groups, workers and
  announced helper/child PIDs. It links/monitors resources, has separate 1024-slot
  operation/delegation quotas, and retains a slot until all recorded group members
  are observed DOWN, including when the controller is forcibly killed. Server
  retains its eight per-parent slots until the registry reports group retirement.
- Admission registration waits at most five seconds; admission/child-startup has
  a separate fixed five-second controller deadline. Total controller lifetime has
  a fixed 65-second deadline, unaffected by incoming messages. Stop, Agent loss,
  and Resources loss interrupt sooner. Authority Agents/Delegations supervisor
  shutdown is capped at one second each, including suspension.
- Terminal business success marks an owner completed, preserving its accounting.
  Healthy replacement input can be accepted while retirement completes; model
  advancement and whole Tool batches wait asynchronously for actual retirement.
  Ordered ready/progress/terminal forwarding is preserved even if Runtime sends
  completion before supervisor admission returns.
- Delayed coordinator admission checks its local controller is alive before
  Runtime initialization; late helpers link their dead launcher/controller before
  child creation. Children link their delegator before input and retain the
  existing parent-group startup ticket. There is no retry/replacement admission.
- Stale dead registrations are discarded with retirement notification. Unknown
  tracking kills the late resource. Oversubscription links/monitors and forcibly
  kills rejected controllers rather than awaiting cooperation; rejection monitors
  are removed on DOWN and are included in teardown/restart fencing.
- The registry stores only bounded infrastructure PID inventories in VM-local
  persistent_term. Startup kills/monitors the old inventory and waits for DOWN
  before readiness. This survives authority replacement within a VM; it stores
  no business state, messages, replay instructions or durable recovery data.

Counts: each admitted operation slot owns one controller plus one blocking worker;
 each delegation slot owns one controller, one admission/relay worker and at most
one Task.Supervisor helper, plus its separately admitted child Agent. Registry
process count is one per authority. Controller/helper/child ownership forms one
shutdown chain; all owned child Agents retain the authority's 128-Agent ceiling.
Registration-stage controllers have no worker until quota grant and retain their
parent's bounded slots. A linked child is also monitored in its controller group;
remote loss is observational and does not establish external termination.

Validation: final named source run has **52 passing tests** (Agent4 + Node48),
seed318484, both actual distributed tests executed. Eight new regressions assert
actual DOWN while Coordinators, Delegations, Agents, child Agents or Resources
remain suspended; resume only follows the bounded assertions. Native provider
progress and real Runtime completion cover blocked acknowledgement and healthy
next input. Existing multi-step/concurrent Tool/distributed contracts pass.

## Durable root-cause retrospective

**Implicit Assumption:** moving a synchronous call into a monitored raw helper
was mistaken for bounded ownership; receive timeouts/monitors could not run during
admission or ack. Terminal success was mistaken for process retirement. Raw
helpers also outlived their authority, and killing a controller alone could precede
worker/helper DOWN. Controllers now remain responsive independently of blocking
workers; the authority registry owns full resource groups and publishes retirement
only after observed group exit. A VM-local old-generation fence prevents new
readiness from racing recorded resources from a killed registry.

**Test Coverage Gap:** earlier tests resumed infrastructure before cleanup
assertions and checked maps/messages instead of process DOWN. New tests keep it
suspended through actual DOWN, then check late admission cannot execute business
work. Three reconstructed pre-repair behavior comparisons fail the intended
assertions, not setup. Restart tests now wait for old-Agent DOWN before querying
supervisor readiness; provider-start observations now use a bounded explicit
operation-ready barrier before reading pending correlation. These observations
come from different senders and were never an ordering guarantee.

Residual limits: independent review required; VM-local inventory mutation cost at
maximum population is not benchmarked, and complete standalone LSP is unavailable.
The liveness/start check is a delayed-admission barrier, not an atomic distributed
termination guarantee. Partitions, external providers and billing remain best
effort. Same-host peers only; no physical/live/paid/release acceptance. All older
claims below are superseded by this checkpoint for the final source.

---

# Independent final child-3 recheck — BLOCKED

Child 4 must remain blocked. Independently loaded every check.jsonl reference,
child PRD/design/plan, current and historical reports/handoffs, parent PRD/design,
and complete tracked/untracked Agent/Node source, manifests and tests. Reviewed
whole current implementation rather than only git's tracked diff. Two scoped
repairs were made; three lifecycle/accounting blockers remain. **44 passing tests
are validation evidence, not acceptance of the remaining behaviors.**

## Remaining blockers

1. **Operation owners have no bounded admission lifecycle or authority ownership.**
   `operation_owner.ex:7` calls Runtime.submit before its receive loop. Runtime's
   DynamicSupervisor.start_child uses an infinity call. Server dispatch uses raw
   spawn_monitor; AuthoritySupervisor owns no owner supervisor/guard. Suspend
   Coordinators, accept input, close Agent and terminate the authority subtree:
   owner remains alive in gen.do_call after 5200 ms, only ending when Coordinators
   resumes. Source establishes that the wait is unbounded; the finite probe does
   not claim to have waited forever. The 65000-ms receive timeout starts only
   after submit returns and resets on each receive iteration. Parent DOWN/stop
   cannot be handled during admission. Repeated Agent creation/loss can accumulate
   owners beyond authority Agent bounds. A late-created coordinator eventually
   sees owner loss/cleanup after resumption, but that is not bounded lifecycle.
2. **Delegation launchers/helpers likewise lack bounded admission/cleanup ownership.**
   `delegation.ex:9` admits a helper through an infinity supervisor call before
   relay handles stop/DOWN. Raw launchers are outside the authority tree.
   Suspending Delegations, delegating then closing parent leaves launcher alive
   after 5200 ms; it exits only on supervisor resume. Local helper Agent.start
   also waits indefinitely on Agents admission before startup/expiry barriers.
   Its 60-second observation expiry begins only after creation/input/subscription.
   Per-parent helper slots survive partial admission while parent is alive, but
   do not bound orphan processes after parent loss. Relay has no independent
   expiry. A supervisor/Agent stall can prevent nested cleanup from completing.
3. **Terminal acceptance retires a live, blocked operation owner.**
   `server.ex` result handling calls retire_owner (line 519), demonitoring/removing
   the owner before DOWN. A genuine native provider emits progress and finishes;
   pause Agent until both real Runtime events queue, then suspend coordinator and
   resume Agent. Agent sends ack, then accepts the terminal; owner blocks in
   Runtime.ack while Server's owners map is empty. Probe output is `{0, true}`,
   status done, replacement input accepted. No forged Result was used in this
   decisive probe. The eight retained-owner claim is therefore not a bound on
   live helpers. Queued acknowledgements can extend cleanup through successive
   five-second calls. Completion of business work does not establish owner exit.

These require a coordinated Agent-side ownership/admission/retirement redesign,
including a bound that runs during blocking calls and late-created-work cleanup.
A simple monitor or receive timeout does not fix them. Recommendation: next scoped
implementation iteration within Agent/Node, then independent recheck; no upstream
contract change or expanded write scope is required. This check repaired the
isolated defects below and reports the larger lifecycle repair explicitly.

## Repairs in this recheck

- Owner DOWN before operation_ready previously removed accounting but left the
  Agent running forever without pending work. Server now detects active owner
  loss before removing the owner and fails/cleans the turn as infrastructure_lost.
  New regression failed before the fix (one selected test failed), then passed;
  asserts public error notification/snapshot rather than a state edit.
- Startup cap capture and public Caller.operation/2 previously defaulted to
  262144 on **any** Directory exit, including a configured Directory timeout.
  They now use the protocol fallback only when Directory is absent; a present
  unavailable Directory returns runtime_unavailable, creates no Agent identity
  and does not construct executable input. Regression suspends Directory through
  its actual five-second timeout, asserts both errors and empty Registry, then
  resumes and successfully starts that identity. Normal smaller-cap rejection
  and standalone-authority tests continue passing. Captured caps remain immutable.

## Five-remediation acceptance matrix

| Gate | Independent disposition | Evidence / remaining qualification |
| --- | --- | --- |
| Responsive callbacks + actual immutable byte cap + bounded owner lifecycle | **Partial / blocked** | Directory/coordinator suspension commands pass; cap timeout repaired; owners still unbounded and prematurely retired |
| Parent startup authorization before delayed input | Pass for reviewed delayed stop/loss cases | Startup ticket checks live group, stop/DOWN queue checked before input; delayed-creation tests assert no worker and child Registry empty |
| Partial launcher/helper admission retains slots through cleanup | **Partial / blocked** | Saturation and suspended helper admission tests retain live-parent slots until DOWN; orphan/admission lifecycle remains unbounded |
| Ref/turn/attempt/increasing sequence and terminal attempt binding | Pass | Duplicate/decreasing/wrong attempt/ref/post-stop progress ignored; terminal mismatch retains pending; complete progress wire bound |
| Complete 8192-byte peer wire and keyed retained envelopes | Pass | Maximum IDs, exact 8192/8193 request/reply, inbound/outbound keyed wrappers, rejection before send/retention |

## Child and parent acceptance matrix

| Scope | Disposition | Evidence and limits |
| --- | --- | --- |
| Child AC1 / parent R2,R4, AC3,6 | Supported in automation | Actual three-role model/workspace loop, missing capability/wrong workspace no fallback; upstream workspace negative contracts consumed unchanged |
| Child AC2 / parent R4,R5, AC7 | Supported | Several Agents, reversed Tool completion, original IDs/order, whole batch validated before dispatch, canonical normalized consistency and JSON-safe observation failure |
| Child AC3 / parent R5,R7, AC8 | **Blocked** | Joins/continuation/disconnect/stop/loss and independent peers pass; owner/launcher/helper lifetime/accounting above fails; full nested-delegation stall matrix not established |
| Child AC4 / parent R6,R7, AC9 | Supported for subscription seam | Same Agent sender initial snapshot, 16 credits/coalescing, subscriber loss isolated; Runtime retention belongs to accepted child 1 |
| Child AC5 / parent R2,R7, AC3,10 Agent/Node portion | **Partial / blocked** | Registry/provider/gateway faults, local gateway and executor-only peer pass; all seven role subsets configuration-tested; raw owners can outlive authority teardown |
| Parent R2,R4–R7 boundaries | Preserved with stated blockers | No Runtime→Harness/Agent dependency, no replay/retry, claims pass unchanged through Runtime's all-pool admission, allowlisted executor-local settings; custom ready? is trusted registration, not network health |
| Physical hosts, release/CLI, paid/live model, parent AC2/10/11 remainder | Outside this check / pending | No physical-host, release or live-service claim |

## Validation and diagnostics

Final-source named run: Agent 4 + Node 40 = **44 passed**, seed **55799**,
both distributed tests actually executed, no exclusions. Strict scoped Credo,
compile warnings-as-errors, format, existing-PLT Dialyzer, dependency and whitespace
checks pass. Exact commands, logs, earlier failures and probe reproduction are in
verification.md. Diagnostics edit runners report pending LSP; no standalone
changed-file diagnostic/query tool is exposed. **LSP is inconclusive**, not clean.

The old known_blocker stall test was replaced by positive responsiveness tests.
Those establish callback availability during finite suspension but resume the
infrastructure before checking cleanup, so they do not prove bounded admission,
owner orphan cleanup or terminal-owner accounting. Final tests retain no deliberate
passing assertion of unacceptable behavior. Manual probes below are defect evidence.

Only server.ex, integration/caller.ex, Node review_test.exs and the four authorized
child reports/plan were changed in this recheck. No index writes, task-state,
parent/spec/root/lock/upstream changes or commits. User SBOM and dirty work preserved.

---

# Historical reports — superseded by the independent recheck above

# Remediation disposition — ready for independent recheck

All five review blockers have scoped source repairs and affirmative behavioral
regressions. This is implementation evidence, **not independent acceptance**;
parent recheck remains the prerequisite for child 4. Final source: **42 passed**
(Agent 4, Node 38, including two actual distributed tests), seed 501169.
Compile, format, strict scoped Credo, existing-PLT Dialyzer and whitespace pass.

- Infrastructure: live callbacks use pure Operation construction with the local
  deployment cap captured before Server startup. One monitored owner per Operation
  performs submit/ack/cancel, owns Runtime work and forwards ordered events. At
  most eight owners are retained per Agent; stopped owners retain slots until
  DOWN. Late creation after stop/loss is cancelled without retry. Valid terminal
  acceptance retires the completed owner explicitly, avoiding a cleanup/next-input
  race found during validation. Directory/coordinator suspension tests assert
  command and snapshot responsiveness.
- Startup: monitored launchers perform Task.Supervisor admission outside callbacks.
  Created children await a ticket authorized by the live parent group before input;
  queued stop/DOWN is checked at the startup barrier. Delayed authority creation
  under parent stop and loss creates no model input.
- Partial admission: every launcher is monitored/accounted before admission starts.
  Failure ends the group and stops its siblings; helper/launcher cleanup accounting
  remains until DOWN. Deterministic max_children=1 saturation with delayed child
  creation rejects a replacement group until cleanup. Suspended helper supervisor
  likewise leaves parent commands responsive and cleanup slots retained.
- Progress: live ref/turn, one observed attempt and strictly increasing sequence
  bind retained progress; bounds include the complete progress wire envelope.
  Duplicate/stale/ref-mismatched progress and valid mismatched-attempt terminal
  Results leave pending state intact. Increasing progress works; post-stop progress
  cannot mutate retained state.
- Peers: complete request/reply wire envelopes and keyed retained observation
  wrappers are checked against 8192 bytes, including live identities and request
  TTL. Tests use maximum 128-byte IDs, 8100-byte rejection and exact 8192/8193-byte
  request/reply boundaries. Payload structural validation remains unchanged.

Residual boundaries: cancellation is best effort across partitions and external
providers; deployment limits are immutable for an authority lifetime (Node restart
coupling invalidates Agents). Standalone authority without Runtime retains the
existing protocol-cap default. No paid/live, release or physical-host acceptance;
no complete standalone LSP sweep. Historical evidence below is preserved explicitly
and does not describe the repaired source or current passing assertions.

---

## Historical independent review before remediation

# Independent child-3 review

Review scope: complete tracked/untracked Agent and Node source and tests, child
PRD/design/plan and actual upstream handoffs/specifications; parent R2/R4–R7,
AC3/AC6–AC10 and design sections 4/6. No unrelated/index changes authorized.

Acceptance is **blocked**, regardless of earlier passing totals.

## Findings and disposition

- Repaired: native model results were pattern matched without checking canonical
  normalized reply consistency. Custom providers could return inconsistent calls,
  content and assistant data; now the adapter-side Agent guard re-normalizes the
  assistant and requires exact normalized reply equality before dispatch/context.
- Repaired: child lifetime was attached only to the parent. Helper death after
  creation could orphan a live child until parent death. Children now monitor the
  helper, which itself monitors the parent; helper termination also invalidates
  a child created after an uncertain remote startup return. Cleanup remains best
  effort across partitions; there is no retry.
- Repaired: missing/non-list delegation options could raise inside the Agent;
  unknown spec fields and non-PID delegator options now reject.
- Repaired: executor model handler silently discarded extra payload/request keys;
  now exact payload/request fields and canonical native requests are required.
- Repaired: trusted allowlist registration did not verify native callback exports;
  registration now verifies loaded module and required model/Tool callbacks.
- **Blocker: callbacks still perform synchronous infrastructure calls.**
  `Caller.operation` calls Directory.limits; Server dispatch calls Runtime.submit
  (Directory and DynamicSupervisor); stop/fail/close/progress call Runtime.cancel
  or ack. Suspend Directory before Agent.input: accepted command and snapshots
  can stall until the five-second infrastructure timeout. Suspend a pending
  coordinator before stop: the Agent is blocked in cancel. Sequential cancellation
  of eight calls may multiply this delay. A facade timeout does not mean no turn
  or Operation was created. Required next action: bounded asynchronous submission
  and cancellation ownership, including late-created coordinator cleanup, inside
  the Agent seam. No upstream write is needed to establish this source finding.
- Repaired: malformed same-ref terminal Results now fail `Result.valid?/1` before
  pending state is removed. Runtime-valid Tool data may contain non-JSON map keys;
  observation encoding now fails explicitly instead of crashing the Agent.
  Delegation continuation encoding also handles failures safely. Stop/fail clear
  retained partial Tool results and order, preserving complete context pairs.
- **Blocker: progress identity/duplicate tracking remains incomplete.** Pending
  ref/operation/turn are checked, but no attempt or sequence watermark is stored.
  Source repro: capture a pending ref while a held model runs, send matching-ref
  progress with attempt A/sequence 2, then attempt B/sequence 1; both overwrite
  snapshot.progress. Required next action: bind observed attempt and monotonic
  sequence to the live pending operation and reject stale/duplicate generations.
  Terminal Results are structurally validated now; binding their attempt metadata
  to observed progress identity still needs completion.
- **Blocker: peer message limits count payload rather than full envelopes.**
  Concrete manual repro (`/tmp/child3-review-envelope.log`): an 8100-byte string
  passes the exact payload/Operation guards (external size 8106), while a complete
  request with valid 128-byte Agent IDs serializes to **8767 bytes**, above 8192.
  Required next action: validate complete request/reply/observation envelopes
  including live refs, turn IDs, TTL and wrappers before send/retention. Inbox
  count is bounded at 16; there is no claim that its aggregate must fit 8192.
- **Startup race remains insufficiently gated.** Helper ownership now prevents
  surviving helper-death orphans, but helper creation calls can return after a
  parent stop message has queued; `run/4` inputs/subscribes before checking that
  queued stop/parent DOWN. Required next action: explicit startup cancellation
  barriers before child input and regression with delayed authority creation.
  This is a scoped Agent repair, not an upstream defect or a new scope request.
- **Partial helper-start accounting gap:** `start_delegation/4` sends stop to
  helpers already created when a later Task.Supervisor admission fails, but
  returns only an error. `control/2` retains neither their monitors nor slots.
  A subsequent group can therefore start before those remote-start helpers finish
  cleanup; the global 1024-helper ceiling remains, but the per-parent eight-helper
  accounting claim is false on this path. Required next action: retain/monitor
  cleanup helpers after partial failure and reject another group until DOWN.
  This branch was source-reviewed; no deterministic saturation fault was run.

## Acceptance matrix

| Requirement | Implemented | Tested | Missing / qualification |
| --- | --- | --- | --- |
| Child AC1 / parent R2,R4 | Three role VMs, remote native loop and no fallback | Existing 2 actual peer tests | Fresh named-VM run passed; same host only |
| AC2 / R4,R5 | Whole-batch operations, parallel join/order | Existing concurrent and invalid sibling tests | Canonical mismatch rejected; no full turn-race matrix |
| AC3 / R5 | Delegation, peers, parent zero slots | Existing lifecycle/disconnect | Helper crash/worker cleanup passed; callback/startup blockers |
| AC4 / R6,R7 | Same-sender initial snapshot, 16 credits, coalescing | Existing slow/client-loss tests | Same-sender credits inspected; peer envelope/progress gaps remain |
| AC5 / R2,R7 | Role selection, Registry/provider/gateway coupling | Existing faults and local gateway | All 7 role subsets configuration-tested; faults/local gateway passed |
| R4 provider privacy | Public routes separate private profiles | Source inspected | Custom registration asserts trusted callback availability, not network health |
| R6 release / physical-host | Child-4 responsibility | Not performed | Physical B/C hosts, release closure, CLI remain external |

## Final validation and disposition

Final scoped named-VM suite: **34 passed** (Agent 4, Node 30 including both actual
three-peer distributed tests). Eight new review tests include one deliberate
**known-blocker reproduction**; its passing assertion confirms the stall exists,
not that responsiveness passes. Compile/format/strict scoped Credo/existing-PLT
Dialyzer and scoped whitespace checks passed after repairs. Exact commands and
intermediate failed lint attempts are recorded in verification.md.

**Do not accept child 3 or start dependent child 4 yet.** Address callback,
startup cancellation/partial-helper accounting, progress identity and full peer-envelope blockers in the
Agent seam, then rerun focused lifecycle/distributed checks and review the gate.
No upstream defect requiring expanded write scope was identified. No staging,
commit, archive, task-state, parent/spec/config/lock or upstream writes performed.
Provider custom allowlisting establishes trusted code registration and callback
availability only; default ready? does not perform arbitrary provider health or
remote service checks. Full LSP, paid/live calls, release/physical-host acceptance
remain unattested. Existing disk alarm and intentional fault crash logs were not
suppressed.
