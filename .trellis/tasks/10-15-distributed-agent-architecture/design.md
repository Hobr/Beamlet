# Distributed Agent Architecture — Accepted Baseline

## 1. Status and Design Position

The user approved the latest revised architecture summary ("同意以上设计"). This document records the accepted architecture baseline, not an implemented system. Confirmed requirements are in `prd.md`; OTP evidence and links are in `research/otp-execution-primitives.md`. Approval covers architecture only and does not authorize application implementation. Material design changes require renewed review.

Build a small, general-purpose distributed action runtime, then compose an AI Agent and its Harness above it. Use ordinary Distributed Erlang, supervision, process monitors, local registries, and explicit node addresses. Do not build a workflow engine, an algebraic Effect framework, a globally consistent scheduler, or a durable event system for the MVP.

The three fundamental separations are:

1. **Decision vs execution:** the Agent decides the next step; the action runtime places and observes work.
2. **Policy/context vs mechanism:** Harness defines Tools, model integrations, and environments; the generic runtime knows only action descriptions, handler capabilities, placement constraints, resource claims, and outcomes.
3. **Library vs deployment:** being a compiled dependency does not grant a node a role or start that role's services.

## 2. Terminology and Ownership

| Term | Meaning | Owner |
| --- | --- | --- |
| Action | A data description of one requested operation, independent of AI | `beamlet_actions` |
| Action coordinator | An ephemeral process that places and observes one submitted action and handles control requests | `beamlet_runtime`, on the submitting node |
| Executor gateway | A node-local admission and execution-management process | `beamlet_runtime`, on an execution node |
| Worker | A temporary supervised process running one handler invocation | `beamlet_runtime`; handler implementation supplied by the caller ecosystem |
| Capability | An opaque, advertised ability or access condition used in eligibility matching | Generic representation in actions/runtime; meaning supplied above them |
| Resource claim | Requested units from locally enforced capacity pools | Generic runtime |
| Environment | A provider-owned workspace/session/sandbox context, not synchronized by Beamlet | Harness/environment provider |
| Agent | An AI conversation/reasoning loop with one explicit authority node | `beamlet_agent` |
| Harness | The catalogue, context-building policies, Tool/model adapters, and environment integrations used by an Agent | `beamlet_harness` |
| Node composition | Configuration and startup of a concrete combination of roles/providers | `beamlet_node` |

An AI Agent is not Elixir's `Agent` state container. Prefer a `GenServer` with an explicit loop state and asynchronous action messages; do not use `Agent.get_and_update` to run LLM or Tool work.

## 3. Umbrella Applications and Dependency Direction

Proposed package names are reviewable; the responsibilities and dependency direction are the important decisions.

| Application | Responsibility and public interface | Explicit exclusions |
| --- | --- | --- |
| `beamlet_actions` | Data contracts for action descriptions, handles, events, outcomes, and handler behaviour | No processes, scheduling, Agent semantics, Phoenix, or storage |
| `beamlet_runtime` | Generic submission/control interface; discovery, placement, local admission, supervised execution, progress and outcome collection | No Tool catalogues, prompts, LLM provider schemas, environment synchronization, or user interfaces |
| `beamlet_harness` | Backend-neutral Tool catalogue/schemas and invocation interfaces, model request/reply normalization, context policies, environment references/providers | No actions/runtime dependency, action handlers, Agent-loop orchestration, or global scheduler |
| `beamlet_agent` | Agent lifecycle/loop, Tool-call orchestration, UI-independent commands/events, plus a separately isolated action integration adapter | No concrete HTTP provider or sandbox implementation; no Phoenix dependency |
| `beamlet_node` | Product composition root: role validation, selected child specifications, explicit handler registration, provider wiring, readiness and deployment configuration | Not the generic execution engine; no reusable runtime algorithms or Agent policy |
| `beamlet_web` | Phoenix/LiveView presentation and adaptation of Agent commands/events | No Agent-loop state ownership, placement decisions, or direct Tool execution |

Dependency arrows below mean **depends on**, not event flow:

```text
beamlet_actions  -> []
beamlet_runtime  -> [beamlet_actions]
beamlet_harness  -> []
beamlet_agent    -> [beamlet_actions, beamlet_runtime, beamlet_harness]
beamlet_node     -> [beamlet_actions, beamlet_runtime, beamlet_harness, beamlet_agent]
beamlet_web      -> [beamlet_agent, Phoenix/LiveView]
```

Here `[]` means no dependency on another Beamlet application, not a ban on normal third-party libraries.

There is no `runtime -> harness` or `harness -> actions/runtime` dependency. The integration adapter inside `beamlet_agent` knows both sets of contracts. Its caller-side translation creates action descriptions, maps native environment descriptions into placement/resource requirements, and converts action outcomes into Agent observations. Its executor-side handlers implement the actions behaviour and invoke ordinary Harness Tool/model interfaces. This is one isolated integration module group, not an additional Mix application or the Agent loop itself. Its handler code can run on an executor without starting an Agent process.

Harness authors provide native Tool/model operations and neutral progress/cancellation hooks, not Action structs, executor behaviours, resource-pool keys, or ActionRefs. The adapter translates those hooks to runtime events/control. A Harness implementation can be exercised directly in a local test without actions/runtime. Generic callers can likewise use actions/runtime without Agent, Harness, or Phoenix.

At startup the product composition root supplies registered handler specifications and provider children to the generic execution subtree. Because it references action registration contracts, this revision lists `beamlet_actions` as a direct dependency rather than relying on its transitive presence. If an eventual implementation only calls runtime child specifications and never references action contracts, that unused direct dependency should be removed.

A physical BEAM node is not the `beamlet_node` package. The physical execution node runs a gateway/worker mechanism implemented by `beamlet_runtime`; `beamlet_node` merely configures and supervises that mechanism. The package name is provisional and should not imply that execution logic belongs in the composition root.

### Why these splits

- The actions package owns a real cross-package protocol, including the handler interface, without requiring a runtime or AI dependency. It is not a set of forwarding functions.
- Runtime hides remote placement, supervision, observation, and cancellation behind a small submission/control interface.
- Harness isolates the things expected to vary between Agent deployments: Tools, model providers, prompt/context construction, and environment integrations.
- Node composition deserves a separate application because reusable libraries must not start every available role as a dependency side effect.
- Do not add separate applications for each provider, directory, scheduler, event type, or policy yet. Provider-specific packages can be extracted if dependencies or independent reuse justify them later.

## 4. Deployment and Role Composition

### Roles

- **Interaction:** hosts a client/UI integration that issues Agent commands and receives observations. It need not host Agent loops or execute actions.
- **Authority:** hosts Agent processes and their action coordinators. It need not execute any action locally.
- **Execution:** hosts an executor gateway, worker supervisor, and configured handler/environment providers. It need not host an Agent loop or UI.

Any subset can be configured. A node with all three roles follows exactly the same interfaces; local execution is a normal eligible target, not a bypass of admission or action accounting.

All participating BEAM nodes must already be connected in one trusted cluster. Initial connection may be manual/static (`Node.connect`/release configuration). `:pg` discovers endpoints on the connected cluster; it does not establish the cluster. Automatic cluster discovery may later use an ecosystem library if deployment needs it, but is not required to demonstrate the MVP.

### Library availability is not service activation

Actions, runtime, Harness, and Agent are reusable library applications that expose child specifications rather than unconditionally starting their full service trees from an application callback. `beamlet_node` starts the configured roles. `beamlet_web` is a separate Phoenix application and release entry point, enabled only in interaction deployments.

In particular, Agent code may be present transitively in an executor build without starting an authority supervisor. Provider descriptions can be available on an authority node without starting a sandbox or loading execution credentials there. An executor-only release need not include `beamlet_web` or Phoenix.

For the MVP, one product-node release can contain the libraries and choose roles at boot; a web release additionally starts `beamlet_web`. This does not promise minimal code artifacts for each role. Mix release dependency closure and startup modes must be tested before claiming that packaging omits a library. Avoid suppressing dependency startup using unsafe release-mode overrides.

Role declarations are capabilities of the deployment, not permissions or a security boundary. The generic runtime interprets execution readiness; interaction/authority labels and their service implementations are supplied by product composition.

### Conceptual supervision shape

```text
Beamlet.Node.Supervisor
  Runtime.SharedSupervisor                         all product nodes
    dedicated :pg scope
    NodeEndpoint                                  role/capability/resource reporting
    Directory                                     local snapshots of discovered endpoints
    ActionCoordinatorSupervisor                   temporary coordinators, bounded count
  Agent.AuthoritySupervisor                       authority role only
    local Registry
    DynamicSupervisor                             temporary Agent processes
  Harness.ProviderSupervisor                      configured execution providers only
    environment/session/sandbox provider children
  Runtime.ExecutionSupervisor                     execution role only
    Task.Supervisor                               temporary action workers
    ExecutorGateway                               handler table, admission, worker handles

Beamlet.Web.Supervisor                            separate interaction application
  Phoenix Endpoint / LiveView supervision
```

Harness providers become ready before the execution gateway advertises their capabilities. Execution infrastructure uses a coupled subtree (for example `:one_for_all` around worker supervisor and gateway): if the gateway loses its task/accounting state, its workers are stopped as well, rather than left unaccounted while fresh capacity is advertised. Provider loss withdraws the relevant capability/readiness and invalidates affected work; provider ownership must be wired explicitly during implementation.

Authority Registry and Agent supervision likewise form an infrastructure island: losing identity/registration infrastructure invalidates its in-memory Agents rather than pretending those Agents can be reconstructed. Normal infrastructure may restart; Agent processes, action coordinators, and action workers are temporary and are not automatically replayed or restarted from their original inputs.

The exact supervisor strategies are implementation details to validate through fault tests. The required property is ownership without silent business-operation re-execution.

## 5. Discovery, Reporting, and Scheduling

### Node report

Each node endpoint advertises a bounded data snapshot containing:

- node address and endpoint incarnation;
- declared roles and currently ready services;
- configured handler protocol/action kinds and opaque capability labels;
- provider-advertised environment access labels;
- locally enforced resource-pool totals and current availability;
- optional advisory host information (CPU/memory/GPU labels), without pretending these are reservations;
- report revision. Freshness is measured by the receiver's local receive time, not synchronized wall clocks.

Do not broadcast secrets, provider clients, open file/socket handles, or entire workspaces. A provider/profile label can indicate access to an LLM credential configured only on its execution node.

Use a dedicated `:pg` scope for node endpoints and directory subscribers. A joining directory requests initial reports; endpoints publish periodic or materially changed snapshots. Membership changes and endpoint monitors invalidate cache entries. Reports expire locally after a configured freshness interval; expired/unready candidates are excluded. Endpoint restart requires re-registration and a fresh report.

This is an ephemeral discovery cache, not a replicated database. There is no cluster-global authority directory, consensus protocol, or special singleton scheduler.

### Placement and local admission

Each action coordinator chooses a target using its local directory:

1. Filter for a ready execution endpoint and compatible handler kind.
2. Match required opaque capability labels, including environment access/affinity.
3. Match hard node constraints, if provided.
4. Exclude stale reports and apparently insufficient resource pools.
5. Prefer an eligible node with lower reported pool utilization; use a simple stable tie-break, not a complex optimization algorithm.
6. Ask that executor to admit and start the action.

The executor gateway serializes **local admission**, rechecks local capability/environment readiness, and charges capacity before starting a worker. Pool units are application-level concurrent slots, not OS-enforced CPU/memory isolation. All action execution paths use this gateway; callers do not directly bypass it by starting arbitrary remote tasks.

Reports are hints; admission is authoritative only on the selected node. If capacity changed, the executor rejects admission. The first version does not need queues, preemption, fairness guarantees, or automatic re-placement. No eligible node or a definite rejection produces an explicit non-started outcome. An admission timeout/disconnection is ambiguous and must not be treated as a safe rejection or automatically retried.

There is no cluster-global atomic capacity allocation. Independent local gateways may admit concurrently on different nodes, as intended.

### Environment constraints

Harness describes a native environment reference and its access/serialization needs without importing runtime types. The Agent integration adapter and deployment configuration translate that description into opaque placement/resource requirements. For a node-local Shell session this normally means a particular node/provider instance, not merely a Tool name or a path string.

An adapter can map a mutable-session exclusivity requirement to a node-local resource slot. Neither Harness nor the generic runtime needs to know the other's representation. If a deployment exposes the same external environment on several nodes, cross-node mutual exclusion and synchronization remain the external provider/deployment's responsibility. A shared path does not imply safe concurrent mutation.

Never substitute an unrelated environment when a target is unavailable. Sharing, copying, migrating, and reconstructing environments are outside this architecture.

## 6. Action Interface and Execution Ownership

The following shapes describe contracts, not final Elixir signatures.

### Data vs live handles

An **Action description** contains:

- a protocol/action kind identifying a registered handler contract;
- bounded data payload;
- opaque capability/affinity requirements and resource claims;
- an operation duration budget and bounded correlation metadata.

The coordinator measures its deadline on its own monotonic clock and passes a remaining duration to the executor. Never compare absolute monotonic timestamps from different BEAM nodes as though they share a clock.

Keep the description data-oriented. Do not make anonymous functions, PIDs, monitor refs, HTTP clients, environment handles, or arbitrary user-selected MFA the operation definition. These belong to live runtime context. Explicit handler protocol identifiers avoid assuming that code availability or schema compatibility follows from being in the cluster.

An **ActionRef** identifies a particular submission and its coordinator address/incarnation. A separate **execution handle** identifies an admitted worker at a particular executor endpoint. These handles may contain ephemeral PIDs/refs; they are not persistent identifiers or recovery records. An old handle must not silently resolve to a new execution after restart.

### Small caller interface

- `submit(description, owner_and_event_sink)` returns a local ActionRef after creating an ephemeral coordinator. This acknowledges local submission, not remote admission or execution success.
- `cancel(action_ref)` requests cancellation and acknowledges the local request/already-terminal condition. It does not synchronously promise remote termination.
- `status(action_ref)` returns a live snapshot while that coordinator is retained, or an unavailable/expired result.

The sink is installed with submission, so the submitting Agent need not race a separate subscription against a fast completion. The coordinator monitors its declared owner (the Agent in the AI use case); on observed owner loss it requests executor cleanup and terminates instead of continuing an orphaned plan. A configured bounded terminal-retention interval allows status inspection; it is not history storage. Consumers can also monitor the coordinator so its death does not look like indefinite progress.

Submission itself can fail immediately for invalid descriptions or exhausted coordinator capacity. The coordinator handles later placement and remote admission outcomes asynchronously. Short control-plane interactions use bounded timeouts; no Agent or gateway callback waits for a whole LLM/Tool operation.

### Executor-side handler interface

A registered handler implements a conceptual `run(payload, execution_context)` operation and returns a normalized success/error value. Execution context provides local cancellation/lifetime facilities, bounded event emission, and provider-specific local resources resolved on the executor. It is not transported as part of the Action description.

The gateway starts a local supervised temporary task, using an explicit wrapper entry point and `Task.Supervisor.async_nolink`. The gateway owns its task handles and observes result/`:DOWN` messages. Coordinators monitor the gateway/incarnation; the gateway monitors coordinator ownership. On observed owner loss it attempts to stop owned local work. This is cleanup policy, not partition-proof lifecycle control.

### Progress path and ordering

```text
handler worker -> executor gateway -> action coordinator -> Agent -> UI subscribers
```

The wrapper routes worker progress through the same gateway that forwards admission and completion. Provider callbacks on other processes must be marshalled through the wrapper before emitting; do not assume cross-process arrival order. The gateway supplies action-local event sequence information and sends one ordered logical stream to the coordinator. Sequence information detects gaps/stale events; it does not create reliable delivery.

LLM deltas and Tool progress are optional payloads. Every observer transition distinguishes progress from a final outcome. A surviving coordinator accepts at most one local terminal outcome and ignores subsequent progress/duplicate or stale terminal reports; this is not a distributed exactly-once guarantee.

Bound event size and forwarding volume; batch/coalesce progress where practical. Do not let raw stdout or per-token callbacks become an unconstrained interface. A slow/disconnected UI must not block the Agent loop. Intermediate display may be incomplete; final model output is assembled on the execution side and returned as the authoritative model reply. Tool output is bounded and marked truncated when necessary. A detailed high-throughput backpressure system is not part of the MVP; concrete limits and provider buffering must nevertheless be validated before shipping streaming.

### Outcomes and limits of knowledge

| Observation | Meaning |
| --- | --- |
| Rejected | Definitely not admitted by the selected executor, or no eligible target; no runtime automatic resubmission |
| Succeeded / failed | A definite handler result or observed worker failure while observation remained intact |
| Cancel requested | Non-terminal control state; work might still be running |
| Cancelled | Cancelled before dispatch, or local worker stop observed after cancellation; external effects may remain |
| Timed out | The coordinator's operation budget expired; stop is attempted, but remote stop may be unconfirmed |
| Lost / unknown | Admission/completion became unknowable through disconnection or process loss; side effects may have happened |

Include cause and whether worker termination was observed where relevant. Do not collapse `lost` into a provider error, advertise cancellation acceptance as completion, or infer “not executed” from a timeout.

Cancellation and completion can race. The coordinator's first accepted terminal observation wins locally; a cancellation request does not override an already accepted success. If a result arrives before observed cancellation termination, success can win even after the request was acknowledged. Late messages cannot resume a stopped Agent turn.

No operation-level automatic retry is performed after ambiguous startup, timeout, or loss. Handler integrations must also disable implicit request retries for potentially side-effecting operations unless that provider explicitly defines a safe policy; OTP supervision does not make retries safe.

## 7. Agent and Harness Interaction

### Agent authority and addressing

Starting an Agent explicitly addresses an authority-ready node. That node creates a temporary Agent `GenServer` through its local DynamicSupervisor and Registry and returns an AgentRef containing the authority node, local identity, and live incarnation/address.

The reference, not a cluster-global name, is the routing authority. Commands from another node address that authority endpoint or live PID. Reject a duplicate local identity on that authority; do not promise global identity uniqueness, automatic relocation, leader election, or failover. Starting another Agent elsewhere is not recovery of the old Agent.

The Agent owns in-memory loop state, outstanding action refs, Tool-call correlations, and the current turn. Losing its process/state loses that live Agent. Losing an interface process does not by itself destroy the Agent.

### Harness contracts

Harness supplies:

- an immutable/configured catalogue snapshot of Tool names, input schemas, native invocation mappings, and environment requirements;
- model/provider contracts that normalize requests and final replies, including Tool-call IDs;
- context/prompt construction policies;
- environment descriptions and native Tool/model/environment implementations with backend-neutral progress/cancellation hooks.

A Harness is not necessarily one always-running process and need not live entirely on the authority node. Catalogue/context functions can run there; concrete HTTP, Tool, and environment operations run where the integration adapter invokes them. The adapter/deployment advertises compatible semantic capabilities; Harness does not register itself with the action system. Changing runtime availability may still reject an action after a catalogue snapshot is built.

LLM generation uses an integration-supplied action handler that calls the Harness model interface, not an inline HTTP request inside the Agent loop. Tool calls use the same separation. Harness implements neither the action-handler behaviour nor action description construction. The Agent integration adapter is responsible for routing Agent-created external operations through the generic runtime.

### Loop flow

1. Receive input on the authority and build model context using Harness.
2. Ask the integration adapter to submit model generation; remain responsive to control/subscription messages.
3. Forward optional model deltas as Agent events; use only the final normalized model reply to update authoritative loop state.
4. If the reply requests Tools, validate completed arguments against Harness catalogue schemas; the integration adapter converts native invocations into action descriptions. Never execute partial streamed Tool-call arguments.
5. Dispatch Tool invocations through the adapter according to the loop's ordering policy. Preserve Tool-call IDs, not arrival order, when aggregating outcomes. Resource/environment constraints still apply if independent calls run concurrently.
6. Use the adapter's normalized Tool outcomes and Harness model contracts to build model observations, then request the next model step or conclude the turn.

The MVP need not add alternative planning algorithms or a plugin framework for every loop branch. Model/Tool adapters and environment providers are the actual variations requiring interfaces now. Tool errors are model observations where appropriate; runtime loss must remain distinguishable from ordinary Tool errors.

A user-requested turn stop first prevents the loop from scheduling follow-on work, then requests cancellation for outstanding actions. It stays stopped even if late results arrive. Action-to-turn correlations prevent old completions from advancing a later turn. It does not promise that all external operations have stopped or been undone.

### UI-independent interface

Conceptual Agent operations are start, send input, inspect snapshot, subscribe/unsubscribe, and stop the current turn. Commands acknowledge acceptance or rejection, not completed reasoning. Per-Agent command serialization belongs to the authority, never LiveView assigns.

Subscriptions use monitored sink PIDs. The Agent sends an initial bounded snapshot and subsequent events to the same sink through the same message channel, in that order; a separate command acknowledgement is not the snapshot barrier. Because the authority serializes subscription and state transitions, a healthy connection can join current state without replaying an event log. If disconnected, reconnect via a fresh snapshot; intermediate deltas may be missing. Session/context retention is bounded and in memory.

For the initial fan-out, ordinary process messages are sufficient. Phoenix.PubSub is independently reusable and requires no external broker with its distributed adapter, but is not required in the core dependency graph. LiveView adapts Agent events into UI state; a CLI/IEx caller uses the same Agent interface directly.

## 8. Representative Walkthroughs

### A. Interaction A, authority B, execution C

1. A asks B to start an Agent, choosing B explicitly. B returns an AgentRef; A subscribes.
2. B's Agent obtains Harness catalogue/context data and submits an LLM action to a coordinator on B.
3. B's directory sees C's handler/profile capabilities and available LLM pool. C admits locally and starts its task.
4. C forwards deltas through its gateway to B's coordinator and Agent; B publishes UI-independent Agent events to A.
5. C sends the final normalized model reply. If it contains a Tool call targeting an environment on C, B submits a new action requiring that environment's affinity.
6. C rechecks the environment and Tool pool before running it; the Tool outcome returns to B, which advances the loop. A only presents state.

A second executor D that supports Shell but lacks the required environment is not a candidate. If C is unavailable, the action is rejected/lost as appropriate; it is not silently run against D's filesystem.

### B. Combined roles and generic callers

A node with all roles can place work locally if eligible, but still passes through the same gateway. A non-Agent process can submit an unrelated handler kind using actions/runtime directly without loading the Agent or Harness contract. An executor-only node starts no Agent loop, LLM reasoning scheduler, or Phoenix listener.

### C. Cancellation before/during/racing with execution

- Before dispatch: coordinator records cancellation and does not start work.
- During a connected execution: coordinator requests cancellation; gateway attempts local worker shutdown without blocking unrelated admission/progress processing. Use shutdown signalling, a bounded escalation timer, and the gateway's existing worker monitor, or a helper invoking supervisor-directed termination. Do not transfer an owned Task handle to another process and assume owner-only Task operations work there. Only observed worker stop supports a confirmed local cancellation outcome.
- Completion race: a real result may win before worker stop; cancelling is not a retroactive result rewrite.
- Unreachable executor or ambiguous admission: coordinator reports timeout/loss with unconfirmed stop. It neither resubmits nor claims rollback. If the executor later observes owner loss, it attempts local cleanup independently.

### D. Disconnect and restart

- UI dies: remove its subscription; Agent and outstanding actions can continue.
- Executor/gateway is lost: coordinator reports a lost/failed observation according to available evidence; never retry automatically after ambiguity.
- Authority/Agent dies: interaction receives monitor/unavailable evidence; remote execution cleanup is attempted when ownership loss is observed. No node takes over the loop.
- Node returns: it re-registers its current incarnation/capabilities. New reports do not resurrect old AgentRef or ActionRef handles.
- Late subscriber: receives a fresh bounded Agent snapshot, not durable progress replay.

### E. Human-input actions — explicitly deferred

The user excluded human questions/replies as actions from the current version. The earlier waiting-handler example is withdrawn: do not add a human-request handler, pending-request resource pool, action-input operation, reply-routing protocol, or special pending-question state for this purpose. The action caller interface remains submit/cancel/status with output events and terminal outcomes.

Ordinary user messages use the Agent interaction interface; they do not complete a waiting action. Human-input actions may be revisited with a future callback/completion system. No such callback system or human-request execution topology is specified or reserved by this draft. The reason for deferral is to avoid retaining an execution handler/node merely to wait for a human reply.

## 9. Extension Space, Not Future Subsystems

Keep only the following structural affordances:

- data-oriented action descriptions separate from live execution context;
- a clear submission/control seam and explicit action/execution identity;
- normalized lifecycle events/outcomes with one local state-transition owner;
- generic handler/provider interfaces instead of hard-coded Tool or model calls;
- explicit ownership of environment resources and authority state.

These reduce accidental coupling for later work. Do not add storage adapters with no implementation need, write-ahead logs, outboxes, checkpoints, review states, recovery coordinators, durable sequence numbers, or consensus interfaces now. Future persistence/review may require contract changes; this draft does not promise schema stability or transparent recovery.

## 10. Alternatives and Trade-offs

| Alternative | Reason not chosen for MVP |
| --- | --- |
| One application containing Phoenix, loop, scheduling, and Tools | Couples independent callers and deployments |
| A separate application for every internal responsibility/provider | Adds packaging/interfaces without demonstrated independent value |
| Raw RPC or Task.Supervisor as the entire public action interface | Leaves placement, capacity, identity, events, and cancellation semantics scattered across callers |
| Central singleton scheduler | Adds a new authority/bottleneck without a current need; coordinators plus local admission suffice |
| `:global`, a distributed Registry, or automatic leader election for Agents | Solves global uniqueness/failover that is not required; explicit authority references are simpler |
| Phoenix dependencies in core for notifications | Unnecessary for basic process subscriptions; Phoenix.PubSub can be adopted independently later if needed |
| Oban, Redis, external queues, or a database | Conflicts with current operational constraints or solves deferred durability |
| An Effect algebra/workflow DSL | The current need is concrete data-described asynchronous actions, not a new programming model |
| Restarting workers/Agents from initial arguments | Risks duplicate side effects or loss of conversational meaning; supervision is not recovery |

Trade-offs accepted by the proposal: reports may be stale, actions may be rejected despite theoretical capacity elsewhere, progress may be incomplete, observation can become unknown, and an Agent cannot survive authority loss. These limitations match the current scope rather than being hidden behind stronger terminology.

## 11. Review and Validation

See `implement.md` for architecture review checks and a separately gated future implementation sequence. Before accepting this draft, verify:

- Every requirement R1–R12 and acceptance criterion AC1–AC10 has a section/flow above.
- Dependency direction is acyclic and runtime compiles without Agent/Harness/Phoenix.
- Each stateful process has one owner and no restart implies business replay.
- Claims about cancellation, timeouts, events, roles, and resources do not exceed the available evidence.
- No proposed interface assumes synchronized environments, global resource locks, or a reliable event log.

No application code or executable Elixir interface is included in this task. Names, exact signatures, batching limits, timers, and provider choices will be fixed through implementation-specific tasks only after separate authorization.
