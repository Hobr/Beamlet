# Agent Orchestration and Node Composition

## 1. Scope / Trigger

Use when wrapping Agent APIs, adding integration handlers, or composing Node roles.
Agent depends on Actions/Runtime/Harness; Node composes those libraries. Runtime
imports no Agent/Harness code. Sources are `apps/beamlet_agent/lib/beamlet/agent/`
and `apps/beamlet_node/lib/beamlet/node/`. Provider-migration source passed fresh
independent repair recheck and rebuilt release gates. Physical-host acceptance was
removed by user decision; no physical or paid/live execution is claimed.

## 2. Signatures

```elixir
binding = %{provider: "openai-compatible",
  config: %{"base_url" => "https://example.test/v1", "model" => "model-name"},
  credentials: %{"api_key" => supplied_key}, placement: %{claims: %{"requests" => 1}}}
{:ok, ref} = Beamlet.Agent.start(authority_node, id: "example", model: binding)
{:ok, turn} = Beamlet.Agent.input(ref, "hello")
{:ok, snapshot} = Beamlet.Agent.snapshot(ref)
:ok = Beamlet.Agent.subscribe(ref)
:ok = Beamlet.Agent.ack(ref, sequence)
:ok = Beamlet.Agent.unsubscribe(ref)
:ok = Beamlet.Agent.stop_turn(ref)
:ok = Beamlet.Agent.close(ref)
Beamlet.Agent.delegate(ref, [%{authority: node, options: opts, input: text}], opts)
Beamlet.Agent.peer_request(ref, target_ref, payload, ttl_ms)
Beamlet.Agent.peer_reply(ref, request_id, payload)
Beamlet.Agent.peer_take(ref, request_id)
Beamlet.Agent.inbox(ref)
{:ok, pid} = Beamlet.Node.start_link(roles: [:authority])
```

Agent commands wait only for command handling (5000 ms call timeout), never model,
Tool or child completion. Remote start uses explicit authority and bounded erpc.
Ref contains authority node, binary ID, incarnation and live PID; it is ephemeral.
Explicit live lookup is available below; no authority fallback, durable recovery or replay exists.

## 3. Contracts

Agent options: id (1..128 UTF-8 bytes), one immutable model binding, optional tools
map, validated catalogue, internal delegator PID and optional safe display_metadata.
Display option validation, source annotations and public view schema are specified
in [Live Observation](./live-observation.md). Binding has exactly provider,
config, optional credentials/default%{} and placement/default%{}. Placement permits
environment/allowed_nodes/claims under existing Operation bounds. Provider ID matches
`[a-zA-Z0-9_-]{1,64}`; common invocation config/credentials follow Native Harness limits.
Actual creation validates the installed authority adapter; unknown providers, legacy
model routes, top-level api_key, collections/switching and extra fields reject as
invalid_agent_options. Binding stays fixed across steps/turns in private Server state.
Tool routes retain portable profile/environment/capability/claim data and executor-local
workspace settings. Native catalogue inspection requires no credentials or provider IO.

AuthoritySupervisor accepts model_providers (same built-in defaults as Harness.Model)
and stores trusted immutable registration in local Registry metadata. Agent never
depends on Node. Caller model payload has exactly type/provider/config/request
(`%{"type" => "model", "provider" => id, "config" => config, "request" => request}`),
requires `model.provider:<id>` capability and puts credentials only in Operation.credentials.
Tool payload retains profile/request and empty credentials. Handler settings contain
profiles/model_providers; it resolves only local implementations and revalidates common
invocation, neutral request and selected adapter. Tool Handler rejects nonempty
credentials and gives Tools only native progress/cancelled? Context hooks. No model
config/credentials enter normal history, snapshots, progress, Results or diagnostics.
Transient plaintext copies remain until ordinary cleanup; no secure erasure or
protection from malicious provider echo/admin inspection is promised.
Caller constructs bounded Operations; OperationOwner calls public Runtime.submit
with its local lifecycle controller as owner/sink and require_live_owner:true.
Runtime owns admission validation, current byte caps, allocation and normalization.
No consumer may construct private coordinator specs, IDs or refs.

One active turn per Agent. Context append rejects overflow rather than evicting
assistant/tool pairs (128 messages, 1 MiB native JSON). Input is at most65536 UTF-8
bytes. Model steps are bounded at16; Tool batches at8. Validate the complete native
reply and sibling batch before dispatch. Independent Tools run concurrently; join
by call ID, construct canonical assistant history via Model.assistant_message/1
and append call_id observations in original order. Generic Server/Handler use
Model validators and never reconstruct OpenAI envelopes. Captured
Operation byte limit is pure callback validation; public submit also checks current
Directory limits. Absent Directory permits standalone default262144; a present but
unavailable Directory fails rather than widening the ceiling.

AuthoritySupervisor couples Registry, Resources, Delegations Task.Supervisor and
Agents DynamicSupervisor with one_for_all. Maximum128 Agents; separate1024 quotas
for operation/delegation controller groups, at most8 of each retained per Agent.
Controllers own linked blocking workers and fixed5s registration/admission timers,
plus fixed65s total lifetime. Timers run outside blocked calls. Resource groups
remain charged until all recorded members are DOWN; business terminal acceptance
alone does not retire ownership. Follow-on scheduling waits asynchronously for
retirement. Duplicate register/track for an inventoried PID is inert. Resources
fences previous VM-local infrastructure PID inventory before authority readiness;
persistent_term stores no business messages/results or replay state. Authority
Agents/Delegations supervisors have1000ms shutdown caps.

Delegation accepts1..8 explicit authority/options/input specs, with startup
parent authorization before child input. Parent checks portable child options,
catalogue/Tool routes and common binding bounds through ModelBinding.portable?/1,
without consulting its registry or invoking an adapter. Actual child authority
resolves its own registry and validates the adapter via ModelBinding.valid?/1.
Registries may differ: a target-only provider must be delegatable. Target creation
rejection yields the existing correlated safe authority_unavailable child error,
with one dispatch and no retry. Common-invalid specs reject before helper spawn.
No child or peer binding/credential inheritance occurs. Helpers/children are owned through links,
monitors and resource groups; stop/loss requests cleanup even across nested work.
A waiting parent holds no executor capacity. Late replies cannot advance an old
turn. Peers have independent lifetimes; requests are API mailbox data, never
implicit input or executable Tools. Peer TTL1..60000ms, pending+inbox bound16,
full wire and keyed retained envelopes at most8192 serialized bytes.

Subscriptions: `{:beamlet_agent, ref, sequence, {:snapshot, snapshot}}` from Agent.
Snapshot fields: ref/turn/terminal_turn/status/steps/final/progress. Initial snapshot
precedes updates from the same sender; acknowledge every consumed sequence from
the sink process (ack/2 identifies self()). Maximum32 subscribers,16 outstanding
each. Slow sinks get a coalesced current snapshot after acknowledgement; sink DOWN
removes subscription only. No event-history replay. Snapshot display limit is
1048000 serialized bytes; excess yields snapshot_limit for the base snapshot.
Opt-in display overloads use the same credit path and fit/omit additions without
invalidating a valid default snapshot. Node observation APIs are also documented
in [Live Observation](./live-observation.md); discovery remains identity-only.

Node config keys: roles, profiles, model_providers, providers, pools, limits,
allowlist, routes, catalogue. Nonempty distinct roles are interaction/authority/executor;
all seven subsets are supported. Profiles (max32) are Tool-only executor-local maps
with type/module/settings/capability and optional environment; callbacks must exist
and be allowlisted. Legacy type:model profiles reject invalid_node_configuration.
model_providers is a trusted map<=32 of IDs to loaded modules exporting both Model
callbacks, defaulting to built-ins. It is separate from monitored providers PIDs.
Executor advertises `model.provider:<id>`; combined Tool/model capability union<=32
and complete Runtime report/deployment caps are validated. Node validates common
Runtime limits through Limits.new for every role set before returning children;
executor-specific Report checks remain conditional on the executor role. Registration/readiness
calls no model network API and reads no model key environment. Routes (max64) and
catalogue remain portable Tool data. Node uses one_for_all;
executor starts Provider before Runtime, with provider monitoring. Authority adds
AuthoritySupervisor; executor-only starts no Agents/Registry. All local work uses
Gateway admission. Node has no Application callback or boot configuration reader. An embedding
supervisor explicitly starts `{Beamlet.Node, options}`; all seven combinations
are tested as running trees, including a three-role local model turn through Gateway.
`Beamlet.Node.Cluster` owns trusted-name validation, a single connection attempt
with a five-second helper budget, and connected-node allowlist filtering (at most32
trusted ASCII names, each at most255 bytes). No CLI/server dependency is introduced.
CLI owns the terminal client and bounded foreground session; its opt-in Application
starts only interaction, and ordinary loading remains empty.
Server is disabled by default, explicitly supervises Node when enabled, and accepts
only authority/executor startup role selections. Its owned temporary task connects
validated peers once after Node is ready, without blocking supervision or retrying
business work. Server release/runtime config now replace the old Node entrypoint; see
[Backend CLI and Release](./backend-release.md).

## 4. Validation & Error Matrix

| Condition | Observation |
| --- | --- |
| Missing authority / dead live ref | authority_unavailable / unavailable |
| Invalid Agent options | invalid_agent_options startup failure |
| Input during active turn | busy |
| Invalid/oversize input or unreleased owners | invalid_or_oversize_input |
| Context / step / dispatch failure | explicit terminal error, no retry |
| Duplicate / excess subscription | already_subscribed / subscriber_limit |
| Ack without subscription | not_subscribed |
| Invalid/excess peer request | peer_limit_or_invalid_message |
| Oversize / stale peer reply | message_limit / stale_peer_request |
| Invalid Node config | invalid_node_configuration; startup raises |
| Registry/provider/gateway loss | refs/work/readiness invalidated; no replay |

## 5. Good/Base/Bad Cases

Good: subscribe, consume snapshot, ack from sink, dispatch independent valid Tools,
join by identity and stop by freezing the turn before requesting cleanup.
Base: authority-only Node starts with trusted adapters and no provisioned user key
or workspace root; each Agent receives its own explicit model invocation binding.
Bad: infer owner retirement from a Result, retry uncertain work, or synchronously
wait for admission inside an Agent callback.

## 6. Tests Required

Preserve Agent/Node lifecycle, review, concurrent Tools and named distributed suites.
Assert actual DOWN while admission/Directory/ack/child infrastructure remains
suspended, then no late work after resume; nested cleanup, startup authorization,
partial helper admission, restart fencing, inventory idempotency and slot retirement.
Test real native progress followed by terminal completion and blocked ack. Assert
invalid sibling means zero dispatch, reversed completion retains original order,
concurrent Agents, progress attempt/sequence/turn identity and full peer envelopes.
Snapshot must be first; slow/down sinks stay bounded and cannot stop Agent. Cover
all role subsets, executor-only no Registry, local Gateway, provider/Registry loss,
remote authority disconnect and no capability/environment fallback. Cover immutable
binding across turns, distinct keys/configs on one executor, alternate protocol provider,
normal output/Tool credential absence and explicit child/independent peer options.
`delegation_binding_test.exs` must keep distinct authority registries and prove direct
and delegated target-only provider input completion, target rejection with one dispatch,
no parent adapter callback, and malformed/oversize portable rejection with zero helper
spawn. Never fix this regression by giving parent and target identical registries. Same-host
peers prove automation only; LSP unavailable/timeout remains inconclusive.

## 7. Wrong vs Correct

Wrong: move a blocking call to a raw helper and assume its receive timeout bounds
admission; remove slot accounting when business work completes; duplicate Runtime
coordinator construction to add an owner guard.
Correct: nonblocking controllers interrupt linked workers, Resources retains groups
until DOWN, and public Runtime owns guarded submission with unchanged validation.
Local owner checks are not atomic with dispatch; subsequent loss uses monitors and
best-effort cleanup, without guarantees of provider rollback or remote termination.

## Live discovery and attachment

`Agent.list(authority)` returns `{:ok, [%{authority: node, id: binary, pid: pid}]}`.
`Agent.lookup(authority, id)` returns the present real Server Ref;
`Agent.lookup(%{authority: node, id: id, pid: expected_pid})` rejects a replacement
PID as `{:error, :stale_agent}`. Descriptor maps contain exactly those three keys.
Queries never construct Ref, inspect private state, submit input or recreate an
Agent. Explicit authority+ID chooses the currently observed instance; saved Ref
always keeps its original PID/incarnation. ID is1..128 valid UTF-8 bytes. Static
errors: invalid_query, not_authority, not_found, unavailable, timeout, stale_agent,
limit. A closed descriptor with no current registration returns not_found.

List enumerates Registry identities, max128, without waiting for each Server.
Lookup asks that PID's existing `:ref` handler and verifies authority/ID/PID and
reference incarnation. Queries have one5s local receive budget. Only already
connected remote nodes are queried at entry. Local reads use a disposable OTP Task;
remote reads use fixed `:erpc.call(authority, Discovery, :query_local, [query, budget], budget)`.
The entry accepts only list or validated lookup and relative integer budgets1..5000ms,
creates its deadline on the executing VM, and waits for Server only within that budget.
Registry identity is checked before and after the read. Authority capability comes
from AuthoritySupervisor/Registry; loaded non-authorities return not_authority,
missing code/unreachable nodes return unavailable. Registry loss still invalidates
Agents through the existing identity island. Query execution has no supervised
endpoint and its death cannot restart that island. Matching library builds are required.

`Node.Agents.discover([trusted_node_atom, ...])` returns
`{:ok, %{agents: descriptors, failures: %{node => static_reason}, complete: boolean}}`.
Use Cluster.authority/2 to resolve trusted configured names; discovery uses
Cluster.connected/1 filtering and never atomizes input. Initially disconnected
targets are rejected; subsequent OTP reconnection is permitted. Invalid or
duplicate targets / >32 nodes return invalid_query wholly. Empty request completes.
An alive allowlisted local node follows Cluster inclusion. Max8 requests run at
once; queued requests share one5s receive deadline. Serialized full `{:ok, result}`
is<=1MiB, conservatively reserving16KiB for all32 possible failure projections.
An overflowing authority is rejected as limit, without truncating its identities;
subsequent failures fit in the same envelope. Every failed requested node is
explicit, including non-authority/unavailable/timeout/limit. `complete` describes
only the requested set. Liveness is an eventual observed view, not an atomic
cluster snapshot; subsequent commands can still lose the returned instance.

Transport follows standard OTP semantics. An initially disconnected target is
rejected; after the connected precheck, a disconnect may trigger OTP reconnection.
There is no application query retry, business replay or automatic Agent recreation.
Caller timeout/exit abandons the response; already issued remote reads may finish
within their own finite budget, which starts when the entry executes. Delayed
execution can therefore begin after local abandonment. No instantaneous cancellation,
300ms remote retirement, expired-admission rejection or mailbox retraction is promised.
Task/erpc/GenServer response correlation discards late replies. Scheduling can delay
timeout delivery; the budgets are not hard real-time guarantees.

There is no query endpoint, offer/confirmation/challenge/heartbeat/lease protocol,
or former256 offer/controller quota. No new global admission service is added.
Per-query128 identity/1MiB limits and per-aggregation32 targets/8 requests/5s deadline
remain. No credentials/options/binding/history enter discovery results.

Regression gates: real local and named remote Server suspension, query execution
kill with unchanged Agent/Registry/supervisor identity, finite remote completion
before Server resume, late response isolation, same-name authorities, descriptor
replacement, Registry loss, all seven role subsets, trusted input and full-envelope
limits. Resource tests delay code loading on ten peers to observe eight in-flight
requests and a single receive deadline. Same-host tests do not prove physical deployment.
Wrong: infer remote cancellation from caller timeout, or promise never reconnect
from a connected precheck. Correct: finite independent reads and explicit partial failures.

## Durable fork, environment risk and evidence resolution

Opt-in only, next to `Beamlet.Agent.restore/3` and `continue/4`; an Agent started
without `durable:` keeps exactly the old behaviour.

```elixir
locator = %{repo: repo, agent_id: source_id, model: binding, tools: tools,
            catalogue: catalogue, environment: ref | nil, runtime: runtime | nil,
            source: %{freeze: :frozen | :idle, environment: :confirmed_stopped | :unconfirmed}}
{:ok, %{agent_id: new_id, checkpoint_id: cp, locator: new_locator, source: %{...},
        risk: nil | "unconfirmed", copied: %{"messages" => n, "records" => n},
        version: 0, generation: 0}} =
  Beamlet.Agent.fork(locator, checkpoint_id, expected_version, command_id)
{:ok, %{continuation: "await_input", version: v, generation: g}} =
  Beamlet.Agent.continue(ref, expected_version, %{"risk" => "accepted"}, command_id)
{:ok, %{continuation: pos, version: v, generation: g}} =
  Beamlet.Agent.continue(ref, expected_version,
    %{"resolution" => "confirmed_executed" | "confirmed_failed",
      "operation_id" => op_id | nil, "evidence" => map | nil}, command_id)
```

- `Agent.fork/4` refuses while the source instance is still registered locally
  (`:source_not_frozen`): a live local dispatcher is not a frozen source. The
  source's own rows are never written by a fork, and the old locator/Ref/alias
  keep pointing at the source; callers must use the returned locator.
- Fork copies one immutable checkpoint only, and only when it is a complete
  boundary (`safe_to_fork`, no pending/join/results/assistant/blocked state, full
  Tool-call/result pairing, `await_input`/`await_model_result`/`completed`). Refusals:
  `:unsafe_checkpoint`, `:source_not_frozen`, `:limit` (over 1 MiB or 128
  messages), `:conflict` (stale source version, wrong checkpoint owner, replayed
  command with different params), `:artifact_missing`. Nothing is written on
  refusal. A retried identical command returns the same new locator.
- The new Agent starts paused at `await_input`. Copied messages keep their exact
  shape; provenance is carried by new `context.inherited` events with
  `source_agent_id` + `source_checkpoint_id` markers, `agents.forked_from_*` and
  the checkpoint's `fork`/`environment` metadata. No Operation, Execution,
  evidence, pending/join/consumption, command, cancellation, delegation or peer
  state is copied, and no parent read is needed to restore it.
- Execution gate: `environment.risk == "unconfirmed"` (caller-declared unconfirmed
  stop, or any accepted `uncertain`/`deadline`/`cancelled`/`unknown` source Result)
  makes `Durable.accept_input/2` return `{:error, {:blocked, :environment_risk_unconfirmed}}`
  until `%{"risk" => "accepted"}` is recorded as an `agent.risk_accepted` event.
  Omitting `locator.source` means `idle` + `unconfirmed`: the quiet default never
  grants execution. A read-only history copy or export never grants execution.
- Resolution: an accepted Result is never overwritten. A decision that adopts late
  evidence names the Operation; the transaction re-reads it and refuses on an
  ownership or accepted-Result digest mismatch (`:conflict`). If the Tool slot is
  still empty it is filled once from the stored Result; if it is already occupied
  the adoption appends one `user` correction message instead of a second Tool
  result. The evidence map and its digest stay in the `agent.decision` event.
