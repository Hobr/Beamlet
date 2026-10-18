# Operation Runtime

**Integration status:** format3 foundation/Actions persistence supports generic durable
Runtime independently of Agent. Agent owns its associations and composes atomic
preparation; trace export remains format2. See [State and Persistence](./database-guidelines.md)
for installation/ownership and [Agent durability](./agent-durable.md) for orchestration.

## Scenario: submit generic work to an eligible connected node

### 1. Scope / Trigger

Use this contract when adding Runtime consumers, local handlers or Node composition.
Actions owns data validation and Handler with no storage dependency. Runtime
directly uses Actions, Actions Storage, foundation Storage and Ecto/OTP.
No Agent, Harness or Phoenix dependency belongs in either application. Sources are
under `apps/beamlet_actions/lib/beamlet/` and `apps/beamlet_runtime/lib/beamlet/`;
behavioral tests mirror them.

### 2. Signatures

```elixir
{:ok, operation} = Beamlet.Actions.Operation.new(kind: "example.echo", payload: %{})
{:ok, ref} = Beamlet.Runtime.submit(operation, owner: self(), sink: self())
{:ok, snapshot} = Beamlet.Runtime.status(ref)
:ok = Beamlet.Runtime.ack(ref, sequence)
:ok = Beamlet.Runtime.cancel(ref) # request only, while nonterminal
```

Optional `submit(operation, owner: local_pid, require_live_owner: true)` rejects
remote owner PIDs as invalid_operation and dead guarded startup as unavailable.
Default mode retains remote-owner compatibility. Runtime alone owns validation,
current Directory byte caps, ID/spec/ref allocation and error normalization (including
ignored startup). The coordinator monitors before its init limits read and checks
local liveness after limits and before/after selection. Observed death during blocked
admission cannot create late execution; subsequent races use existing cleanup.
Consumers must not construct private coordinator specs to duplicate this guard.

Handlers implement `Beamlet.Actions.Handler.run(payload, context)` returning
`{:ok, value}` or `{:error, safe_reason}`. Context contains executor-local
`settings`, unchanged invocation `credentials` (default `%{}`), `remaining_ms`,
`progress` and `cancelled?` callbacks. Use callbacks
for neutral progress/cancellation; provider authors need not know coordinator IDs.

### 3. Contracts

Operation fields: `kind` (1..128 UTF-8 bytes), `version: 1`, `payload: %{}`,
`metadata: %{}`, `credentials: %{}`, `capabilities: []`, `environment: nil`, `allowed_nodes: nil`,
`claims: %{}`, `budget_ms: 60_000` (1..3_600_000). Capabilities/claims are bounded
at 32 entries; allowed nodes are at most 64 existing node atoms. Never atomize
untrusted text. Nested values are bounded data, not PIDs, references, functions,
ports, tuples or arbitrary structs. Maximum nesting depth is 24. Conventional
secret/root keys are rejected recursively; producers must still redact secrets
and roots embedded in ordinary text. Executable arguments are never truncated.

Only dedicated credentials bypass ordinary secret-label rejection. They must be a
plain string-key JSON object: <=32 top-level entries, top-level names1..128 UTF-8
bytes, depth<=24, complete encoded JSON<=16384 bytes. Nested maps/proper lists and
JSON scalars are accepted; structs, arbitrary atoms, tuples and executable/live
values are not. Reject root/workspace_root recursively, case-insensitively, including
maps inside lists. `Actions.credentials?/1` uses OTP JSON with no Harness dependency.
Validate the remaining Operation with unchanged ordinary policy and count the full
credential-inclusive struct with `:erlang.external_size/1` under262144 and current
deployment caps at public submit and Gateway. JSON credential and Erlang envelope
sizes are separate limits. Worker forwards credentials separately from local
settings; Runtime never interprets providers or merges credentials into settings.
Generated status/progress/Results/reports/errors omit credentials. Transient copies
may remain until ordinary cleanup; there is no secure-erasure guarantee.

OperationRef contains opaque ID and live coordinator PID. Execution is distinct:
operation ID, preallocated attempt ID, endpoint/incarnation, optional admitted
handle and state. No target means no Execution. Result contains operation ID,
optional execution ID, status, safe reason/value, source and bounded metadata.
Execution-origin Results require an execution ID. Exactly one matching terminal
Result is accepted in memory; no attempt is retried, replaced or replayed.

Gateway records the first stop trigger it processes for each admitted worker:
execution deadline or cancellation. Later triggers do not replace that source.
A cancellation-marked shutdown, or a killed DOWN following Gateway kill escalation,
proves local worker retirement and uses that source with reason `:worker_stopped`.
Other crashes remain `:error/:worker_lost`. Coordinator preserves valid Gateway
classification even with cancellation pending; a handler returning an error named
worker_stopped alone is not observed-stop evidence. Valid success racing before
terminal acceptance keeps existing semantics; any accepted terminal is immutable.
There is no global trigger ordering across VMs. Local worker exit does not prove
external provider cancellation, rollback, absence of effects or stopped billing.
Matching trusted Gateway builds are required for corrected provenance.

Events arrive at the installed sink:

```elixir
{:beamlet_operation, ref, {:progress, attempt_id, sequence, value}}
{:beamlet_operation, ref, {:result, result}}
```

Acknowledge consumed progress with `ack/2`. Terminal delivery does not require
credits. Producer/gateway/sink drops appear in terminal metadata/status. A linked,
monitored task-owned marshaler forwards auxiliary progress while run/2 executes.
Handlers own arbitrary children and external resources they create.

Start Runtime once per VM with `{Beamlet.Runtime, options}`. Default
`execution: false` starts only SharedSupervisor: dedicated pg scope, Directory,
temporary coordinator supervisor and NodeEndpoint. Explicit `execution: true`
adds ExecutionSupervisor, coupling Workers Task.Supervisor and ExecutorGateway
with one_for_all. Node may compose the execution subtree separately using its
child spec; stop execution before shared infrastructure. Neither library has an
application callback that automatically starts roles.

Executor options include local `handlers: %{"kind" => {Module, settings}}`,
opaque `capabilities`, `environments`, `pools: %{"requests" => 2}` and monitored
`providers: [pid]`. Reports omit settings/providers. Registration validates module
run/2, bounded labels/settings/counts and report overhead. Directory monitors pg
membership/endpoints, queries joins immediately, refreshes nonce-correlated
reports and expires them using local receive time. Shared-only endpoints remain
discoverable with execution readiness false.

Placement filters readiness, protocol/kind, freshness, capability/environment,
allowed nodes and all claims; lower utilization then node/incarnation breaks ties.
Gateway revalidates and atomically charges local pools. Report leases are checked
only against the issuing gateway's clock; lease age conservatively reduces the
remaining budget. Stale reports can shorten short operations. Discovery reserves
no capacity. Tombstones/lease watermarks reject old dispatches. Ephemeral operation
still has no durable execution deduplication or public retry permission.

## Durable execution mode (opt-in)

Actions persistence exposes `OperationRecords.prepare(repo, %{operation: op, attempt: attempt})`
and the same-Repo participant `prepare_in_transaction/2`. Operation attributes are
exactly `id`, `description`, optional `dispatch_scope_id`/`dispatch_epoch`; attempt
attributes are `attempt_id`, `executor_id`, `executor_boot_id`, `budget`. Agent-shaped
owner/role/step/sources attributes refuse as invalid_data. Description allows only
string keys `kind`, `protocol_version`, `payload`, `refs`, `budget`, `claims`, `safety`;
Runtime's description uses protocol_version1 and excludes invocation credentials.
Prepare returns string-key `operation_id`, `description_digest`, `attempt_id`,
`attempt_version: 0`, `lock_version: 0`, `dispatch_state: "prepared"` and scope/epoch.
Exact immutable replay succeeds; changed description/attempt identity conflicts.
`record_evidence/2` requires atom keys `id`, `operation_id`, `attempt_id`,
`executor_id`, `evidence_id`, `content`, with optional `resolution`.
`accept_result/2` requires `operation_id`, `expected_version`, `result`, with
optional `evidence_id`, `artifact_ids`; repeated identical acceptance preserves the
original Result and conflicting acceptance refuses. Both return safe tuples through
the owning transaction facade. Actions owns these APIs and journal/terminal artifacts.

`Runtime.submit/2` accepts `persistence: %Beamlet.Runtime.Persistence{}` carrying the
authority_repo, journal_repo, authority_id, executor_id, executor_boot_id and optional
paired dispatch_scope_id/dispatch_epoch. Scope is an opaque UUID/epoch, never an
Agent owner or callback. Both nil is valid; a partial binding is invalid. Without it nothing changes: no Repo is started, no environment is
read and no persisted identity is required. With it:

- the immutable Operation and one `prepared` attempt commit before any coordinator
exists; a failed write returns `{:error, :invalid_operation | :unavailable}` and
dispatches nothing. A durable submit is refused up front when no coordinator
supervisor is running, because an orphan `prepared` attempt would have no id the
caller could reconcile with;
- the coordinator CASes `prepared -> send_claimed` and only then sends the 9-element
admit form carrying authority/operation/attempt/executor ids plus the description
digest; it never sends inside a transaction;
- the gateway revalidates that identity, recomputes the description digest from the
operation it will actually run, rejects duplicate admissions from the journal, and
commits `start_intent` before the worker task exists. A failed journal write rejects
the attempt with capacity never charged and no handler call;
- the terminal value and receipt commit before any completion message. If that write
fails after the handler ran, the gateway reports `:unrecorded`, so the coordinator
accepts `:uncertain` rather than a definite error. A pre-dispatch rejection stays
`:error`;
- the authority persists the receipt evidence and CASes `accepted_result` from NULL
before the sink is notified. A failed accept notifies no sink and is visible as
`durable.accepted: false` with `accept_error` in `status/1`; the Result itself is not
surfaced by status until it is accepted;
- at gateway boot every remaining `start_intent` of this authority/executor becomes
`unknown_after_restart`: no worker is rebuilt, no capacity is restored, and the state
can never become terminal. A boot that cannot write the marker reports not-ready and
keeps rejecting durable admissions;
- `Runtime.evidence/3` reads the authority Operation/attempt and the journal row by
stable ids only. `journal: :not_found` means no row; `journal: :unavailable` means the
journal could not be read; neither proves the handler never ran.

Enabling persistence on an executor therefore requires every submitter to pass a
`%Persistence{}`; a durable gateway rejects the ephemeral admit form instead of
silently degrading. The struct is authoritative input, so an invalid one raises
rather than returning an error tuple. Already committed requests pass a string-key
`prepared:` map with `operation_id`, `attempt_id`, `description_digest`,
`lock_version` (Operation), `attempt_version`, `dispatch_scope_id`, `dispatch_epoch`.
Public submit fetches Actions facts and compares actual `Persistence.description/1`,
both IDs/versions/digest, executor/boot, prepared state, absent acceptance and scope
binding against Persistence and prepared identity before starting a coordinator.
It never creates a replacement request for a supplied identity.

Coordinator calls Actions `OperationRecords.claim_dispatch(repo, attrs)` with
`operation_id`, `attempt_id`, `expected_version` (attempt), and `expected_operation`
containing exact atom keys `description_digest`, `lock_version`, `dispatch_scope_id`,
`dispatch_epoch`. The latter binding is checked again under the claim lock; public
validation alone cannot fence continuation between check and dispatch.
PG claim locks scope FOR SHARE before Operation FOR UPDATE and holds both through
commit; SQLite immediate writes serialize. Rotation/reauthorization lock scope
before Operation; Agent composition adds Agent first. Acceptance locks/CASes only
Operation, never Agent/scope. Restore-before-claim rejects stale epoch; claim-first
retains already-claimed semantics. Rotation cannot retract network sends/effects.

Actions `DispatchScopes.create(repo, %{id: uuid})` starts epoch0;
`rotate(repo, %{id: uuid, expected_epoch: epoch})` advances it, with transaction
participants `create_in_transaction/2`, `rotate_in_transaction/2` and
`reauthorize_in_transaction/2`. Reauthorization requires `scope_id`, `from_epoch`,
`to_epoch`, `operation_id`, `attempt_id`, `description_digest`, `expected_version`
and `attempt_version`; only unaccepted prepared attempts at the old binding qualify.
The returned Operation lock_version/epoch must replace stale prepared bindings.
There is no business retry or exactly-once promise.

Acceptance uses Operation CAS independently of Agent position, with explicit Agent
consumption left to orchestration. Failed/duplicate claims cannot accept Results;
late receipts preserve evidence without replacement or a second sink completion.
See [Runtime integration API](../../../apps/beamlet_runtime/README.md).

Default configurable limits (`limits: [...]`): coordinators including retained
256, retention 30_000 ms, refresh 1_000 ms, expiry 5_000 ms, admission 2_000 ms,
cancel 100 ms, attempts 512, progress count 256, credit 16, rate 20/sec. Byte
limits: Operation 262_144, Result 1_048_576, progress 8192, report 65_536; overrides
accept 1024 through the corresponding default ceiling. Count full serialized
envelopes, including identity/metadata, not just values. Unknown/invalid limits
fail startup. These bounds do not enforce a hard RSS cap or hostile-node sandbox.

### 4. Validation & Error Matrix

| Condition | Observation |
| --- | --- |
| Invalid description/deployment byte cap | immediate `{:error, :invalid_operation}` |
| Coordinator capacity/unavailable infrastructure | immediate `{:error, :capacity}` / `{:error, :unavailable}` |
| No eligible target | coordinator error `:no_target`; Execution nil |
| Definite admission rejection | `:ineligible` / `:capacity`; no retry |
| Admission timeout | uncertain / `:admission_timeout` |
| Connection/owner/endpoint loss | uncertain / `:connection_lost` or `:infrastructure_lost` |
| Deadline without observed termination | deadline / `:termination_unconfirmed` |
| Cancellation without observed termination | uncertain / `:cancel_unconfirmed` |
| Execution deadline initiated observed shutdown or Gateway kill escalation | deadline / `:worker_stopped` |
| Cancellation initiated observed shutdown or Gateway kill escalation | cancelled / `:worker_stopped` |
| Unrelated crash, even after cancel request | error / `:worker_lost` |
| Accepted racing success | remains successful |
| Malformed/oversize handler output | explicit invalid-result error |
| Malformed supplied prepared identity/changed description or versions at submit | `:invalid_operation`; no new prepare |
| Scope epoch rotated before claim | Actions `:stale_epoch`; no dispatch |
| Locked expected Operation or attempt CAS mismatch | Actions `:conflict`; no dispatch |
| Ref expired/shared infrastructure restarted | status unavailable; no reconstruction |

### 5. Good/Base/Bad Cases

Good: submit a valid generic handler Operation, correlate progress/result by ref
and attempt, ack progress, and handle a terminal uncertain result explicitly.
Base: shared-only node discovers endpoints but runs no executor and advertises no
execution capability. Bad: choose another workspace/node after uncertain admission,
accept a late mismatched Result, or describe worker death as external rollback.

### 6. Tests Required

Preserve Actions validation and Runtime lifecycle/composition/review tests. Assert
Actions-only authority schema and generic non-model/tool Handler execution through
journal/evidence/accept and reopened facts. Assert forged prepared fields and stale
refreshed bindings refuse. Control actual PG locks to cover restore-first/claim-first
and acceptance-before-claim; preserve no-Agent dependency and fresh-VM no-Repo checks.
Assert
whole-envelope byte limits, all-pool capacity, task-start failures, live auxiliary
progress/helper cleanup, membership leave invalidation, malformed reports,
idempotent cancellation and unrelated-crash distinction, terminal identity/races,
tombstone expiry/rejection watermark, provider/gateway/scope loss and retention.
Assert strict credential JSON/count/name/depth/UTF-8/exact-byte boundaries, recursive
mixed-case root-label rejection and unchanged ordinary secret policy. Observe local
and actual remote credential forwarding through a test handler while normal
progress/status/Result/report/error projections omit credentials. Assert complete
credential-inclusive protocol and reduced deployment boundaries at public submit
and direct remote Gateway admission.
Assert public/consumer admission parity, malformed budget, current reduced cap,
missing infrastructure, capacity normalization and ignored guarded startup. Observe
owner DOWN before resuming suspended public limits/supervisor/init limits/selection,
then prove no late execution. Preserve default remote ownership and guarded rejection.
Run `:distributed` tests explicitly using isolated named peer VMs; assert remote
execution, no fallback, concurrent capacity, partition uncertainty and delayed
admission without retry. Bound startup/teardown and use independent stdio control
for partition inspection. Same-host results are not physical-host acceptance.

Preserve `deadline_classification_test.exs`: use a genuine valid aged report and
actual admission to make the executor budget expire before the Coordinator timer;
assert actual worker DOWN and execution-source deadline/worker_stopped. Cover both
first-trigger orders against shutdown/kill, unrelated crash and racing success;
late/wrong-PID timers, duplicate completion/admission, one result, restored capacity
and zero remaining tasks. Keep unconfirmed deadline/cancel tests with a live worker
at terminal acceptance. Do not weaken errors or remove lease-age reduction to pass.

### 7. Wrong vs Correct

Wrong: wait for a full remote job in a GenServer callback, automatically retry on
lost acknowledgement, compare monotonic timestamps from different machines, or
restart temporary business work after infrastructure loss.

Correct: dispatch once, process correlated asynchronous admission/progress/result
messages, monitor ownership, use executor-local leases and timer-driven cleanup.
Temporary workers/coordinators and retained Results are deliberately ephemeral.
Wrong: infer deadline from the final DOWN time or relabel all worker_stopped errors
as cancelled. Correct: Gateway owns first-trigger provenance; Coordinator accepts
only valid correlated completion once and preserves that classification.
