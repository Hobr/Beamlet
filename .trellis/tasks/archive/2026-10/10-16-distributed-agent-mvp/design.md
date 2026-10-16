# Option-B Backend Design

## 1. Status and Boundaries

Implementation design approved by the user on 2026-10-16 ("批准"). Follow the accepted
`architecture.md` / `architecture_zh.md`; the archived architecture task stays
archived. This plan implements the approved B scope without future durability
machinery. API names below are planned interfaces, not existing callable code.

Dependency direction:

```text
actions -> []
runtime -> [actions]
harness -> [Req, Jason]                 # no other Beamlet app
agent   -> [actions, runtime, harness]
node    -> [actions, runtime, harness, agent]
web     -> [agent, Phoenix/LiveView]     # no new UI in this task
```

Keep runtime mechanisms in Runtime, provider code in Harness, translation in
`Beamlet.Agent.Integration.*`, and deployment composition in Node. Existing Web
does not need a new Agent dependency until it actually calls Agent APIs.
Reusable libraries expose opt-in child specifications, not automatic role trees.
Concrete provider/profile IDs are configured allowlisted data, never remote
module/function/closure injection.

## 2. Operation Contracts (child 1)

`Beamlet.Actions` owns structs/validation/behaviours:

- Operation: kind and protocol version, bounded data payload, opaque capability
  requirements, optional allowed nodes, resource claims, duration budget,
  bounded correlation metadata. No PIDs/references/functions/provider clients,
  credentials or absolute workspace roots in descriptions.
- Execution: operation ID, pre-admission attempt ID, target endpoint incarnation,
  state (awaiting admission/running/completed/uncertain), optional admitted handle.
- Result: operation ID, optional execution ID, status, safe reason/cause, bounded
  value, source (coordinator/execution), and observation metadata. Result is a
  value, not an independently supervised entity or a second Outcome abstraction.
- OperationRef/ExecutionHandle: explicitly ephemeral addresses/incarnations;
  runtime-only PIDs/monitor references stay out of Operation data.
- Handler behaviour: local worker entry `run(payload, context)`; context supplies
  neutral progress/cancel access and executor-resolved handler/provider settings.

Planned Runtime interface: `submit(operation, owner: pid, sink: pid)` →
`{:ok, operation_ref}` or immediate validation/capacity error;
`cancel(ref)`, `status(ref)`. The sink is installed at creation. Results/events
carry operation/ref/attempt identity, so clients need not infer identity from
arrival order. Each coordinator records at most one accepted Result, reusing an
execution-returned Result when valid. No target means no Execution; an attempt ID
is allocated before dispatch and is never reused for a retry.

## 3. Runtime Processes and Distribution (child 1)

Shared subtree on each composed product node: dedicated `:pg` scope, endpoint,
Directory and temporary Coordinator DynamicSupervisor. Directory bootstraps
reports, monitors membership and endpoint incarnations, refreshes periodically,
and expires snapshots by local monotonic receive time. Scope/directory loss
forces re-registration and fresh reports; old incarnations are invalidated.
A coupled shared infrastructure restart may invalidate coordinators: clients
observe unavailable/lost refs rather than reconstructed submissions.

Execution subtree: temporary Task.Supervisor plus Gateway, coupled
`:one_for_all`. Provider dependencies are supplied explicitly by Node. Gateway
accounting loss stops existing workers before new capacity is advertised.
Provider loss withdraws relevant readiness and invalidates its affected workers.
The coupling/monitor ownership is verified by fault tests, not merely a diagram.

Placement filters readiness, protocol, opaque capabilities/environment, hard
node constraints, freshness and reported capacity, then prefers lower utilization
with a stable node/incarnation tie-break. Gateway rechecks and atomically charges
all local pools before starting `Task.Supervisor.async_nolink` using an MFA wrapper.
Pools represent concurrent units, not OS CPU/memory enforcement.

Admission uses correlated bounded asynchronous messages, not a remote call that
blocks the gateway/coordinator for the whole job. Gateway validates operation,
attempt, coordinator and endpoint incarnation before charging. It owns task result
and monitor processing, emits normalized Result messages, and releases capacity
once per admitted handle. A start-ack/result race is handled by the preallocated
attempt identity. Duplicate dispatch for the same live attempt must not start a
second worker; a bounded record may reject stale duplicate messages, not introduce
a durable deduplication system or public retry permission.

Remaining duration is sent to the executor; absolute monotonic values are never
compared across machines. Deadline and admission observation timeout produce
coordinator-origin Results with honest uncertainty and best-effort cleanup.
No eligible target/definite rejection ends the submission; no queue/re-placement.
Executors monitor coordinator ownership; coordinators monitor owner and target.
After cancellation, observed worker DOWN can establish local worker termination;
partition or missing ack cannot. Kill/shutdown escalation is timer-driven and
does not block unrelated gateway admission. A racing accepted success stays success.

## 4. Bounded Events and State

Use one logical stream from wrapper → gateway → coordinator → Agent; provider
callbacks from auxiliary processes marshal through the wrapper. Identity and
operation-local sequence numbers reject stale/duplicate progress; delivery is
best effort. A progress credit/rate budget prevents an unbounded producer stream.
Terminal results are independent of display event loss.

Planned conservative configurable defaults (tune only with tests/docs):

| Boundary | Default limit / behavior |
| --- | --- |
| Active coordinators, including retained ones | 256 per node; reject excess |
| Terminal coordinator retention | 30 seconds; expired ref is unavailable |
| Operation payload / final Result | 256 KiB / 1 MiB; oversize is explicit error |
| One progress event / count per Operation | 8 KiB / 256; drop/coalesce with indication |
| Progress rate and in-flight credit | 20 events/sec and 16; no unbounded callback firehose |
| Directory refresh / expiry | 1 sec / 5 sec, configurable; local clock only |
| Admission observation / Operation budget | 2 sec / 60 sec default; bounded configuration |
| Agent count | 128 per authority; temporary Agents |
| Agent context | 128 messages and 1 MiB; reject further input/context growth explicitly |
| Model steps / Tool batch | 16 per turn / 8 calls; validate full batch before dispatch |
| Delegations / pending peer exchanges | 8 / 16 per Agent; reject excess |
| Subscribers / outstanding events each | 32 / 16; coalesce state/progress until acknowledged |
| HTTP response / Tool read | 1 MiB / 64 KiB retained, with independent bounds |

Serialized limits apply to the full envelopes, not just value fields. Invalid
executable descriptions/arguments are rejected, never truncated into executable
input. Text output truncation preserves UTF-8 and marks omitted data. Context
overflow ends/blocks a turn explicitly; do not drop tool-call/result pairs and
send a malformed conversation. Limits are application bounds, not a hard RSS cap.

Subscription sends the initial snapshot first from the same Agent process, then
sequenced events. Credit acknowledgements cap outstanding events; slow subscribers
receive a coalesced current-state indication once they consume/ack, not an
unbounded queue of missed events. Terminal turn state remains in the bounded
snapshot. Monitor subscribers; client loss does not stop the Agent. CLI handles
credits transparently; raw IEx protocol is documented. Runtime progress emission
also has an absolute per-operation count bound even if a generic sink never acks.

## 5. Native Harness and Concrete Providers (child 2)

Harness exposes native Tool catalogue/schema/invoke, model request/reply,
environment reference and context-policy interfaces. It imports no Actions or
Runtime. Native hooks are callbacks/tokens in local invocation context, never
operation refs. Agent adapters alone translate them into runtime events.

Real model: `Beamlet.Harness.Models.OpenAICompatible`, executor-local profiles
with configured API base/model/key-env name. Implement text Chat Completions
`/chat/completions`, `stream: false`, one choice, standard function tools. Keep
base-path joining correct. Normalize complete text or validated tool-call batches;
preserve assistant metadata and opaque unique Tool-call IDs. Reject length-limited,
filtered, refused, malformed or unsupported action-bearing replies. Optional
model-specific parameters are profile-controlled; no universal compatibility claim.

Use pinned Req 0.7.5 and explicit direct Jason dependency in Harness; Plug may be
test-only for Req.Test. Set `retry: false`, `redirect: false`, identity encoding,
peer TLS verification, and bounded synchronous `into` callback for all HTTP
statuses. Mark overflow explicitly: callback halt may otherwise look successful.
No unbounded automatic response decode/decompression before the byte guard.
HTTP idle/transport timeouts do not replace runtime's whole-operation deadline.
Configuration is trusted deployment input; reject unsafe/unexpected URL forms
and disallow HTTP except explicitly enabled local fixture/development profiles.
Never log Authorization, raw error bodies/prompts or credentials.

Tool schema support is deliberately explicit: object/properties/required,
additionalProperties, primitive types, enum and bounded string/numeric constraints
needed by the bundled Tool; reject unsupported schema keywords at registration.
JSON is decoded with string keys, never atomized. Validate the whole model batch,
including count/argument size/name/duplicate IDs, before submitting any work.

First workspace Tool: `workspace_read` for a relative text file in a configured
environment/root. Reject absolute/empty/NUL/traversal/ambiguous paths, symlinks at
any component, nonregular leaves and invalid UTF-8. Bound path length/depth.
Inspect components with lstat, open read-only in the worker, fstat the descriptor,
bounded-read at most max+1 bytes, close in all cases, and return truncated text
with metadata when necessary. A root label in the Agent profile maps to an opaque
capability and optionally allowed executor nodes; no root travels in Operation.

Important residual risk: OTP checks do not provide atomic `openat2` confinement.
Symlink swaps, hard links, mount changes, hostile local writers and pathological
filesystems are not contained. Deployment must supply a dedicated allowed-content,
non-adversarial local tree, preferably OS read-only provisioned, with controlled
backing writers. No OS sandbox or race-free confidentiality guarantee is claimed.
This is part of the proposed final review, not a previously user-approved assumption.

## 6. Agent Integration and Node Composition (child 3)

`Beamlet.Agent.AuthoritySupervisor` couples local unique Registry and temporary
Agent DynamicSupervisor. AgentRef identifies explicit authority, local ID and live
incarnation/PID. Restarted identities never validate old refs. Short lifecycle
requests verify authority readiness; no global Registry or silent fallback.

Planned facade: `start(authority, options)`, `input(ref, text)`,
`snapshot(ref)`, `subscribe(ref, sink)`, `unsubscribe`, `stop_turn(ref)`,
`delegate(parent_ref, children)`, and correlated peer request/reply operations.
One turn per Agent; concurrent input when busy returns an explicit error.
GenServer callbacks only update state and dispatch asynchronous work; no model,
Tool or child-turn wait inside a callback.

The integration adapter registers generic model/Tool operation kinds and resolves
provider/environment profile IDs on executors. Caller-side mapping adds opaque
capabilities and resource pools; execution-side handlers invoke ordinary Harness.
An executor can load these modules without any authority supervisor or Agent.

Loop: accepted input → bounded Harness context → model Operation → normalized reply.
Final text ends turn. Valid complete Tool batch starts independent Operations up
to its bounded maximum; track turn/operation/tool IDs and stable original order.
After all observations are joined, append valid tool messages and request the next
model step. Tool failures become bounded correlated observations; model/runtime
uncertainty or malformed model batches stops/fails explicitly without blind retries.
Stopping freezes turn advancement before cancellation; late events cannot revive it.

Delegation: the Agent public API starts ordinary temporary children on selected
authority-ready nodes, correlates child refs/turns/delegation IDs, and joins final
child replies into a parent-owned waiting state/observations. An idle parent may
start a delegated group turn; a busy parent rejects incompatible delegation commands
rather than modifying an in-flight model context. After children join, a configured
parent continuation can run its next model step. The client/API drives delegation;
no new model-facing delegation Tool or autonomous policy is needed.

Peers: bounded request ID + sender/receiver Agent incarnation + turn identity,
with asynchronous response events. Requests do not implicitly become user input or
trigger tool execution; the receiver exposes them to its Agent-facing mailbox/API,
and an explicit Agent command/policy replies. Independent peer lifetimes are not
coupled. No durable inbox/callback framework is introduced.

Delegator monitors and stop propagation request cleanup of owned child turns.
Replies from stale generations or after stop are ignored. Parents waiting/joining
hold no gateway resources. Child loss is a correlated failure, not transparent
recreation. Bounded retained conversation/active-message state is ephemeral.

Node owns role validation, shared/authority/execution child selection, explicit
handler registration, provider supervision/readiness and resource pools.
Provider children are ready before Gateway advertises their capabilities; a
monitored provider disappearing invalidates affected work/capabilities.
All roles may share a node; local operations still use Gateway admission.
No model key/workspace service is started just to inspect a catalogue on authority.

## 7. CLI, Release and Multi-machine Deployment (child 4)

Expose a small `Beamlet.Node.CLI` facade plus repeatable script/examples using
release console/RPC or a named interaction node. Support ask/watch/status/stop,
explicit authority selection and delegation/peer examples. CLI may wait for
results outside Agent callbacks; it acknowledges event credits and bounds printed
output. Do not add a second Agent loop, full terminal UI or HTTP control server.

Define `beamlet_node` release rooted in `:beamlet_node`, closing only over its
declared core dependencies. Exclude Web/Phoenix/LiveView/PubSub/Bandit artifacts,
not merely their listeners. Build-time umbrella compilation may still use Phoenix.

Web runtime configuration must be gated consistently with actual Web activation.
Prefer a backend-release-specific runtime configuration (Mix release runtime_config_path)
sharing a small backend configuration include, while preserving the existing
default production Web secret fail-fast path. If using an explicit activation
flag instead, test disabled/enabled boot together so Web cannot start with a
silently skipped secret check. Decide the exact selector by testing Mix 1.20
release behavior, without changing user-visible scope or weakening TLS/CSP.

Configure roles, static peers, named-node identity/cookie, resource capacities,
provider profile IDs, executor-local key/root and readiness. Parse only trusted
bounded node names from deployment config; never create atoms from model output.
Use long names/reachable DNS or host addresses for physical machines. Document
trusted-network EPMD/fixed distribution ports and cookies; no untrusted WAN exposure,
automatic discovery, TLS-distribution rollout or authentication system is added.

Automation: controllable fake handlers/providers across isolated `:peer` nodes,
with alternative stdio control during partition tests. Assert correct execution
node/authority and cleanup; do not infer absence of side effects from DOWN.
Revised acceptance: A client, B authority, C executor in independent VMs, using a
local real HTTP fixture and executor-only marker, with explicit role/correlation,
stop/loss and no-fallback assertions. User cancelled cross-physical-host acceptance;
physical deployment instructions remain optional and no physical run is claimed.

No paid request is authorized by this plan. Local compatible HTTP fixtures test
the real adapter deterministically; a separate opt-in live smoke uses operator
credentials, endpoint/model and spending approval without printing secrets.

## 8. Compatibility, Rollout and Rollback

No supported domain API exists to preserve. Replace generated hello-world tests
with behavioral tests; unrelated Web scaffold/security remains intact. Document
that refs/results are ephemeral and schema/version compatibility across different
builds is not guaranteed; deploy one compatible build to all participating nodes.

Land/gate runtime, independent Harness, Agent composition, then release/integration.
Do not enable real providers before no-retry/cancel/uncertainty tests pass.
On a failed gate, stop at that boundary and revise scoped files; never reset user
changes or replay work as rollback. Application restart loses in-memory business
state by design. Record executable contracts in backend specs after verification.
