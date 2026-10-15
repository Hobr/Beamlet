# Architecture Review and Future Implementation Plan

## Authorization Boundary

This task is architecture-only. The current deliverables are documents, and its status remains `planning`. This file is required planning material, **not** permission to scaffold libraries, add dependencies, implement a provider, run `task.py start`, or enter application implementation. User acceptance of the architecture must be recorded separately from authorization of any future implementation task.

Future implementation should use separately scoped tasks with their own acceptance criteria. The ordered stages below describe a possible sequence, not already-created child tasks or approved work.

## 1. Current Architecture Review Checklist

- [x] Inspect the umbrella, current README, configuration, and available project guidelines.
- [x] Capture user constraints and architecture-only scope in `prd.md`.
- [x] Confirm environment locality and exclude environment synchronization/migration.
- [x] Confirm intermediate output and best-effort cancellation without side-effect reversal.
- [x] Research OTP execution/discovery/registry primitives and release/notification constraints using primary sources.
- [x] Draft responsibilities, acyclic dependencies, role activation, action contracts, and representative flows in `design.md`.
- [x] Validate the initial draft documents/manifests.
- [x] Revise the Harness/action adapter seam and clarify composition vs physical execution nodes after user review.
- [x] Record the user decision to defer human-input actions and remove the waiting-handler/input-routing proposal.
- [x] Obtain overall user review of the revised architecture: the user approved the latest summary ("同意以上设计"). Acceptance is not implementation approval.

### Requirements-to-design traceability

| Requirement / criterion | Design sections |
| --- | --- |
| R1, AC1: independent libraries, acyclic dependencies | 2–4, 10 |
| R2, AC1: generic actions/runtime | 3, 5–6, 8B |
| R3, AC1/AC3: Agent/Harness responsibilities | 2–3, 7 |
| R4, AC2/AC4: explicit authority and remote actions | 4, 6–8A |
| R5, AC2: role composition | 4, 8B |
| R6, AC3: capabilities/resources and admission | 5 |
| R7, AC5: UI independence | 3, 7, 8A/8D |
| R8, AC4/AC6: MVP limits, no external services | 1, 4–6, 8D, 10 |
| R9, AC7: extension space without deferred-system design | 6, 9 |
| R10, AC3: environment locality | 5, 8A |
| R11, AC9: live output, limits, disconnected subscriber | 6–8 |
| R12, AC10: cancellation races and uncertainty | 6–8C |
| AC8: review without implementation | 1, 11; authorization boundary in this file |

### Current-task validation commands

These check documentation integrity, not runtime correctness:

```bash
python3 ./.trellis/scripts/task.py validate .trellis/tasks/10-15-distributed-agent-architecture
git diff --check
git diff --cached --check
git status --short
```

Also inspect all new files, since untracked files are not covered by `git diff --check`. Check manifest targets exist, dependency graph has no cycles, R1–R12 and AC1–AC10 are preserved, and changed paths are confined to this task directory. Read Markdown diagnostics when available; do not represent absent LSP coverage as a clean runtime check.

### Review evidence

Documentation checks passed: `task.py validate` (two real entries in each manifest), working-tree and staged `git diff --check`, R1–R12 and AC1–AC10 preservation, dependency-graph acyclicity, and task-file whitespace checks. The revised graph was checked with Harness independent of other Beamlet applications and node composition directly declaring action registration contracts. The withdrawn human-input action proposal is absent from the current scope. Markdown tool checks reported clean documents.

The user has now accepted the revised architecture baseline. No Mix compile, application tests, connected-node tests, or releases were run: no application implementation exists, and document checks cannot prove runtime correctness. The task remains `planning` to avoid entering application implementation; architecture acceptance is recorded in `prd.md`, `design.md`, and task notes. Future stages below are reference material only and need separately approved tasks.

## 2. Future Stage A — Generic Contracts and Library Boundaries

Only after a separate task is reviewed and approved:

1. Create `beamlet_actions` and `beamlet_runtime` library applications.
2. Implement data descriptions separately from live refs/context; define normalized outcomes and optional events.
3. Add one non-AI example/test handler to prove that no Agent, Harness, or Phoenix dependency is needed.
4. Prove a plain caller can submit work and receive a result through a stable interface.

Gate: contract tests exercise success, invalid submission, worker failure, and caller/coordinator loss. Reject a package split that merely forwards calls without owning protocol/mechanism responsibility.

## 3. Future Stage B — Runtime Discovery, Placement, and Execution

Depends on Stage A contracts.

1. Add dedicated `:pg` scope, endpoint incarnations, directory bootstrap/refresh/expiry, and role/capability/resource snapshots.
2. Add per-action temporary coordinators and executor-local gateway/admission/temporary workers.
3. Enforce local resource pools and explicit capability/environment affinity.
4. Add bounded intermediate-event emission and local status retention.
5. Add cancellation, operation deadlines, and loss/unknown outcomes without automatic retry.
6. Verify supervision ownership and that infrastructure restart does not replay business operations.

Gate: connected three-node tests use isolated names/cookies and controllable fake handlers. Exercise stale reports, capacity races, missing environment access, incompatible handlers, startup timeout, partition, gateway restart, duplicate/late events, and cancellation/completion races. Test topology teardown must clean up all test nodes.

Do not test disconnected execution by assuming `:DOWN` establishes remote side-effect absence. Assert the observer's uncertainty instead.

## 4. Future Stage C — Harness and Environment Integrations

Harness contracts can be developed independently of Stage A/B; the separate action integration checks depend on those stages.

1. Create `beamlet_harness` with backend-neutral Tool catalogue/invocation, model reply, and environment contracts, without dependencies on actions/runtime.
2. Test deterministic fake model/Tool implementations directly, including neutral progress/cancellation hooks, Tool-call IDs, and argument/context validation.
3. Add one explicitly chosen real model integration and one constrained environment/Tool integration in follow-up scope; decide concrete libraries and sandbox guarantees there.
4. In the Agent integration adapter, map native Harness invocations/environment needs to action descriptions, capability requirements, and node-local slots. Its execution handlers implement the action behaviour and call Harness interfaces.
5. Keep credentials on execution nodes and disable unsafe hidden provider retries.

Gate: Harness compiles/tests without actions, runtime, Agent, or Phoenix. Harness authors implement neither action handlers nor Action structs. Adapter integration rejects same-Tool/wrong-environment placement. Catalogue construction does not activate execution services or need executor secrets. Partial streamed Tool-call arguments never become executable calls.

## 5. Future Stage D — Agent Loop and Node Composition

Depends on Stages B–C.

1. Create `beamlet_agent` with an isolated action integration adapter and `beamlet_node` with opt-in role subtrees and explicit handler/provider registration. Declare actions directly where its registration types are referenced; the composition root does not reimplement execution.
2. Implement explicit-authority AgentRefs, local uniqueness, temporary Agent processes, and asynchronous action orchestration.
3. Implement UI-independent commands, same-channel initial snapshot/events, and subscriber monitoring.
4. Stop scheduling new work when the current turn is stopped, even if cancelled actions later report completion.
5. Verify each supported role combination; declare role readiness only when configured services/providers are ready.

Gate: run the complete loop with fake model/Tools through IEx/test clients and three BEAM nodes, with no Phoenix. Test UI-client loss separately from authority loss. Verify that executor-only nodes start no authority or web services, and that combined-role local execution uses the same admission path.

## 6. Future Stage E — Phoenix Presentation and Release Smoke Tests

Depends on Stage D; this is a UI implementation scope, not part of this architecture task.

1. Create `beamlet_web` as a consumer of Agent commands/snapshots/events.
2. Present progress, final responses, cancellation requests, and unknown outcomes honestly.
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

Run package-scoped and connected-node ExUnit suites as they are introduced. Add Dialyzer/Credo checks only after those tools are actually configured; the current README's command list is not proof they are installed.

## 7. Risks, Pause Points, and Rollback

- Before scaffolding: if application dependencies cycle, revise the design rather than add a shared grab-bag package.
- Before exposing action contracts: verify admitted vs submitted and confirmed vs unknown outcomes; these mistakes leak into every caller.
- Before enabling real side effects: use fake handlers to test cancellation/startup ambiguity and disable unsafe automatic retries. Stopping a worker is not rollback.
- Before sharing an environment across nodes: require the deployment/provider to own coordination; do not silently add distributed locks or synchronization here.
- Before role-specific releases: validate actual dependency startup instead of treating package presence as role activation.
- Before shipping streaming: choose concrete payload/rate/retention limits and test slow consumers/providers. Best effort does not justify unbounded resource use.

For this documentation-only task, rollback means revising the proposal and keeping requirements intact. Future implementation should land in independently verifiable stages; if a stage fails its gate, stop before adding the next application or real integration. Never use `git reset --hard` or discard unrelated user changes as a rollback technique.

Human-input actions and a future callback/completion system are explicitly deferred (§8E). Do not schedule human-request handlers, pending-request pools, action-input routing, or related UI state as part of these stages. Ordinary Agent input remains in scope; future callback-related work requires a separately authorized design.

No persistence, recovery, review engine, external queue, or consensus design is scheduled by this plan.
