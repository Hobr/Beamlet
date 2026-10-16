# Architecture Review and Future Implementation Plan

## Authorization Boundary

This archived task is architecture-only and remains completed; this follow-up revises its documentation without reactivating it. This file is reference planning material, **not** permission to scaffold libraries, add dependencies, implement a provider, run `task.py start`, or enter application implementation. User acceptance of the architecture and its terminology/concurrency revision is separate from authorization of any future implementation task. Persistence, recovery, and distributed consistency remain deferred.

Future implementation should use separately scoped tasks with their own acceptance criteria. The ordered stages below describe a possible sequence, not already-created child tasks or approved work.

## 1. Current Architecture Review Checklist

- [x] Inspect the umbrella, current README, configuration, and available project guidelines.
- [x] Capture user constraints and architecture-only scope in `prd.md`.
- [x] Confirm environment locality and exclude environment synchronization/migration.
- [x] Confirm intermediate output and best-effort cancellation without side-effect reversal.
- [x] Research OTP execution/discovery/registry primitives and release/notification constraints using primary sources.
- [x] Draft responsibilities, acyclic dependencies, role activation, operation contracts, and representative flows in `design.md`.
- [x] Validate the initial draft documents/manifests.
- [x] Revise the Harness/operation adapter seam and clarify composition vs physical execution nodes after user review.
- [x] Record the user decision to defer human-input operations and remove the waiting-handler/input-routing proposal.
- [x] Obtain overall user review of the revised architecture: the user approved the latest summary ("同意以上设计"). Acceptance is not implementation approval.
- [x] Apply the approved follow-up terminology: Operation and Execution are core entities; Result is a shared value with explicit local acceptance, including coordinator-origin termination.
- [x] Document concurrent independent Operations and OTP-based Sub-agent/peer interaction, while deferring persistence, recovery, and distributed consistency.

### Requirements-to-design traceability

| Requirement / criterion | Design sections |
| --- | --- |
| R1, AC1: independent libraries, acyclic dependencies | 2–4, 10 |
| R2, AC1: generic `beamlet_actions`/`beamlet_runtime` | 3, 5–6, 8B |
| R3, AC1/AC3: Agent/Harness responsibilities | 2–3, 7 |
| R4, AC2/AC4: explicit authority and remote operations | 4, 6–8A |
| R5, AC2: role composition | 4, 8B |
| R6, AC3: capabilities/resources and admission | 5 |
| R7, AC5: UI independence | 3, 7, 8A/8D |
| R8, AC4/AC6: MVP limits, no external services | 1, 4–6, 8D, 10 |
| R9, AC7: extension space without deferred-system design | 6, 9 |
| R10, AC3: environment locality | 5, 8A |
| R11, AC9: live output, limits, disconnected subscriber | 6–8 |
| R12, AC10: cancellation races and uncertainty | 6–8C |
| R13, AC12–AC13: independent concurrency and Agent collaboration | 6–7, 8F |
| AC11: shared Result and explicit acceptance | 2, 6 |
| AC8: review without implementation | 1, 11; authorization boundary in this file |

### Current-task validation commands

These check documentation integrity, not runtime correctness:

```bash
python3 ./.trellis/scripts/task.py validate .trellis/tasks/archive/2026-10/10-15-distributed-agent-architecture
git diff --check
git diff --cached --check
git status --short
```

Also inspect any new files, since untracked files are not covered by `git diff --check`. Check manifest targets exist, dependency graph has no cycles, R1–R13 and AC1–AC13 are preserved, and English/Chinese architecture sections and anchors agree. Check OperationRef/OperationCoordinator terminology, shared Result acceptance and coordinator-origin results, single-attempt limits, and Sub-agent/peer cancellation/correlation examples. Changed paths are confined to `architecture.md`, `architecture_zh.md`, and this archived task directory. Read Markdown diagnostics when available; do not represent absent LSP coverage as a clean runtime check.

### Review evidence

At the original review, documentation checks passed: `task.py validate` (two real entries in each manifest), working-tree and staged `git diff --check`, R1–R12 and AC1–AC10 preservation, dependency-graph acyclicity, and task-file whitespace checks. Harness was independent of other Beamlet applications and node composition directly declared operation registration contracts. The withdrawn human-input proposal was absent. These are historical checks, not evidence that this follow-up or any runtime implementation passed testing; rerun the checks above for the revision.

The terminology/concurrency revision passed archived `task.py validate`, working-tree/staged/HEAD whitespace checks, local Markdown link/anchor and code-fence checks, R1–R13/AC1–AC13 coverage, bilingual section/contract checks, and equality/acyclicity of the three dependency diagrams. Active LSP checks found no diagnostics in the six Markdown documents and task metadata. These checks establish document integrity, not runtime correctness; application tests were not run for this documentation-only revision.

The user accepted the architecture baseline and requested its terminology/concurrency update. No runtime implementation is authorized by this archived task or follow-up. Existing application scaffolds are not evidence that these contracts run. Future stages below are reference material only and need separately approved tasks.

## 2. Future Stage A — Generic Contracts and Library Boundaries

Only after a separate task is reviewed and approved:

1. Implement the contracts and mechanisms in the existing `beamlet_actions` and `beamlet_runtime` application scaffolds; do not infer implemented behavior from their names.
2. Define Operation and Execution separately from live refs/context. Use one Result representation for execution returns and operation acceptance; define coordinator-origin Results and optional intermediate events without a separate Outcome entity.
3. Add one non-AI example/test handler to prove that no Agent, Harness, or Phoenix dependency is needed.
4. Prove a plain caller can submit work and receive a result through a stable interface.

Gate: contract tests exercise success, invalid submission, worker failure, caller/coordinator loss, and operations terminating without an execution return. Verify that reporting is distinct from acceptance, accepted Result values are reused rather than copied into an Outcome entity, and stale results cannot overwrite the accepted value. Reject a package split that merely forwards calls without owning protocol/mechanism responsibility.

## 3. Future Stage B — Runtime Discovery, Placement, and Execution

Depends on Stage A contracts.

1. Add dedicated `:pg` scope, endpoint incarnations, directory bootstrap/refresh/expiry, and role/capability/resource snapshots.
2. Add per-Operation temporary coordinators and identified Execution attempts with executor-local gateway/admission/temporary workers. Correlate dispatch identity before confirmed admission; an execution handle exists only after admission.
3. Enforce local resource pools and explicit capability/environment affinity.
4. Add bounded intermediate-event emission and local status retention.
5. Add cancellation, operation deadlines, and loss/unknown results without automatic retry.
6. Verify supervision ownership and that infrastructure restart does not replay business operations.
7. Permit independent Operations to run concurrently but enforce at most one Execution attempt per Operation, including ambiguous admission. Do not implement speculative attempts or automatic retry.

Gate: connected three-node tests use isolated names/cookies and controllable fake handlers. Exercise stale reports, capacity races, missing environment access, incompatible handlers, startup timeout, partition, gateway restart, duplicate/late events, and cancellation/completion races. Test topology teardown must clean up all test nodes.

Do not test disconnected execution by assuming `:DOWN` establishes remote side-effect absence. Assert the observer's uncertainty instead.

## 4. Future Stage C — Harness and Environment Integrations

Harness contracts can be developed independently of Stage A/B; the separate operation integration checks depend on those stages.

1. Implement backend-neutral Tool catalogue/invocation, model reply, and environment contracts in the existing `beamlet_harness` scaffold, without dependencies on `beamlet_actions`/`beamlet_runtime`.
2. Test deterministic fake model/Tool implementations directly, including neutral progress/cancellation hooks, Tool-call IDs, and argument/context validation.
3. Add one explicitly chosen real model integration and one constrained environment/Tool integration in follow-up scope; decide concrete libraries and sandbox guarantees there.
4. In the Agent integration adapter, map native Harness invocations/environment needs to operation descriptions, capability requirements, and node-local slots. Its execution handlers implement the operation behaviour and call Harness interfaces.
5. Keep credentials on execution nodes and disable unsafe hidden provider retries.

Gate: Harness compiles/tests without `beamlet_actions`, `beamlet_runtime`, Agent, or Phoenix. Harness authors implement neither operation handlers nor Operation structs. Adapter integration rejects same-Tool/wrong-environment placement. Catalogue construction does not activate execution services or need executor secrets. Partial streamed Tool-call arguments never become executable calls.

## 5. Future Stage D — Agent Loop and Node Composition

Depends on Stages B–C.

1. Implement the isolated operation integration adapter in `beamlet_agent` and opt-in role subtrees and explicit handler/provider registration in `beamlet_node`. Depend on `beamlet_actions` directly where registration types are referenced; the composition root does not reimplement execution.
2. Implement explicit-authority AgentRefs, local uniqueness, temporary Agent processes, and asynchronous operation orchestration.
3. Implement UI-independent commands, same-channel initial snapshot/events, and subscriber monitoring.
4. Stop scheduling new work when the current turn is stopped, even if cancelled operations later report completion.
5. Add concurrent independent Operation tracking and correlated Sub-agent/peer messaging. Use explicit authority-ready node selection, temporary Agent processes, monitors, and asynchronous completion; select `GenServer` or `:gen_statem` based on actual state complexity.
6. Keep business delegation independent of supervision links. A delegating turn owns its child work and requests a best-effort child-turn stop on stop/observed delegator loss. Independent peers are not implicitly stopped; late replies cannot advance later turns.
7. Do not reserve child-required Execution slots while waiting for delegation replies. Bound Agent count, pending work, and message sizes/rates; no durable messaging or recovery layer is added.
8. Verify each supported role combination; declare role readiness only when configured services/providers are ready.

Gate: run the complete loop with fake model/Tools through IEx/test clients and three BEAM nodes, with no Phoenix. Exercise one Agent's parallel Operations, several concurrent Agents, parallel delegation and joining, peer exchange, child failure, delegator loss/turn stop, disconnect, and late replies. Verify failure isolation and absence of parent-waits-for-child capacity deadlock. Test UI-client loss separately from authority loss. Executor-only nodes start no authority or web services; combined-role local execution uses the same admission path.

## 6. Future Stage E — Phoenix Presentation and Release Smoke Tests

Depends on Stage D; this is a UI implementation scope, not part of this architecture task.

1. Extend the existing `beamlet_web` scaffold as a consumer of Agent commands/snapshots/events.
2. Present progress, final responses, cancellation requests, and unknown results honestly.
3. Add release entry points for product node and product node plus web.
4. Test dependency closure, role-based startup, absent web listeners on non-interaction nodes, and remote Agent control.

Gate: an actual three-node demonstration matches design §8A, and a CLI/IEx client can replace Phoenix without changing Agent/Harness/runtime behavior. No external database or message broker is needed.

### Candidate future validation commands

These are prospective commands after applications and tests exist, not claims about checks run now:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix xref graph --format cycles
MIX_ENV=prod mix release <configured-release-name>
```

Run package-scoped and connected-node ExUnit suites as they are introduced. The current umbrella declares Dialyzer/Credo development tools; verify executable/dependency availability and use the backend quality guidelines rather than treating declarations as evidence of passing checks.

## 7. Risks, Pause Points, and Rollback

- Before scaffolding: if application dependencies cycle, revise the design rather than add a shared grab-bag package.
- Before exposing operation contracts: verify admitted vs submitted and confirmed vs unknown results; these mistakes leak into every caller.
- Before enabling real side effects: use fake handlers to test cancellation/startup ambiguity and disable unsafe automatic retries. Stopping a worker is not rollback.
- Before sharing an environment across nodes: require the deployment/provider to own coordination; do not silently add distributed locks or synchronization here.
- Before role-specific releases: validate actual dependency startup instead of treating package presence as role activation.
- Before shipping streaming: choose concrete payload/rate/retention limits and test slow consumers/providers. Best effort does not justify unbounded resource use.

For this documentation-only task, rollback means revising the proposal and keeping requirements intact. Future implementation should land in independently verifiable stages; if a stage fails its gate, stop before adding the next application or real integration. Never use `git reset --hard` or discard unrelated user changes as a rollback technique.

Human-input operations and a future callback/completion system are explicitly deferred (§8E). Do not schedule human-request handlers, pending-request pools, operation-input routing, or related UI state as part of these stages. Ordinary Agent input remains in scope; future callback-related work requires a separately authorized design.

No Agent/Operation persistence, recovery, inbox/outbox, authority-epoch, review-engine, external-queue, or consensus design is scheduled by this plan. Those reliability topics require separate discussion; the current Result acceptance decision is in memory only.
