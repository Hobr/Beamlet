# Parent acceptance — 2026-10-16

Parent reviewed the final independent reports and public admission/lifecycle source,
and accepts child3's scoped implementation/check gate and consumer handoff.
Evidence: independent86 tests seed631927, including six distributed cases; compile,
format, strict scoped Credo, existing-PLT Dialyzer, dependency and whitespace pass.
Executable specs synchronized. LSP inconclusive; physical/release/live-provider gates
remain separate. Commit/archive bookkeeping remains deferred to final delivery.
Child4 may activate under the existing user approval.

# Independent consumer handoff — accepted by parent

Independent acceptance gate found **no remaining child3 blocker**. Parent may
accept this consumer handoff, synchronize executable specs and activate child4.
This worker makes no task-state/acceptance/spec/commit changes. Earlier pending
and blocked sections below are historical and superseded by this recommendation.

Public admission contract: OperationOwner uses only
`Beamlet.Runtime.submit(operation, owner: controller, sink: controller,
require_live_owner: true)` and Runtime.ack/2. Runtime alone validates Operations,
current Directory operation_bytes and owner/sink, allocates IDs/specs/refs and
normalizes capacity/unavailable. Optional guarding is local-PID-only; default
remote ownership stays compatible. Guarded dead startup/ignored startup is
unavailable. Monitor-before-init-read plus post-limits/post-selection checks reject
observed owner death during delayed admission. No retry or atomic-death guarantee;
subsequent loss uses the existing monitor and honest cleanup/uncertainty semantics.
Runtime depends only on Actions, without Agent/Harness or callable injection.

For child4, use the existing public Agent start/input/snapshot/stop_turn/close,
subscribe/ack/unsubscribe, delegate and peer request/reply/take/inbox APIs. AgentRef
contains explicit authority, ID, incarnation and live PID; refs are ephemeral.
Input/delegate accept commands, while model/Tool/child work completes asynchronously.
The same Agent channel sends snapshot first and sequenced bounded/coalesced
snapshots afterward; acknowledge consumed sequence numbers. Slow/disconnected
subscribers do not own Agent lifetime. No replay promise exists. A stopped or old
turn cannot consume later correlated operation/child/peer results.

Authority owns Registry, Resources, bounded Delegations and Agents supervisors.
Controllers own linked blocking workers and fixed admission/total timers; Resources
retains per-kind quotas and group inventories until recorded DOWN. Terminal success
marks owners completed but keeps retirement accounting. Follow-on model/whole Tool
batch work waits asynchronously for retired capacity. Delegation children are
owned through helpers/links and startup authorization; nested cleanup and old
inventory restart fencing remain intact. Waiting parents reserve no executor slot;
peers have independent lifetimes. These are infrastructure lifecycle guarantees,
not provider rollback or partition-proof remote termination.

Node.start_link/1 composes declared interaction/authority/executor roles. Configuration
provides portable routes/catalogue separately from executor-local allowlisted
profiles/settings/providers/pools/limits. Authority requires no executor credentials
or workspace root. Executor-only starts no Registry/Agents; local combined-role
work still uses Runtime Gateway. Provider/gateway/Registry loss invalidates live
work/readiness without business replay. Child4 must wrap these APIs and composition,
keeping the single Agent loop and existing role ownership.

Independent final evidence: **86 passed**, Runtime32/Agent4/Node50, seed631927;
all six distributed cases explicitly executed. Compile warnings-as-errors, format,
strict scoped Credo73 files/575 mods-funs, existing-PLT Dialyzer0 errors, Runtime/
Agent/Node production dependencies and whitespace pass; index empty. CURRENT
verification.md records exact commands/logs and repair/lifecycle hashes; CURRENT
check-report.md records before/after findings and child AC1–AC5/parent mapping.
No product repair or new tests were needed in this recheck.

Parent can safely proceed with child3 acceptance/spec synchronization and child4
release/CLI implementation. Parent physical AC2/AC11, release AC10 and optional
live-provider evidence remain pending their own gates. LSP current changed-path
coverage is inconclusive (active Expert, no exposed complete query); Markdown
edit feedback is clean and does not establish Elixir diagnostics. Same-host peers,
local DOWN and bounded retained data do not establish physical-host deployment,
external cancellation, hostile filesystem isolation or hard RSS bounds. No live/
paid/provider/release calls, staging, commits or broader writes occurred.

---

# Historical consumer handoff — ready only for independent recheck

The authorized public Runtime admission repair is implemented and verified.
**Child3 is not accepted; child4 must not start until independent recheck and
parent acceptance.** Earlier blocked/ready statements below are historical.

OperationOwner uses public `Beamlet.Runtime.submit(operation, owner: controller,
sink: controller, require_live_owner: true)` and public ack. It no longer allocates
Runtime IDs/refs/specs or calls coordinator internals. Runtime owns validation,
current Directory byte caps, owner/sink checks, allocation and normalized errors.
The optional guard accepts only a local owner PID, rejects dead startup with
unavailable, monitors before init's blocking limits read, checks after that read,
and checks before/after Directory selection before dispatch. Queued supervisor
admission cannot execute after observed guarded-owner death. Ignored startup is
unavailable; max_children is capacity; no retry or callable injection. Generic
submit defaults remain compatible, including remote-owner submission.

Fixed lifecycle timers, worker/controller links, DOWN-based resource-group
retirement, duplicate PID accounting, quotas and progress/terminal identities
remain intact. Current reduced deployment caps and missing infrastructure errors
now agree between public Runtime and OperationOwner. No Agent/Harness dependency
was added to Runtime; no root/config/dependency/spec/task-state edits occurred.

Evidence: full impacted named run86 passed (Runtime32/Agent4/Node50), seed458366,
including both distributed suites; final affected named run47 passed
(Runtime19/Node28), seed750289, after test alias/docs/remote-owner assertions.
Compile/warnings-as-errors, format, strict scoped Credo, existing-PLT Dialyzer,
production dependency and whitespace gates pass; index empty. Current
verification.md records actual commands/logs/hashes and intermediate warnings /
Credo findings separately. check-report.md records before/after parity and actual
DOWN-before-resume at public limits, supervisor, init limits and selection stages,
then no late execution.

LSP remains inconclusive. Local liveness checks do not make owner death atomic
with dispatch; subsequent loss uses the installed monitor and existing cleanup.
Same-host distributed evidence does not attest physical-host placement or external
provider rollback. No paid/live-provider/physical/release calls were performed.
Parent owns independent acceptance, accepted contracts/spec sync and bookkeeping.

---

# Historical consumer handoff — child3 BLOCKED

Do not start child4. Independent lifecycle recheck repaired duplicate PID inventory
accounting and passed53 named tests (Agent4 + Node49, seed408204), including both
real distributed tests. The three previous lifecycle defects have affirmative
DOWN-before-resume / no-late-execution / blocked-ack evidence. One boundary blocker
remains: OperationOwner bypasses public Runtime.submit and constructs private
coordinator specs/IDs/refs without equivalent entry validation/error normalization.

Parent must coordinate a minimal Runtime-owned guarded public submit seam, then
return OperationOwner to public submission and recheck delayed admission plus
validation/capacity/error parity. Current check-report.md gives the concrete
proposal, evidence, AC1–AC5/parent matrix and exact limitations; verification.md
records final commands, seeds, hashes and before/after evidence. No upstream edits
were made or authorized by this review. No accepted consumer contract is published.

Current lifecycle semantics: Resources deduplicates register/track by inventoried
PID, retains groups until all recorded DOWN, fences previous VM-local inventory
before readiness; controllers own fixed timers and linked blocking workers.
Completed business Results retain owner accounting through actual retirement;
healthy next input and whole-batch model/Tool continuation wait asynchronously.
Public Agent/Node facade/config, same-channel subscription credits, captured-cap
construction, progress/peer correlation and provider privacy remain as source.
Historical public API reference below is provisional: its statement that all
submission uses public Runtime.submit is not true of the current private adapter;
its unavailable-Directory fallback wording is superseded by current Caller/Server
(absent permits standalone262144; present-unavailable fails). No retry/fallback.

LSP is inconclusive despite active Expert processes. Same-host peers do not satisfy
physical-host acceptance; paid/live/release tests not run. Parent owns final spec,
commit and task-state work. All earlier ready/blocked statements are history only.

---

# Historical handoffs — superseded by CURRENT disposition above

# Lifecycle repair handoff — ready only for independent recheck

Child4 remains blocked pending parent independent acceptance. Final impacted
named validation: **52 passed**, Agent4 + Node48, seed318484, both distributed
checks executed; static/format/compile/existing-PLT gates passed. See current
verification.md for exact commands, source hashes and failed comparison evidence.

Public Agent/Node APIs, native provider privacy, progress correlation, peer full
8192-byte envelopes, immutable captured operation cap and whole-batch contracts
are preserved. In particular, active owner loss before readiness still fails
explicitly, and a present unavailable Directory never widens the byte limit.

Authority now additionally supervises Resources. It owns/monitors controller
resource groups and separate1024 operation/delegation slot quotas; Agents retain
8 slots until the whole group exits. Each operation uses controller+blocking
worker; each delegation uses controller+worker+Task helper and a separately
bounded child Agent. Fixed admission/total deadlines run in the controller,
independently of blocking worker calls. Stop/loss kills workers/helpers and waits
for observed DOWN; suspended supervisor teardown uses finite shutdown bounds.
Linked delegators invalidate even suspended children, including nested trees.
Delayed coordinator starts reject dead local controllers before Runtime init;
late Task helpers link dead owners before business creation/input. No retry.

Business terminal success marks completed ownership but does not free its slot.
Ordered ready/progress/result forwarding remains same-controller. Replacement
healthy input can be accepted while cleanup finishes; next model step/Tool batch
waits asynchronously for actual retirement without capacity failures. Server
uses resource-group retirement rather than controller DOWN alone so forced
controller death cannot release a live worker/helper's slot.

Resources startup fences the old recorded generation via VM-local persistent_term
PID inventory, kill/monitor/DOWN before new readiness. This is ephemeral
infrastructure bookkeeping, never business persistence/recovery/replay. Dead
stale registrations do not admit workers; unknown late tracking kills its PID;
rejected registrations are forcibly killed, monitored and fenced until exit.
The registry's bounded inventory update cost at maximum population is unbenchmarked.

Reviewer focus: delayed dead-owner admission, resource registration/track ordering,
forced registry restart, rejected registration cleanup, nested links and ordered
terminal retirement. The local alive/start check does not promise atomic remote
termination. Remote disconnect observations and local BEAM DOWN do not establish
external provider rollback/billing cessation. No live/paid/physical/release or full
standalone LSP claim. Rootcause categories and prevention tests are durable in
check-report.md. Parent owns accepted spec sync/final commit/task bookkeeping.

---

# Historical handoffs (superseded for current source)

# Current consumer handoff — child 3 BLOCKED

Do not begin child 4. Independent recheck repaired two isolated defects and ran
44 impacted tests including both distributed tests, but three lifecycle/accounting
blockers remain. See check-report.md and verification.md for exact evidence.
There is no accepted consumer handoff yet.

Current contract corrections for any further Agent-side repair:

- Server captures immutable actual local operation_bytes before startup and uses
  pure Caller.operation/3 inside callbacks. Absent Directory permits the existing
  standalone262144 fallback; present Directory failure returns runtime_unavailable
  from startup/public Caller.operation/2 and must not silently widen limits.
- OperationOwner performs Runtime submit/ack/cancel outside Agent callbacks. Ref
  ready and forwarded progress/results share the owner sender, preserving order.
  Active owner loss now fails the Agent even before readiness. **Do not claim a
  bound of eight live owners:** terminal acceptance removes accounting before
  owner exit, and suspended supervisor admission can orphan raw owners indefinitely
  after Agent/authority loss. Receive timeouts do not bound blocked calls.
- Parent startup tickets reject delayed child input after observed stop/loss; live
  parent partial admission retains launcher slots until DOWN. **Do not claim
  bounded launcher/helper cleanup:** raw launcher/helper admission can wait forever
  before stop/DOWN/expiry processing. Authority tree does not own raw launchers.
- Progress requires matching live ref/turn, one observed attempt and increasing
  sequence; terminal metadata must match an observed attempt. Invalid events leave
  pending work intact; full progress wire is bounded.
- Peer limits are **8192 bytes for the complete request/reply wire and each keyed
  retained envelope**, including identities/turn/TTL/wrappers. Usable payload is
  smaller than8192 and depends on overhead; over-limit executable messages reject.
- Public Agent APIs, same-sender subscription snapshot/credit protocol and Node
  trusted role/config seam are otherwise as described in historical API reference
  below. Pending operation ownership changed from direct Agent submission to
  helpers; old coordinator-only pending-state descriptions are superseded.
- Executor-only starts no authority; all operations use Runtime gateway, all pool
  claims remain intact and no retry/replay is introduced. Provider settings stay
  executor-local. Custom module readiness is trusted callback registration, not
  network health. No release/physical/live-provider/full LSP acceptance is claimed.

Historical sections below are reference/history only, including old blocked and
ready-for-recheck statements. They cannot authorize dependent implementation.

---

# Historical handoffs — superseded by current blocked disposition above

# Current remediation handoff

Five independent-review blockers repaired; **ready for independent recheck**.
42 impacted tests pass, including both actual distributed tests; see verification.md
for exact final-source commands and intermediate failures. Do not treat worker
validation as parent acceptance or begin child 4 before independent recheck.

Public Agent/Node APIs remain those documented below. Implementation corrections:

- Server startup captures immutable local Runtime operation_bytes outside live
  callbacks; standalone authority without Runtime uses the existing 262144 default.
  All Server executable validation uses pure Caller.operation/3 with that cap.
  Public Caller.operation/2 still consults the actual Directory deployment cap.
  No executable input is truncated. Deploy/restart matching Node role trees when
  changing limits; limits are not a hot-reconfiguration API.
- Each Operation has one monitored owner (maximum eight retained per Agent).
  Runtime owner and sink are that helper; ordered events forward to Agent. Stop
  freezes correlation immediately and sends cancellation asynchronously. Owners
  monitor Agent loss and clean up late-created work. Stopped owners retain slots
  until DOWN; completed terminal owners retire explicitly. No retry/replay.
- Delegation uses at most eight monitored launchers plus their supervised helpers.
  Admission calls happen in launchers, never Server callbacks. Launchers remain
  counted through helper cleanup/DOWN, including partial admission failure.
  Created children await parent-group authorization before input, with stop/loss
  checks at the startup barrier. Global Task.Supervisor helper ceiling stays 1024.
- Pending progress binds ref, turn, attempt and increasing sequence. Valid terminal
  Result metadata must match any observed attempt. Invalid events retain pending
  state, never advance or overwrite progress. Full progress wire is bounded.
- Peer 8192-byte limits apply to complete request/reply wire envelopes and keyed
  retained wrappers, including identities and TTL. Consequently usable payload
  size depends on envelope overhead; oversize requests/replies reject explicitly.

Source edits: integration/caller.ex, server.ex, delegation.ex, new operation_owner.ex,
Node review_test.exs. Authorized child reports/plan also updated. Upstream dirty
work and user SBOM commit preserved. No task state/index/commit changes by worker.
No physical/live provider claim, full LSP sweep, reliable remote cancellation,
new dependency or expanded contract. Historical handoff below records prior state;
its blocker notices and payload-only limit description are superseded above.

---

## Historical handoff before remediation

# Child 3 Agent/Node handoff

Independent review completed with scoped repairs; **child-3 acceptance is blocked**.
See check-report.md before starting dependent child 4. See verification.md for actual counts, repaired failures and external gates. No task-state, stage, commit, archive, root configuration, lock, upstream app or spec edits were made by this worker.

## Agent authority and lifecycle

Opt in to `Beamlet.Agent.AuthoritySupervisor.start_link([])` / its child spec. The authority island couples unique `Beamlet.Agent.Registry`, a bounded delegation Task.Supervisor and temporary Agent DynamicSupervisor with `:one_for_all`. Registry/infrastructure loss destroys live identities and context; it never reconstructs work.

`Beamlet.Agent.start(authority_node_atom, options) -> {:ok, ref} | {:error, reason}` explicitly addresses an authority; remote creation uses bounded erpc and never falls back. Options are `id` (UTF-8 binary 1..128 bytes), `model` portable route, optional `catalogue` (validated data map), `tools` (Tool name→portable route) and internal `delegator` PID. Routes have `id`, `capability`, optional `environment`, `claims`, `allowed_nodes`. Roots/settings/credentials/module names are not accepted route fields.

`%Beamlet.Agent.Ref{authority: node, id: binary, incarnation: reference, pid: pid}` is live and ephemeral. Commands address the PID and validate its incarnation. A reused local ID never validates an old ref.

Public commands:

- `input(ref, text) -> {:ok, turn_reference} | {:error, reason}`. One active turn; incompatible input rejects `:busy`. Input is at most 65,536 UTF-8 bytes and must fit both context and Runtime executable limits before acceptance.
- `snapshot(ref) -> {:ok, snapshot} | {:error, :unavailable | :stale_ref}`.
- `stop_turn(ref) -> :ok`: first freezes advancement/clears pending correlation, then requests cancellation/owned-child cleanup. Late results cannot resume it.
- `close(ref) -> :ok`: terminates the temporary Agent after requesting owned-work cleanup.
- `subscribe(ref, sink \\ self())`, `unsubscribe(ref, sink \\ self())` return `:ok` or explicit errors.
- `ack(ref, sequence)` acknowledges for the calling subscriber PID. A different process must not acknowledge another sink's credit.

Snapshot fields: `ref`, `turn`, `terminal_turn`, `status` (`:idle | :running | :waiting | :done | :error | :stopped`), `steps`, `final`, `progress`. No context, local roots, native settings or credentials are included. Safe model failure snapshots preserve Runtime status/reason/operation ID and the completed `terminal_turn` even after active `turn` is cleared; loss without terminal notification reports `:infrastructure_lost`. Delegation accepts error/stop snapshots only for its exact child turn. Progress includes operation ID, Tool key, attempt identity and bounded native value.

All subscriber notifications come directly from the same Agent process/channel:

```elixir
{:beamlet_agent, agent_ref, sequence_integer, {:snapshot, snapshot}}
```

The initial snapshot is sent before subscribe replies and precedes later events from that Agent. At most 32 sinks and 16 unacknowledged notifications per sink are retained. State/progress coalesce while credit is exhausted; an ack permits a current snapshot. The terminal state remains queryable even if a slow client has no credits. Subscriber DOWN removes only the subscription. No subscriber forwarders or durable event history exist.

## Model/Tool integration

`Beamlet.Agent.Integration.Caller.operation(route, request) -> {:ok, Operation} | {:error, reason}` produces `kind: "agent.native"`, payload `%{"profile" => route.id, "request" => request}`, opaque capabilities/environment, allowed nodes and claims. It checks the actual local Runtime operation-byte deployment limit, defaulting to the protocol 262,144-byte ceiling if Runtime is unavailable. Native Harness's 1 MiB request allowance does not override this ceiling. Executable input is rejected, never truncated.

`Beamlet.Agent.Integration.Handler.run(payload, runtime_context)` resolves a configured profile ID in executor-local handler settings. It invokes ordinary native `complete/3` or `invoke/3` with `%Beamlet.Harness.Context{progress: ..., cancelled?: ...}`. Runtime owns scheduling/admission/uncertainty; Harness remains independent of Runtime/Agent.

The Agent submits model and Tool operations through Runtime even when execution is local. No callback awaits provider IO or model/Tool/child completion. Pending operations store ref, turn, Tool key and coordinator monitor. Completion requires matching live ref, operation ID and turn. Coordinator DOWN may invalidate a submission without a terminal event and is handled explicitly.

Before Tool dispatch, validate the entire wire batch, every Tool route, context message slots and all complete Operation envelopes. Preserve the assistant wire message and original call order. Parallel Tool observations join by operation/ref/turn and Tool ID, then append the assistant plus all observations atomically in original order. No incomplete assistant/Tool pair is retained in conversation after stop/failure, and no model step sees a partial join. Tool failures include Runtime status/reason as JSON Tool content. Native failure/uncertainty is never retried.

## Delegation

`delegate(parent_ref, child_specs, continue: false) -> {:ok, group_turn_reference} | {:error, reason}` starts an idle/terminal parent's group; incompatible busy states reject. Each spec is `%{authority: node_atom, options: agent_options, input: text}`. At most 8 children. Children require authority readiness and use normal Runtime gateways. Parent `:waiting` holds no Operations/execution slots.

One bounded monitored helper per child performs creation and watches its snapshot channel outside Agent callbacks. Helpers are supervised globally (1024 maximum per authority), while each parent admits at most 8 and waits for prior helper cleanup before another group. Child Agents monitor helper ownership; each helper monitors its parent. Helper death
therefore also requests child cleanup, including after uncertain remote creation. Parent stop or loss requests cleanup, including nested owned work; child disconnect/loss becomes a correlated error with no recreation/retry. Helpers have a fixed 60-second observation expiry after startup, delivered by a timer message; incoming snapshots cannot reset this deadline. Remote startup/control calls are separately bounded. Successful or failed owned children are stopped/closed after observation.

Groups join by group reference and original child index; final observations are ordered `%{status: :ok | :error, value: child_final_or_safe_reason}` maps. Optional `continue: true` appends their bounded JSON observation as a user message before another configured model step. Stale group events are ignored. A cleanup request/partition does not prove external resources or billing ceased.

## Peers

- `peer_request(source_ref, target_ref, payload, ttl_ms \\ 30_000) -> {:ok, request_reference} | {:error, reason}`.
- `inbox(ref) -> {:ok, bounded_map}` exposes pending requests and received observations.
- `peer_reply(receiver_ref, request_reference, payload) -> :ok | {:error, reason}`.
- `peer_take(ref, request_reference) -> {:ok, entry_or_nil}` removes an entry explicitly.

Peer payloads are bounded plain data, maximum 8192 serialized bytes. A total of 16 pending outgoing/inbox entries per Agent is admitted; overflow rejects. TTL is 1..60,000 ms. Internal request correlation carries source/target live refs, source turn, request reference and receiver turn. Replies must match source/target incarnation and current source turn; replies from a receiver's later turn reject. Peer traffic never implicitly executes a turn and never couples peer lifetimes. Loss/expiry produces bounded `:peer_lost` / `:peer_expired` observations; inbound requests expire, with no delivery/replay promise.

## Node composition and child-4 boot seam

`Beamlet.Node.start_link(options)` / child spec starts a single role composition per VM. `Beamlet.Node.configuration(options)` validates trusted roles and returns child specs or `{:error, :invalid_node_configuration}`. Roles are any unique nonempty subset of `[:interaction, :authority, :executor]`. Every role starts shared Runtime discovery and public Routes. Authority adds the identity island. Executor adds provider ownership then execution-enabled Runtime. Executor-only starts no authority Registry/Agents. Node supervision couples these children with `:one_for_all`; provider/accounting loss kills affected workers before fresh readiness and never replays business work.

Default umbrella `Beamlet.Node.Application` starts only its empty application supervisor, requiring no roles/secrets. To boot selected roles later, configure trusted `Application` env `:beamlet_node, :boot` with the options below; product selectors/release packaging are child 4.

```elixir
[
  roles: [:authority, :executor],
  routes: %{
    "public-model" => %{id: "public-model", capability: "model-v1", claims: %{"native" => 1}},
    "public-tree" => %{id: "public-tree", capability: "read-v1", environment: "tree-v1", claims: %{"native" => 1}}
  },
  catalogue: catalogue_data,
  profiles: %{
    "public-model" => %{type: :model, module: Beamlet.Harness.Models.OpenAICompatible,
      settings: %{base_url: "https://configured.example/v1", model: "configured-model", key_env: "LOCAL_MODEL_KEY"}, capability: "model-v1"},
    "public-tree" => %{type: :tool, module: Beamlet.Harness.Tools.WorkspaceRead,
      settings: %{root: executor_local_trusted_root}, capability: "read-v1", environment: "tree-v1"}
  },
  pools: %{"native" => 8},
  providers: [],
  limits: []
]
```

`Beamlet.Node.profile(public_id)` returns `{:ok, portable_route}` or `:error`; `catalogue/0` returns `{:ok, data}`. These are local service calls (usable via console/RPC); unavailable Routes can exit like ordinary OTP calls. Authority can configure only routes/catalogue and roles, with no native key/root/client. Child 4 resolves routes then passes them as Agent model/Tool options; it must not implement a second loop.

Profiles are executor-local. Default explicit native allowlist includes Models.OpenAICompatible/Deterministic and Tools.WorkspaceRead/Deterministic. Trusted boot `allowlist: %{model: [modules], tool: [modules]}` can deliberately install configured native providers; test-only modules use this seam. Operation payloads never choose modules. At most 32 profiles, 64 public routes, and 31 externally monitored provider PIDs (plus owned Provider) are accepted. Runtime enforces local handler/settings/report bounds. All provider roots and HTTP key/settings validation happens before readiness; the owned Provider starts before Gateway advertisement, and Runtime also monitors supplied provider PIDs. Req's application-managed client is available through declared Harness dependencies. Native adapters still revalidate at invocation. No model HTTP call is used to establish readiness.

## Limits and review boundaries

Authority Agents 128; context 128 messages / 1 MiB JSON; model steps 16/turn; Tool batch 8; delegation 8; peer exchanges/inbox 16; subscribers 32 with 16 credits; incoming text 65,536 bytes; peer message 8192 serialized bytes. Native/Runtime operation/result/progress limits remain as verified upstream. Snapshot state is bounded below 1 MiB (oversize final becomes explicit `:snapshot_limit`); pending batches contain at most 8 bounded Results and may transiently retain more bytes than context. Bounds do not imply a hard RSS cap.

Readiness and references are ephemeral. A provider loss conservatively invalidates work; Node subtree restart may also invalidate authority Agents on a combined node. This is deliberate conservative coupling, not business recovery. No retry/replay, reliable-delivery guarantee, durable inbox, shell/write Tool, LLM-selected delegation Tool, automatic clustering or OS filesystem sandbox was introduced. Same-host peers are automation only. Physical-host release acceptance, live paid provider compatibility, full standalone LSP coverage remain external/pending. Independent trellis-check
found blockers in synchronous infrastructure calls inside Agent callbacks, startup
stop barriers, progress attempt/sequence validation and complete peer envelopes.
These must be repaired before child 4 starts.


## Review corrections for child 4

Public APIs/config above remain the intended consumption seam, but are not yet
an accepted prerequisite gate. Native model replies now require exact canonical
normalized consistency. Model Handler rejects unknown executable payload/request
fields; trusted provider allowlisting verifies loaded native callbacks. Custom
providers' default readiness is a trusted registration assertion, not generic
network/client health checking. Operators must supply explicit monitored provider
PIDs where readiness depends on a live service; no HTTP readiness probe is claimed.
Malformed terminal Results are ignored; non-JSON Tool output fails safely and
clears partial retained batch state. Helpers own child lifetime, while queued
parent stop during creation still needs a startup barrier. Full callback/progress/
peer-message corrections and their regressions are required next. Release, CLI,
physical hosts and live-provider validation remain child 4/parent responsibilities.
