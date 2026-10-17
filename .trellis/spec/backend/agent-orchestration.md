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
No global lookup, authority fallback, durable reconnect or replay exists.

## 3. Contracts

Agent options: id (1..128 UTF-8 bytes), one immutable model binding, optional tools
map, validated catalogue and internal delegator PID. Binding has exactly provider,
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
1048000 serialized bytes; excess yields snapshot_limit.

Node config keys: roles, profiles, model_providers, providers, pools, limits,
allowlist, routes, catalogue. Nonempty distinct roles are interaction/authority/executor;
all seven subsets are supported. Profiles (max32) are Tool-only executor-local maps
with type/module/settings/capability and optional environment; callbacks must exist
and be allowlisted. Legacy type:model profiles reject invalid_node_configuration.
model_providers is a trusted map<=32 of IDs to loaded modules exporting both Model
callbacks, defaulting to built-ins. It is separate from monitored providers PIDs.
Executor advertises `model.provider:<id>`; combined Tool/model capability union<=32
and complete Runtime report/deployment caps are validated. Registration/readiness
calls no model network API and reads no model key environment. Routes (max64) and
catalogue remain portable Tool data. Node uses one_for_all;
executor starts Provider before Runtime, with provider monitoring. Authority adds
AuthoritySupervisor; executor-only starts no Agents/Registry. All local work uses
Gateway admission. Default Application boot is empty; `:beamlet_node, :boot`
options opt into Node composition. Backend release loads them from an absolute trusted
BEAMLET_CONFIG file; see [Backend CLI and Release](./backend-release.md).

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
