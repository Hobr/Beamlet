# Distributed Agent Multi-node MVP

## Goal and User Value

Deliver the first usable backend of the accepted distributed-agent architecture:
a caller chooses an Agent authority, the Agent runs model/Tool Operations on
eligible connected BEAM nodes, and the caller observes results and controls work
through IEx/CLI. The first version must work across physical machines, not just
simulate distribution on one host.

The user approved task creation and selected **B: usable backend**. This includes
real model integration, a constrained read-only workspace Tool, deterministic
test providers, concurrent work, Sub-agent delegation, and peer interaction.
It excludes a Web product UI. Approval of this final implementation plan is
still pending; all parent/child tasks remain in planning.

## Background and Evidence

- `architecture.md` / `architecture_zh.md`, especially §§3–11, and archived task
  `10-15-distributed-agent-architecture` establish the accepted boundaries and
  failure semantics. That archived task authorized documentation, not code.
- `apps/beamlet_agent/lib/beamlet/agent.ex` and the other non-web entry modules
  contain only generated `hello/0` implementations.
  `apps/beamlet_node/lib/beamlet/node/application.ex` has an empty supervisor.
- Phoenix currently provides a welcome page. `config/runtime.exs` requires
  `SECRET_KEY_BASE` for every production boot, including a future headless
  release. `README.md` has no multi-machine deployment instructions.
- Parent-session baseline: Elixir 1.20.4 / OTP 29; existing compilation succeeded
  with dependency warnings, and 17 existing tests passed. A disposable controller
  and two independent `:peer` VMs connected successfully on one host. These
  checks prove neither application execution nor physical multi-machine behavior.
- Primary-source findings and caveats are in
  `research/provider-workspace-release.md`; its proposed limits/protocol subset
  become task decisions only through review of this plan.

## Requirements

### R1 — Independent reusable boundaries

Keep the six applications and acyclic dependency direction. Generic contracts
and execution must work without Agent, Harness, or Phoenix. Harness must compile
and execute directly without Actions/Runtime. Only the Agent integration adapter
translates between native Harness and operation contracts.

### R2 — Actual multi-machine runtime

Support statically connected trusted BEAM nodes, explicit user-selected authority,
role discovery/readiness, capability/environment eligibility, resource-aware
placement, and executor-local authoritative admission. Support interaction-only,
authority-only, executor-only, and combined-role configurations. A missing executor
must not cause execution on an unauthorized node or different workspace.

### R3 — Operation lifecycle and honest failures

Operation and Execution remain distinct entities; Result is the shared terminal
value accepted once by the coordinator in memory. At most one Execution attempt
per submission, including uncertain admission. Support asynchronous submit,
status, bounded progress, deadline and best-effort cancel. Distinguish definite
rejection/failure, observed cancellation, timeout, and loss/unknown. Never
automatically retry, relocate, replay, or imply exactly-once side effects.

### R4 — Real model and constrained workspace integration

Provide a configurable executor-local OpenAI-compatible model adapter and
read-only workspace file Tool. Validate complete model tool-call batches and
arguments before any execution, preserving tool-call identity and original order.
Keep credentials and absolute workspace roots on executors, out of discovery
reports, operation payloads, snapshots, and logs. Deterministic providers and
local HTTP fixtures remain first-class verification paths.

For this proposed first adapter, compatibility means text Chat Completions
with non-streaming function tools, not all OpenAI APIs/models. The workspace
Tool operates on a dedicated trusted local permitted-content tree: it rejects
traversal/symlinks/nonregular files and bounds reads, but is not an adversarial
filesystem/OS sandbox and does not guarantee atomic or snapshot reads.

### R5 — Responsive Agent and collaboration

An Agent maintains bounded in-memory context and a single active turn, submits
independent Tool Operations concurrently, joins by identity, and remains
responsive to snapshots/stop. Several Agents can work concurrently. Provide
asynchronous correlated Sub-agent and peer APIs with explicit authority addresses.
Delegated work belongs to its parent turn; stopping it or observing delegator
loss requests child-turn cleanup. Peers have independent lifetimes. Late replies
must not advance stopped or later turns, and waiting parents hold no executor slots.
Collaboration is initially driven through Agent/IEx/CLI APIs; autonomous
LLM-selected delegation policy is not required.

### R6 — Non-Web clients and deployable backend

Provide IEx APIs and a CLI path for creating Agents, input, snapshot/status,
subscription, stopping, and collaboration. Initial subscription snapshot and
subsequent events share an ordered channel; disappearing/slow clients must not
terminate or block the Agent. Provide a backend release without Phoenix/web
listeners or dummy web secrets; retain existing Web scaffold behavior/security.

### R7 — Finite resource use and explicit operational limits

Bound active coordinators/workers/Agents, pending work/delegations/messages,
payload/result/progress/context sizes, subscriber outstanding events, and retained
terminal state. Overflow must be explicit rejection, truncation of display/text
output, or bounded coalescing as appropriate; never execute truncated arguments.
Infrastructure restart must not silently replay business work or leave unaccounted
workers behind.

## Acceptance Criteria

| ID | Observable result | Requirements | Owning child |
| --- | --- | --- | --- |
| AC1 | Non-AI handler submits/executes successfully with no Harness/Agent/Phoenix dependency; Harness tests independently without Actions/Runtime; sibling dependencies have no cycles. | R1 | 1, 2, 4 |
| AC2 | On three BEAM nodes A/B/C, A controls an Agent on B and C executes model/Tool work. At least B/C run on different physical hosts for the physical acceptance record; same-host peers are separately labelled automation only. | R2, R6 | 4 |
| AC3 | Missing capability, stale/unready endpoint, wrong environment, insufficient capacity, or definite admission rejection produces a non-started result; competing callers never exceed one executor's configured capacity. | R2, R3 | 1, 3 |
| AC4 | Tests cover submit vs admission, no-target results without synthetic executions, cancel before dispatch/during work/racing success, owner/coordinator/gateway loss, deadline, uncertain admission, partition, and stale/duplicate replies. No ambiguous attempt is retried. | R3, R7 | 1 |
| AC5 | HTTP adapter sends a real compatible wire request through a local HTTP fixture, normalizes final text/function calls, preserves IDs, and rejects malformed/refused/incomplete/oversized replies. Redirect/429/500/timeout tests prove no hidden retry. An operator-run live-provider smoke path is documented separately. | R4 | 2, 4 |
| AC6 | A configured workspace file can be read only on its eligible executor; traversal, absolute paths, symlink components, directory/device/FIFO leaves, invalid text and over-limit arguments are rejected. Long text returns a bounded UTF-8 result with truncation metadata. No shell or write path exists. | R2, R4 | 2, 3 |
| AC7 | One Agent and several Agents complete independent Tool calls concurrently, including out-of-order completion, while preserving call/result correlation; invalid sibling calls are rejected before any batch dispatch. | R4, R5 | 3 |
| AC8 | Parallel delegated child turns join asynchronously; stop/delegator loss requests child cleanup; late replies cannot resume a stopped/later turn; child failure/disconnection is explicit; peer lifetime is independent and parent waits consume no executor capacity. | R5 | 3 |
| AC9 | Initial snapshot precedes events, slow clients see bounded/coalesced output, client exit removes only subscription, and reconnect obtains a fresh snapshot without replay promises. Limits and retention expiry are tested. | R6, R7 | 1, 3 |
| AC10 | Backend release boots without source checkout, Phoenix artifacts/listeners, web secret or authority-side model credentials. Executor-only boot starts no authority services; local combined-role work uses the same gateway. Existing Web production secret fail-fast and CSP tests remain intact. | R1, R2, R6 | 3, 4 |
| AC11 | README/runbook and repeatable scripts describe long names, cookie, reachable hostnames, EPMD/distribution ports, role/provider/workspace config, teardown, and an actual multi-host verification record. Missing hosts/credentials are recorded as pending, never reported as tested. | R2, R4, R6 | 4 |
| AC12 | Formatting, application compilation/tests, distributed tests, static analysis, dependency/release checks, and final parent integration review have recorded results; failures/skips have concrete explanations. | All | All |

## Out of Scope

- Persistence, checkpoints, recovery, replay, durable queues/inboxes/outboxes.
- Consensus, distributed locks, global consistent scheduling/identity, leader
  election, authority migration, failover, exactly-once or reliable delivery.
- Web product pages, full terminal UI, a new HTTP control API.
- Automatic cluster connection discovery, external databases or message brokers.
- Shell/write Tools, full sandbox isolation, hostile-filesystem containment,
  environment copying/synchronization/migration, or side-effect rollback.
- SSE/token streaming in the first real model adapter; generic bounded progress
  remains in scope. No multimodal/Responses API/full JSON Schema compatibility.
- Human-input Operations, callback/completion infrastructure, review workflows,
  workflow DSL, and automatic LLM orchestration of Agent delegation.
- Authentication/authorization between already trusted cluster nodes.

## Task Map and Cross-child Acceptance

1. `../10-16-operation-runtime`: generic contracts and multi-node runtime.
2. `../10-16-harness-providers`: independent native Harness and concrete providers.
3. `../10-16-agent-orchestration`: Agent, adapters and node-role composition;
   depends on accepted outputs of 1 and 2.
4. `../10-16-backend-release`: CLI/release/deployment and end-to-end acceptance;
   depends on 1–3.

The parent owns this requirement set, cross-child contracts, AC2/AC11 integration
sign-off and final review. It is not the initial implementation target. Child 1
and 2 have independent gates; the default work order is 1 → 2 → 3 → 4 with one
writer at a time. No task-tree edge substitutes for the written dependencies.

## Review and External Verification Status

No unresolved scope question remains beyond approval of the proposed detailed
plan. Physical hosts/network access and live-provider credentials/spending are
execution-time prerequisites, not silently granted permissions. Never request
secrets in chat or make paid calls without approval. Automated local HTTP tests
do not claim that a third-party model was called; same-host peer tests do not
satisfy AC2/AC11's physical-host record. Parent completion remains blocked on any
required physical-host evidence not yet obtained.
