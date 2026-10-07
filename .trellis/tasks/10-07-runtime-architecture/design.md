# Durable Runtime Architecture and Core Contracts

Status: accepted target architecture; final planning review approved on 2026-10-07.
Date: 2026-10-07.
Scope: architecture and a maintained spec library; no product implementation.
Requirements: [PRD](./prd.md). Vocabulary: [glossary](./GLOSSARY.md).
Evidence: [initial research](./research/initial-evidence.md) and [authority storage](./research/authority-storage.md).

## 1. Architectural Shape

Business code describes capability invocations and handles ordinary replies. The generic explicit-state runtime persists immutable Effects, coordinates attempts, and delivers committed outcomes as application inputs.

~~~mermaid
flowchart TD
    UI["CLI / TUI / Desktop / Android / Web"]
    AG["Agent state + capability facades"]
    RUN["Generic computation host"]
    AUTH["Designated storage authorities"]
    DISP["Configured execution controller"]
    CAP["Scoped capability resolution"]
    EXEC["Execution node + local resources"]
    UI --> AG
    AG --> RUN
    RUN -->|"input + state + new Effects"| AUTH
    AUTH -->|"committed pending work"| DISP
    DISP --> CAP
    CAP -->|"eligible provider"| DISP
    DISP -->|"request attempt grant"| AUTH
    AUTH -->|"committed permission"| EXEC
    EXEC -->|"observations + outcome"| AUTH
    AUTH -->|"durable capability reply"| RUN
    RUN --> AG
~~~

Boxes are logical responsibilities, not one process/node each. Nodes may combine roles; authorities need not host Agent definitions or all providers. A view/session connection is a client of a Run, not its identity or durable lifetime.

## 2. Logical Modules and Dependencies

Refine the README concepts through namespaces before creating separate OTP applications for every abstraction.

| Group | Owns | Depends on |
|---|---|---|
| Beamlet-core | Definition/Run/Invocation/Reply references and portable data contracts | OTP/Elixir |
| Cordex | Generic scoped services, dependencies, provider generations and resource lifecycle | OTP/Elixir; no Agent/durable computation logic |
| Beamlet-effect | Immutable intent, attempt/outcome contracts, eligibility and one provider invocation | Core and narrow Cordex integration |
| Beamlet-durable | Authority records/commands, computation hosts, dispatch/workers, control and archives | Core, Effect, Cordex integration, selected storage |
| Beamlet-lib | Public generic facade and role-aware bootstrap | Generic groups above |
| Beamlet-agent | Agent definitions and LLM/tool/settings/subagent facades/providers | Public generic interfaces |
| Surfaces | Interaction, projections, authenticated adapters and role configuration | Agent and public generic controls |

A Durable worker invokes Effect execution and submits the result to authority storage. Effect execution does not call back into Durable; no cyclic dependency or abstract result-sink framework is needed.

Cordex retains live contexts locally; Durable retains logical descriptors. Node-local resources are reconstructed from those descriptors. Cordis registration effects, Ra scheduling effects, and Beamlet durable Effects are distinct.

Full Cordis API compatibility, a new event-bus framework, and hot-loader tooling are not implied by the selected Scope/lifecycle contract.

## 3. Core Abstractions

| Contract | Minimum data | Invariant |
|---|---|---|
| DefinitionRef | Definition ID, logic version, state/input schema versions | Resolve to registered compatible trusted code. |
| RunRef | Authority-domain and Run identities | Survives host/process changes. |
| Run snapshot | Definition, state, state revision, input cursor, progress directive, Scope descriptor, mode | Portable application data. |
| Invocation | Operation contract/version, arguments, reply key, resource constraints | Business-facing declaration; builder performs no I/O. |
| Effect intent | EffectRef, origin Run/step/reply key, normalized Invocation, effective configuration, retry declaration | Immutable after creation. |
| Attempt | AttemptRef, EffectRef, provider/resource/generation, admission evidence | Permission is not proof of execution. |
| Outcome | Observation, canonical result or unknown evidence, provenance | Transport loss is not non-execution evidence. |
| Scope descriptor | ID/version, bindings/configuration, parent/isolation relationships | No live handle or private credential. |
| BoundaryRef | Run/state revision, history cut, recorded stability | Historical eligibility belongs to that point. |
| Archive | Profile/versions, origin/lineage, stable snapshot, necessary history/data | Validate before new-branch activation. |

Public references are opaque data, not PIDs or storage-leader handles.

Runtime control mode is active or suspended, independent of open/finished/failed Run lifetime and the application's own phase. The progress directive is ready, waiting, or finished.

Effect lifecycle is pending, executing, unknown, outcome_recorded, or consumed. Executing means an attempt has been admitted, not proof of physical execution start. Attempt lifecycle is admitted, unknown, or observation_recorded; the observation separately identifies a known result or established non-execution. This keeps external evidence distinct from scheduler state.

Effect identity stays stable across retries; proposed allocation is Run identity + committed step sequence + invocation ordinal. Attempts add an authority-allocated ordinal. Ownership epoch is not logical Effect identity.

Moving a host retains Run/Effect identity. Fork/import assigns new Run identity for future work. Inherited history keeps provenance and is read-only.

## 4. Computation Authoring

Proposed transition vocabulary:

~~~text
step(state, application_input) ->
  {:continue, new_state}
  | {:wait, new_state}
  | {:invoke, new_state, [Invocation]}
  | {:finish, new_state, result}
~~~

This is contract notation, not an implemented API. Capability facades build Invocation data; providers execute operations. Replies contain the application's reply key/result, not Effect/Attempt/store records.

Continue commits a ready progress directive and a deduplicated data-only continuation input keyed by Run/state revision. Wait awaits ordinary inputs; Invoke creates a nonempty call set and awaits replies; Finish requires the relevant Effect completions to be settled. Obsolete internal continuation inputs are dispositioned without executing a transition against a different state revision.

Finish closes input admission and retains explicit not-processed dispositions for any remaining external inputs; an acceptance receipt never becomes an implicit processing-success claim. Unsettled Effect completions cannot be silently discarded to satisfy Finish.

The continuation directive makes a stable checkpoint between operations resumable without storing a closure or copying an executable source queue. Resume uses an existing committed continuation; fork/import reconstructs a fresh branch-local continuation from the saved ready directive. A finished checkpoint remains finished and does not silently restart old work.

Transitions avoid unrecorded I/O, mailbox reads, clock/random decisions and live handles. Obtain such observations through capabilities. A transition can be evaluated again if its uncommitted proposal is lost.

Run the definition on a computation host against committed state/input. Do not evaluate user callbacks inside a transaction/replicated machine. Authority atomically validates and commits the result.

### Agent walkthrough

User input is durably accepted; Agent state proposes an LLM Invocation using recorded settings. Runtime persists/resolves/executes it. A committed capability reply drives the next state transition, which may propose tool, settings or subagent invocations.

Settings are ordinary invocations whose replies update Agent state. A subagent provider uses generic Run creation with a stable creation key and returns a Run reference. The foundation contains no model/effort/subagent-specific coordinator.

Agent definitions/facades depend on Invocation/Reply contracts, not Effect/Durable namespaces. Generic infrastructure can inspect those records without exposing them to Agent business logic.

### Non-Agent walkthrough

Read an immutable object through a provider on node A, compute its digest from the recorded reply, then commit a ready checkpoint before invoking a content-addressed write on node B. The write declares retry/deduplication semantics. Host takeover uses the committed result/progress or pending write; an archive of the stable ready checkpoint resumes with a new branch-local write. No Agent concept is involved.

## 5. Authority Protocol

Use closed data commands for Run creation, input append, conditional step commit, attempt admission, outcome/resolution, ownership/control, and stable fork/import. Do not persist arbitrary update functions.

Logical records include snapshots/revisions, ordered inbox/consumption, Effect intents/pending index, attempts/results/recovery evidence, ownership/control epochs, Scope descriptors, lineage and command receipts. They need not be separate databases.

| Command | Conditions | Atomic result |
|---|---|---|
| Accept input | Run accepts it; stable key; valid data | Ordered inbox entry and receipt. |
| Commit step | Active mode/current epoch; expected state revision/input cursor | State/progress + consumed input + new Effects or continuation + history/boundary. |
| Admit attempt | Active mode; eligible Effect/provider; valid orchestration/retry permission | Attempt and binding recorded before external execution. |
| Record outcome | Recognized attempt and matching intent | Observation; when justified, canonical outcome + one reply entry. |
| Suspend/resume | Authorized conditional command | Control change and fencing of obsolete permissions. |
| Fork/import | Valid stable boundary/archive and compatible target | New Run, state/prefix/lineage and receipt. |

State and new Effects share one commit. Neither advanced state with lost calls nor calls detached from their state transition are allowed.

A receipt means authoritative commit, not external success. Timeout is ambiguous: retry the same key/original logical payload or query its receipt; reject a changed request under an existing key. Compare normalized logical data rather than assume universal canonical ETF bytes.

Consistent reads govern recovery, boundary selection and export. Cached UI views expose their revision and cannot authorize progress.

### Ownership and discovery

A supervised host caches state, while durable ownership/control epochs fence obsolete step/grant proposals after takeover or suspension.

Outcomes use their original attempt authorization, not the current host epoch. Old legitimate workers may report after a pause/takeover; stale hosts cannot advance state.

Registry/ETS and pg-style membership locate processes/providers. Discovery is not authoritative ownership or evidence that an external operation stopped. Correctness does not rely on synchronized clocks or a perfect failure detector.

### Storage target

Propose one Ra-backed authority group with three persistent voting nodes for one-node-loss tolerance. Expose no Ra leader/index internals in generic public contracts; do not build multiple backend adapters initially.

[Storage research](./research/authority-storage.md) records native alternatives and the required OTP 29/version, disk/quorum, fencing and recovery gate. Ra is not installed or validated. A failed spike reopens implementation choice, not R10.

Public histories/checkpoints remain application records across backend compaction. A backend WAL is not the public computation journal or archive.

## 6. Resolution and Outcomes

Resolve providers using saved contracts, Scope/configuration meaning and resource constraints. An equal operation name/path/provider label alone is insufficient. Current eligibility can deny admission without rewriting intent.

Replacement changes location only within that contract. Deduplicated retry preserves the original admitted binding's deduplication domain and valid retention conditions. Expiry does not silently become permission to repeat.

Live sockets, credentials, devices and service PIDs remain provider-local resources.

After admission, the worker verifies the recorded provider generation and resource constraints locally before invocation. A vanished/replaced provider cannot be substituted inside that attempt. Rejection before invocation can establish non-execution; loss after possible invocation follows the unknown-outcome rules.

~~~text
created/pending -> admitted attempt -> recorded observation
known canonical result -> durable reply -> consumed state transition
uncertain execution -> unknown -> declared recovery or explicit resolution
~~~

Dispatch/grant does not prove execution start. Exceptions/timeouts remain uncertain unless the provider can establish a result or non-execution.

One canonical terminal reply is committed per Effect. Duplicates do not enqueue another reply. Conflicting/late evidence remains inspectable and cannot rewrite consumed history. A later attempt's failure alone cannot settle an earlier possible execution.

An uncertainty notice can be a durable ordinary capability reply/input without being a canonical terminal completion. Consuming that notice does not settle the Effect or make the boundary stable. An application/provider can resolve its opaque invocation reference with evidence or a recorded explicit repeat decision through generic control interfaces; it does not need an Effect record in business code. The immutable intent and previous evidence remain unchanged.

Retries after possible execution require idempotence, applicable deduplication or explicit permission to repeat. Confirmed non-execution can retry under policy. Retry exhaustion does not convert unknown into definite non-execution.

Workers report to authorities, independent of the original host PID. Durable input cursors and conditional commits prevent redelivery from advancing state twice.

| Fault boundary | Required recovery |
|---|---|
| Host loss before step commit | Re-evaluate committed state/input; no uncommitted call executed. |
| Committed Effect, lost dispatch notification | Reconcile authoritative pending work; notification is a hint. |
| Admitted attempt, missing worker | Retain uncertainty unless non-execution is established. |
| External success, lost outcome recording | Retain admission/unknown evidence; apply declared recovery. |
| Recorded outcome, lost reply delivery | Consume the recorded reply under the normal cursor/commit gate. |
| Stale host after takeover | Reject old epoch/revision; admitted worker evidence remains recordable. |
| Isolated authority minority | No new authoritative progress/grants or false receipt; admitted work may finish. |
| Conflicting late completion | Audit it without overwriting canonical consumed history. |

## 7. External Pre-execution Composition

The execution path is a real seam: commit pending intent, let the configured controller select/resolve ready work, request authority admission, then execute and record.

Default orchestration is automatic. An application may supply a scoped controller/service that coordinates review before admission. The automatic path must not simultaneously bypass it.

All controllers use the same invariant gate. Durable stores generic pending/attempt/control facts, with no awaiting_approval state or approve/reject workflow. Review UI, persistence and decisions belong to the external module. No middleware DSL is required.

A new gate or suspension cannot retrospectively revoke already granted execution.

## 8. Lifecycle and Compatibility

### Suspend/resume

Committed suspension orders against steps/grants and prevents new ones. Admitted work may execute/finish and record outcomes while suspended.

Resume obtains fresh advancement permission, loads committed state/input and consumes retained replies. It never repeats completed work merely due to suspension or host restart.

A suspended head may still have unsettled work. It is not automatically a forkable boundary.

### Fork

Proposed precise stable rule: no pending/executing/unknown Effects or unconsumed canonical replies in the selected snapshot's causal work. Record the marker/history cut at that point; later completion does not retroactively make an in-flight snapshot stable. This is stability of canonical computation state, not proof of physical quiescence of external resources or every older attempt.

A new Run inherits state/completed prefix while the source continues. Source-owned pending input queues and running attempts are not cloned or activated. No prefix is re-executed.

New branches are initially suspended. A ready progress directive produces a fresh branch-local continuation on activation; waiting requires new input; finished stays terminal. The source's pending external-input queue is not copied.

Fork acts on one Run. Child Runs/resources remain references; recursive application-graph copying is composed explicitly from generic operations.

### Export/import

Archive the same stable-boundary class: necessary state/history/results, Scope descriptors, lineage and definition/schema/profile/contracts.

Validate the archive and code/resource bindings before activating a new target branch. Import registers it initially suspended; activation follows an explicit resume under those validated conditions. Missing/incompatible requirements produce an explicit non-executing outcome. No implicit source deletion, old queue activation, code installation, credential copy or external-resource restoration occurs.

Required payload data is included or available through a verified durable reference. An unresolved reference is not successful activation. Applications can explicitly package multiple related Run archives.

### Versioning

Resume/import uses recorded definition, state/input schema and operation contracts. Initially require registered matching versions or a declared compatible target; otherwise block activation.

No implicit migration/reinterpretation after hot code changes. Future explicit versioned migration preserves original state/history. OTP code-change support is not the durable compatibility contract.

## 9. Constrained ETF

Propose standard, uncompressed ETF for bounded data, using OTP encoders/decoders.

Support integers/floats, binaries/bitstrings, proper lists, tuples, maps and schema-approved existing atoms. Registered structs are data maps with approved tags. External names use binaries; importing data never creates arbitrary atoms or loads code.

Recursively exclude PID/port/reference/function/closure values and instance-local ETF. Use stable logical IDs/code references.

The envelope identifies format/profile, definition/schema/contracts, origin/lineage, boundary state/history and resource requirements. Apply byte bounds before decoding; reject compressed and top-level instance-local wrappers; use safe + used with full-consumption checks, then validate the tree/application schema. Normalize accepted data through the standard profile encoder before persistence/export; runtime-instance-specific wire representations are not retained as portable state. No complete custom ETF tag parser is introduced. Decode in a supervised worker with timeout/heap guardrails, without invoking archive-supplied code.

Byte, depth/node-count, time and heap budgets are explicit positive profile configuration. Worker heap/time settings are guardrails, not a process sandbox or a claim of hard RSS isolation. Codec measurements/fault checks must establish supported resource bounds before runtime release. Reject unbounded profiles/oversized values; never silently truncate outcomes. Providers honor declared result limits or return verified references. A recording failure remains visible uncertainty.

Digests/checksums verify recorded bytes with their profile/version, not provenance or universal canonical encoding. Keep authorization/provenance validation separate.

[OTP term decoding](https://www.erlang.org/doc/apps/erts/erlang.html#binary_to_term/2) distinguishes safe decoding from application validation; deterministic encoding is limited to an OTP major release. Replicated command application must avoid replica-dependent re-encoding.

## 10. OTP/BEAM and Surfaces

Use processes for concurrency/lifetime/failure domains: role-aware supervision, designated authority members, registered supervised computation hosts, supervised dispatch/workers and local providers. Reconcile committed work after restart using versioned data messages between admitted nodes.

Snapshots/inbox/Effects outlive processes. Recovery reconstructs actors rather than a process stack or durable mailbox.

One authority group/retained-history machine is an initial scalability ceiling. Measure before sharding, optimized placement, multiple adapters or a blob framework. History retention and archive limits are visible; no silent history/retry-evidence deletion.

| Surface | Interaction | Compute/execute | Authority |
|---|---|---|---|
| CLI / Owl | Local/connected adapter | Configurable BEAM roles | Independent deployment configuration |
| TUI / term_ui | Local/connected adapter | Configurable BEAM roles | Same rule |
| Desktop / Elixir Desktop | Native/Phoenix host UI | Configurable host roles | Same rule |
| Android / Mob | On-device Elixir/BEAM UI | Configurable device roles | Same rule, subject to platform validation |
| Web / Phoenix | Browser through authenticated Phoenix interface | Phoenix/other BEAM hosts, independent of view PID | Independently configured |
| Server Node | Application/gateway or headless | Configurable host/resource roles | Stable-host candidate |

These are architecture targets, not tested distributions. [Mob](https://mobframework.com/) offers on-device BEAM; [LiveView](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html) keeps view state server-side. Validate toolchains, native packaging, OS lifecycle and real networking separately.

Membership/code are operator-trusted. Distribution security, client authentication, Run/control/read authorization and provider permissions are explicit boundaries. Scope is composition, not malicious-node containment. Use standard secure distribution/edge validation; no new membership-crypto or untrusted-node sandbox framework is introduced.

## 11. Public Interface Proposal

Exact names are for final review; required behavior is:

| Consumer | Operation | Result |
|---|---|---|
| Application | Start definition/state/Scope with command key | Durable Run receipt; repeated same key/payload yields same creation. |
| Application/UI | Submit input with stable key | Ordered durable acceptance, not proof of processing/success. |
| Operator/application | Suspend/resume/move host | Conditional fenced control receipt. |
| Operator/application | Inspect state/history/attempts | Bounded/paginated projection with revision. |
| Operator/application | Fork BoundaryRef | New Run or explicit stability/compatibility error. |
| Operator/application | Export/import | Validated archive/new branch; activation depends on resources/code. |
| Application/provider/operator | Resolve an uncertain invocation with evidence or an explicit repeat decision | Conditional recorded resolution; immutable intent/history retained. |
| External controller | Select pending intent/resolve/request admission | Conditional grant; no built-in approval API. |
| Worker/adapter | Record observation/outcome/recovery evidence | Durable receipt/canonical reply or conflict/unknown. |

Use consistent tagged errors with stable codes and bounded data: invalid_data, incompatible_version, unavailable_resource, stale_permission, not_stable, key_conflict, authority_unavailable, commit_unknown.

Reject arbitrary client/archive MFA/update functions. Registered callback modules are trusted installed code.

## 12. Maintained Specification Library

After review, publish one Trellis architecture layer:

| File | Owns |
|---|---|
| index.md | Read order, status/governance, requirements/scenarios |
| glossary.md | Canonical vocabulary only |
| boundaries.md | Logical modules/dependencies and generic boundary |
| computation-and-effects.md | Authoring/data/references/public contracts |
| authority-and-recovery.md | Commits/fencing/attempts/outcomes/failures |
| capability-composition.md | Scope/generations/constraints/external seam |
| lifecycle-and-archives.md | Suspend/resume/fork/ETF/compatibility |
| platforms-and-trust.md | Roles/trust/edge integration |
| decisions.md | Concise decisions, alternatives/consequences |

Reviewed target contracts are normative. Mark implementation proposals and unvalidated gates separately. Do not fill existing scaffold coding guidelines with invented conventions.

Preserve rationale for explicit state over replay, designated authority history/identity, immutable intent/late resolution/policy outside Durable, and stable branches/portable data. Storage recommendation remains proposed until validation.

Change guarantees in their owning spec/scenarios first; keep canonical topics linked and supersede decision entries explicitly.

## 13. Delivery and Rollback

This task delivers docs, not a runtime release. Check links/manifests, R1-R19 coverage, state-machine/scenario consistency, vocabulary and approved-versus-proposed status.

Future first implementation uses a non-Agent definition before Agent/frontends. Gate storage/toolchain/disk/quorum, codec bounds, idempotent commands/fencing, host/worker loss, partitions, suspend races, and archive round trips. Platform support requires separate packaging/device checks.

Spec publication is reversible Git work. Preserve existing README/flake/staged work and review only task/spec changes. Future runtime upgrades retain records and validate versions before deployment. No compensation or undo is promised.
