# Durable Runtime Architecture and Core Contracts

## Goal

Design a generic Elixir/OTP durable computation runtime before product implementation, and establish a maintained specification library that guides engineering across the project. Validate its boundaries against an agent runtime built on composable capabilities and durable effects.

The outcome is a reviewed architecture and a discoverable, versioned target-contract library for subsequent engineering work.

## Background

- The user approved creating this planning task on 2026-10-07.
- The project uses Elixir throughout and should make deliberate use of OTP and BEAM distribution.
- The repository contains project setup and Trellis scaffolding, but no Elixir runtime implementation or Mix project. Existing spec indexes contain unfilled templates.
- `README.md` names Beamlet-lib, Beamlet-core, Beamlet-effect, Beamlet-durable, Cordex, Beamlet-agent, and client applications. These are existing concepts, not an approved module decomposition or recovery contract.

## Requirements

### R1. Generic Runtime

The foundation persists effects, resolves them to capabilities, and executes them across a BEAM cluster. Its contracts must be usable outside the agent domain, without agent-specific mechanisms.

### R2. Agent Integration

Agent business logic does not know what an Effect is. The architecture must explain how this separation works with the explicit state-progression contract in R8.

Agent actions, including LLM requests, tool calls, model selection, effort selection, and subagent creation, participate in durable execution. Their domain meanings belong to the agent layer.

### R3. Distributed Execution

A user interacts with an agent from a supported endpoint in the cluster. An effect can execute on another BEAM node with the relevant resources, with its outcome returned to the computation on the originating node. Specify resource resolution, execution responsibility, correlation, and recovery when the originating node is unavailable.

### R4. Durable Lifecycle

Account for agent distribution to nodes, fork, review, export, suspension, and resumption. Distinguish computation lifecycle operations from effect execution, and generic contracts from agent-specific semantics.

Fork boundary and historical reuse semantics are defined in R13, review/approval boundaries in R14, portable export in R17, and suspension/resumption in R19. Define code/configuration compatibility in the technical design.

### R5. Supported Surfaces

The intended surfaces are CLI (`fuelen/owl`), TUI (`agentjido/term_ui`), Desktop (`elixir-desktop`), Web (Phoenix Framework), Android (Mob Framework), and Server Node. Explain their relationship to the agent/runtime and platform constraints without assuming identical runtime roles. Building these surfaces is outside this task.

### R6. Failure Guarantees

Define durability, acknowledgement, execution attempts, retries, and outcomes under process crashes, node loss, and network partitions. Describe duplicates and uncertain external outcomes without claiming exactly-once execution. Persisting a request must not be presented as proof of execution completion or computation recovery.

### R7. Maintained Specs

Use the existing Trellis specification system. Establish a discoverable index, consistent vocabulary, core contracts and invariants, architecture decisions with rationale, and observable acceptance scenarios. Distinguish approved decisions, proposals, and deferred work. Write repository documents in English.

### R8. Explicit State Progression

The user selected explicit state progression on 2026-10-07 (Q1, option 1). Business logic handles application state and inputs; a generic runtime layer saves progress and arranges capability calls. Recovery continues from a persisted boundary rather than reconstructing arbitrary sequential Elixir code through whole-program replay.

Applications must explicitly represent computation stages. This choice does not select a storage engine, checkpoint/journal format, public callback signature, or precise atomic persistence boundary. It also does not exclude using a journal to reconstruct explicit application state.

### R9. Runtime Capability Composition

The user selected runtime dynamic composition on 2026-10-07 (Q2, option 1). Capabilities expose stable callable contracts. Different scopes can select and isolate capabilities, and implementations can be replaced or unloaded during operation. Declared dependencies affect capability availability. Agent business logic depends on the stable contract.

The architecture must define scope boundaries, lifecycle ownership, and the treatment of pending Effects when capability availability or implementations change. This choice does not select a Cordis API port, exact provider-binding time, remote invocation protocol, authorization scheme, or dependency restart policy. Resource cleanup and unregistering capabilities do not imply undo of external operations.

### R10. Designated Storage Authorities and Cluster Durability

The user selected cluster-level durability on 2026-10-07 (Q3, option 1), and specified that persistence need not be maintained on every cluster node. Users can designate a subset of nodes as the authoritative storage nodes.

Under a documented authority-replica configuration sufficient to tolerate one storage-node loss, acknowledged computation progress and Effect records must survive permanent loss of one authority node and its disk, and support reconstruction on another node. During a network partition, the same computation history may advance only through a side that retains authoritative write permission. Insufficient authority availability must not produce a false durable acknowledgement.

Authoritative persistence, computation hosting, Effect execution, and user interaction are logical responsibilities. A node may combine responsibilities; non-authority nodes are not required to maintain durable replicas. The architecture must distinguish persistent runtime records from node-local provider resources, and identify the required deployment conditions for the promised guarantee.

This decision does not select a storage engine, consensus implementation, number of replicas, or authority membership-change protocol. It does not imply exactly-once external execution.

### R11. Recovery According to Declared Operation Semantics

The user selected recovery according to operation declarations on 2026-10-07 (Q6, option 1). After uncertain execution, operations declared idempotent, protected by applicable deduplication, or explicitly allowed to repeat may be retried according to their policy. Other operations retain an unknown outcome until the capability or application explicitly determines the next action.

Unknown outcomes must be distinguishable from confirmed failure or confirmed non-execution. A timeout or lost node connection alone must not be treated as proof of non-execution. The architecture must explain how retry declarations remain valid across recovery and provider changes, including the scope and limits of any deduplication guarantee.

The resolution mechanism must be generic and expose appropriate business-level inputs to effect-unaware applications. This decision does not mandate a human approval UI, an agent-specific recovery path, compensation, or an exactly-once claim. Retry limits, late outcomes, and concrete resolution commands remain technical design work.

### R12. Immutable Intent and Late Provider Resolution

The user selected immutable intent with execution-time resource resolution on 2026-10-07 (Q2 provider-binding question, option 1). A persisted Effect retains its operation contract, arguments, relevant configuration, and resource constraints. Provider/node selection happens when execution is attempted, and a compatible replacement implementation may handle queued work.

Later changes to scope configuration must not silently alter an existing request's meaning. In the agent example, a previously recorded LLM request retains its recorded model and effort even if the agent's subsequent settings change. This is an example of a generic immutable-input rule, not a model-specific mechanism in the foundation.

Re-resolution for retry must preserve the repeatability or deduplication conditions relied on in R11. Matching an operation name alone does not establish semantic compatibility. The design must state how constraints are represented and how unavailable or incompatible providers are reported without substituting different request semantics.

### R13. Fork at Stable Committed Boundaries

The user selected stable-boundary fork on 2026-10-07 (Q4 fork-boundary question, option 1). Fork creates an independently advancing branch from a committed state boundary with no unresolved Effects at that boundary. It inherits that point's application state, historical prefix, and completed outcomes, without executing those historical operations again. Subsequent work has independent branch/Effect identities.

The source branch continues independently. Outstanding work at its current head does not prevent selecting an earlier stable boundary; entries after the selected point are not inherited as the new branch's history. Fork does not copy running attempts, restore an earlier external environment, or reverse external operations.

Forking an in-flight boundary with pending, running, or unknown Effects is outside the initial contract. The design must define how stable boundaries are identified and how a fork's lineage and inherited history are represented and exported.

### R14. Historical Review and External Pre-execution Extensions

The user selected history/state review on 2026-10-07 (Q4 review question, option 1). Review exposes computation state, Effect requests/outcomes, execution attempts, and branch differences for inspection and audit.

The user additionally specified that pre-execution review should be implemented externally, for example by composing functionality between Effect creation and execution. Approval-specific states, approve/reject workflows, and human-review semantics must not be predefined features of the Effect/Durable module.

The architecture must expose a clear composition boundary after Effect creation and before external execution so an external module can participate in that path. A passive after-the-fact observer is insufficient to establish a pre-execution control boundary. Define this seam using the general creation/execution and capability composition contracts, without inventing a built-in approval subsystem.

### R15. Configurable Roles on BEAM-hosting Surfaces

The user selected configurable full-node roles on 2026-10-07 (Q5, option 1). CLI, TUI, Desktop, and Android surfaces with a BEAM host can run Agent computations, execute locally available capabilities, or provide interaction only. Storage-authority participation is independently configured under R10, and a node may combine roles.

The Web browser interacts through a Phoenix BEAM node, whose computation/execution/storage roles follow the same configuration rules. UI connection and view-process lifecycles must be distinguished from durable computation ownership and lifetime.

The architecture must make endpoint disconnection, process loss, and mobile OS lifecycle part of the general failure model. A node without access to a valid authority write path cannot acknowledge new cluster-durable progress. Previously admitted external operations may still complete; their outcomes follow R11 rather than an assumption that disconnection cancelled execution.

Platform packaging, supported OTP/Elixir versions, mobile lifecycle behavior, and real-device networking remain technical validation work; no platform implementation is included in this architecture task.

### R16. Operator-managed Trusted Cluster

The user selected an operator-managed trusted BEAM cluster on 2026-10-07 (Q2 trust-boundary question, option 1). Users or administrators control membership; admitted cluster members and the code they run are trusted. External clients access authenticated, authorized, validated application interfaces rather than becoming cluster members merely by using a frontend.

The architecture must distinguish scope-based capability composition/selection from isolation against malicious node code. Define authorization boundaries for externally submitted inputs, lifecycle commands, resource use, and inspection/export, while retaining the trusted-member premise of the internal cluster protocol.

The initial contract does not include third-party-controlled untrusted compute/execution nodes or containment of a malicious admitted member. Such execution domains would require independent isolation and a bounded protocol as separate work.

### R17. Portable Computation Archives

The user selected portable computation archives on 2026-10-07 (Q4 export question, option 1). Export a stable committed boundary with the necessary application state, historical prefix/completed outcomes, lineage, and contract/code/schema version information. A target environment with compatible code and required resources can import it as a new branch and continue without repeating completed historical operations.

Import must validate the archive and its compatibility/resource requirements before allowing execution. The architecture must define branch identity, inherited history, resource-reference resolution, and explicit failure behavior for missing code or resources. A portable archive contains logical computation data; it does not promise to reproduce a live process, copy provider credentials, or restore an earlier external environment.

### R18. Constrained ETF Representation

The user explicitly permits storing an appropriate subset of Erlang External Term Format. Define a versioned, data-only ETF profile for persisted/archived state and records, using OTP's term encoding rather than an invented serializer.

The profile must identify supported data terms and schema/atom rules, replace runtime/resource handles with stable logical references, and exclude process-local identifiers, ports, references, executable functions/closures, and instance-local ETF encoding from portable state. It must define validation and resource limits at archive import boundaries. The `safe` decode option alone does not establish application validity or compatibility.

Envelope/profile rules are technical design, subject to the final architecture review. This encoding choice does not replace authoritative persistence or change the cluster durability guarantee in R10.

### R19. Durable Suspension with In-flight Outcome Retention

The user selected stopping new progress while allowing admitted work to finish on 2026-10-07 (Q4 suspension question, option 1). Once suspension is authoritatively committed, the computation must not advance state or grant new Effect execution attempts. Already admitted attempts may finish, and their outcomes remain recordable in the authoritative history while the computation is suspended.

Resume enables the normal state/input processing path to consume recorded outcomes and apply R11 to remaining uncertainty. It must not execute an already completed historical operation again merely because the computation was suspended or its hosting process restarted.

The architecture must define the ordering of suspension, step commits, and attempt admission, including the race where permission was granted before suspension but execution starts later. Suspension does not assert cancellation or reverse external work; a best-effort interruption feature is outside the initial contract.

## Acceptance Criteria

- [x] AC1: Boundaries and dependency direction are documented across the generic runtime, agent, and surfaces, including runtime capability composition; the generic foundation has no agent-specific dependency. (R1, R2, R5, R9)
- [x] AC2: A computation walkthrough demonstrates explicit state progression and states what is persisted and how progress resumes after a process/node restart, including the effect-unaware authoring contract. (R1, R2, R4, R6, R8)
- [x] AC3: An action walkthrough covers user endpoint, agent, authoritative durable recording, capability resolution, remote execution, and outcome consumption, including loss of a computation-hosting node without local durable replicas. (R2, R3, R5, R6, R10)
- [x] AC4: Failure scenarios cover crashes before dispatch, after an external operation but before outcome recording, and after recording but before delivery; each states allowed observations and recovery under declared operation semantics. (R3, R6, R11)
- [x] AC5: Lifecycle scenarios define stable-boundary fork, review, portable export/import, suspension, resumption, and node distribution, including historical/pending effects and code/configuration changes. (R2, R4, R6, R13, R17, R18)
- [x] AC6: A non-agent example exercises the generic contracts without LLM, tool, conversation, or subagent concepts. (R1)
- [x] AC7: Specs have working local references, an index, requirement-to-contract/scenario traceability, and no unresolved decision presented as an approved guarantee. (R7)
- [x] AC8: The latest planning summary is reviewed with the user before leaving planning.
- [x] AC9: Composition scenarios demonstrate scope isolation, unavailable dependencies, capability replacement/unload, and their observable effects on pending and running work. (R2, R3, R6, R9)
- [x] AC10: A deployment/failure scenario identifies the user-designated authority subset, explains the configuration required to tolerate one authority node/disk loss, reconstructs acknowledged state after that loss, and forbids conflicting authoritative advancement during partitions. It includes computation/execution nodes without durable replicas. (R3, R6, R10)
- [x] AC11: Recovery scenarios contrast a repeatable operation that retries under its declared policy with an operation lacking permission to repeat that remains unknown. They define explicit resolution and demonstrate that provider changes cannot silently invalidate the relied-on retry/deduplication guarantee. (R2, R6, R9, R11)
- [x] AC12: A queued-request scenario replaces a provider and changes scope configuration before execution; the request retains its saved intent and executes only on a compatible eligible provider. Include no matching provider and retry across a changed deduplication domain. (R2, R3, R9, R11, R12)
- [x] AC13: A source computation with current outstanding work forks from an earlier stable boundary. The new branch inherits only the selected prefix, consumes completed historical outcomes without repeating operations, advances with independent Effect identities, and leaves source execution intact. A request to fork an unresolved boundary is rejected with an explicit reason. (R4, R8, R11, R13)
- [x] AC14: Inspection scenarios expose state, requests/outcomes, attempts, and branch differences. An external-extension walkthrough identifies where pre-execution review can be composed after Effect creation and before external execution, while the Effect/Durable contract contains no approval-specific state machine or workflow. (R1, R4, R9, R14)
- [x] AC15: A deployment matrix covers all requested surfaces, configurable computation/execution/interaction roles on BEAM hosts, independent authority participation, and browser-to-Phoenix interaction. A disconnection scenario distinguishes UI reconnection, computation takeover, authority write availability, and outcomes of previously admitted work. (R3, R5, R6, R10, R11, R15)
- [x] AC16: The trust model identifies operator-admitted nodes and authenticated external interfaces, and maps authorization checks to input/control, resource, and inspection/export boundaries. It makes no claim that a capability Scope contains malicious cluster code or that the authority protocol tolerates Byzantine members. (R1, R9, R10, R14, R16)
- [x] AC17: A stable-boundary archive imports into a compatible target authority domain as a new branch, preserves history/lineage, and resumes only subsequent work. Missing code/schema compatibility or required resources blocks activation with an explicit outcome rather than executing historical work again. (R4, R12, R13, R16, R17)
- [x] AC18: The ETF profile provides supported-term examples and rejection/compatibility scenarios for runtime handles, functions, unknown schema/atoms, malformed/trailing data, and oversized input. It distinguishes encoding, safe decoding, application validation, and durable acknowledgement. (R6, R10, R16, R17, R18)
- [x] AC19: A suspension race orders a step/attempt grant against the committed suspension boundary, rejects grants/advancement after it, records completion of previously admitted work while suspended, survives host restart, and resumes by consuming recorded outcomes. It makes no claim of retroactive external cancellation. (R4, R6, R8, R10, R11, R19)

## Out of Scope

- Product runtime, agent, frontend, or deployment implementation in this architecture task.
- Saga compensation, undo, or reversal of already executed external actions.
- Exactly-once execution claims and agent-specific magic in the foundational library.
- Filling coding-guideline templates with invented implementation conventions.
- Forking an in-flight boundary or inheriting its running/pending/unknown Effects in the initial contract.
- Built-in pre-execution approval states and workflows in the Effect/Durable module. External pre-execution composition is supported by the architecture, but implementing an approval product is outside this task.
- Untrusted third-party compute/execution domains and malicious-member isolation in the initial cluster contract.
- Best-effort interruption of admitted external work as part of the initial suspension contract.

## Technical Validation and Planning Artifacts

User-owned requirements have converged. The design defines submission/acknowledgement and fencing, public contracts, codec/version compatibility, logical boundaries and validation gates without weakening confirmed behavior. The proposed Ra storage target is gated against its actual version, project toolchain and persistence semantics before any implementation claim.

`design.md` records the reviewable architecture proposal; `implement.md` plans producing and checking the specification library. Approval of this documentation task does not implicitly authorize product implementation. The task remains in planning until the latest summary is reviewed.

Initial evidence is recorded in `research/initial-evidence.md`.

## Documentation Acceptance Evidence

Published architecture-v1 contains nine linked documents, R1-R19/S1-S19 coverage, concrete target signatures/payloads/error matrices, required future assertions, and wrong/correct cases. Documentation checks verified links/anchors, fences, formatting and manifest paths. Coherence/failure review checked continuation and branch identity, atomic state/input/Effect commits, stale host versus original attempt reporting, unknown/late outcomes, controller bypass, suspension and archive activation. No runtime code, dependencies or runtime tests were created/executed; those gates remain explicit.
