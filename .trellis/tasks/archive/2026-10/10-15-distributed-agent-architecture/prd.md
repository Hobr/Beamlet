# Distributed Agent Architecture and Module Boundaries

## Goal and User Value

Agree on a maintainable Elixir/OTP architecture for an AI Agent running across a trusted BEAM cluster. Separate reusable execution mechanisms, Agent reasoning, Harness integrations, and user interfaces so they can evolve without coupling the whole product to one Mix application.

This task produces requirements, architecture decisions, and a future execution plan only. It does not implement application code or authorize implementation.

## Background and Repository Evidence

The following observations describe the original architecture-planning snapshot, not the current implementation. Since then, six application scaffolds and backend guidelines have been added; their presence does not mean the Agent/runtime contracts below are implemented. This revision changes documentation only.

- At original planning time, `mix.exs` defined `Beamlet.Umbrella.MixProject`, with `apps_path: "apps"` and no root dependencies, and `apps/` was empty.
- `config/config.exs` contains only the generated umbrella configuration scaffold.
- `README.md` contains build notes and ecosystem references only. Commit `cacf6b0` removed the earlier speculative package list; there is no repository-imposed Effect-system split or finalized package naming.
- `flake.nix` selects OTP 29 and Elixir 1.20 in the development shell; this is configuration evidence, not proof of the currently installed runtime.
- `.trellis/spec/backend/index.md` contains bootstrap placeholders rather than established architecture conventions. It requires English documentation; user-facing discussion remains in Chinese.

## Confirmed Requirements

### R1 — Independent umbrella applications

Separate responsibilities into maintainable libraries/applications rather than one tightly coupled Mix application. Define dependencies and ownership explicitly; avoid splitting into pass-through libraries without meaningful responsibilities.

### R2 — General-purpose distributed operation execution

The lower-level libraries support Operations submitted by arbitrary callers, including but not limited to Agents, without importing Agent-loop, Tool-specific, or UI semantics. Operation is a structured operation description, not natural-language input; Execution is one attempt to perform it. These are the two core entities. Execution results and accepted Operation results share the Result representation, while reporting and acceptance remain distinct. An Operation can also terminate without an execution-produced result.

### R3 — Agent and Harness separation

The Agent library owns the Agent loop. Harness responsibilities include providing available Tools, environments, and sandbox integrations. Harness authors must not need to know about or depend on the `beamlet_actions`/`beamlet_runtime` system: their Tool, environment, and model interfaces are execution-backend-neutral. An integration adapter, not Harness, translates between those interfaces and operation descriptions/events/requirements. The generic execution layer remains independent of AI-specific scenarios.

### R4 — User-selected authority

The user can select a node to maintain an Agent loop. Agent-created operations, including Tool calls and LLM requests, can execute on eligible nodes in the same cluster, with results returned to the Agent's authority.

### R5 — Composable node roles

All participating nodes belong to one BEAM cluster. Registration declares a combination of interaction, Agent authority, and operation execution roles. Interaction-only, authority-only, executor-only, and combined-role nodes must be accounted for.

### R6 — Capabilities and resources

Nodes report the operations they can run and the resources they have available. The design explains how this information influences eligibility and placement without promising distributed consistency.

### R7 — UI independence

Phoenix is the initially planned UI framework, but Agent operation must not depend on Phoenix or any particular UI. Other interfaces must be able to interact with the same Agent functionality.

### R8 — MVP operating assumptions

The first version prioritizes starting and running within a cluster. Cluster nodes are trusted. No external database server or message queue may be required. Prefer existing Elixir/OTP mechanisms where they fit.

### R9 — Future extension space without future-system design

Preserve necessary interfaces and ownership boundaries for later operation persistence, recovery, review, and higher availability. Do not design those systems now; the exclusions below define the limit of this task.

### R10 — Environment locality and ownership

Stateful environments may constrain operations to the nodes that host or can access them. Supporting an operation type alone does not make a node eligible for an operation requiring a specific environment. Environment synchronization, replication, and migration are not project responsibilities; deployments or external environment providers may arrange sharing independently. The framework respects declared environment availability rather than assuming shared filesystems or interchangeable Shell sessions.

### R11 — Live intermediate output

The MVP supports optional intermediate operation output, including LLM deltas and Tool progress, independently of terminal results and independently of Phoenix. Intermediate events are ephemeral, not a reliable or complete history.

### R12 — Best-effort cancellation

Callers can request cancellation through a UI-independent interface. Distinguish a cancellation request from observed execution termination and handle completion/cancellation races explicitly. Neither reversal of side effects nor confirmation of remote termination during disconnection is promised.

### R13 — Concurrent work and Agent collaboration

A single Agent can initiate several independent Operations, and multiple Agents can work concurrently, subject to resource/environment constraints. Sub-agents are ordinary Agents with explicit delegation relationships; peer Agents can exchange correlated requests/replies independently of a parent/child relationship and independently of UI. Waiting must not block Agent control or prevent child work from obtaining required execution capacity. Stopping a delegating turn requests a best-effort stop of its delegated child turns; late replies cannot advance stopped/later turns, and independent peer lifetimes are not implicitly coupled. Current concurrency does not enable retries or competing Executions of the same Operation, durable messaging, or Agent recovery.

## Deliverables

- `prd.md`: converged requirements, constraints, and acceptance criteria.
- `design.md`: terminology, application dependencies, responsibilities, OTP process ownership, node roles, operation contracts, trade-offs, and representative flows.
- `implement.md`: architecture review checks and a separately gated future execution plan, not implementation authorization.
- `research/`: repository/primary-source evidence supporting important OTP and ecosystem choices, with recommendations distinguished from confirmed facts.

## Acceptance Criteria

- AC1 (R1–R3, R7): The design includes an acyclic umbrella dependency diagram, responsibility ownership, and public interaction points. The generic operation layer has no dependency on Agent, Harness-specific Tool semantics, or Phoenix. Harness compiles and can be exercised directly without `beamlet_actions`/`beamlet_runtime`; only its integration adapter knows both contracts.
- AC2 (R4–R6): A walkthrough shows a UI on node A interacting with an Agent on user-selected node B while an eligible executor on node C runs an operation and returns its result. Combined roles and ineligible execution targets are also covered.
- AC3 (R3–R6, R10): The design distinguishes operation capability, environment availability, and available resources. A Tool operation requiring an environment is not placed on a node lacking access to it, even when that node supports the Tool. No environment synchronization or migration is assumed.
- AC4 (R4, R8): Operation submission and result semantics are explicit. Unsupported reliability guarantees and the limits of failure observation are documented rather than implied.
- AC5 (R7): An Agent can be started and interacted with through a non-Phoenix caller without changing its loop or operation contracts.
- AC6 (R8): The proposed MVP can operate without external database or message-broker services; additional dependencies have a concrete justification.
- AC7 (R9): Future extension points are identified without specifying persistence, recovery, review, consensus, or high-availability machinery.
- AC8 (all): The user reviews the converged design. No application code is added or modified, and no implementation is started as part of the architecture discussion.
- AC9 (R11): An execution-to-Agent-to-UI walkthrough shows intermediate output separately from the final result, including finite output handling and a subscriber disconnect without durable replay.
- AC10 (R12): Cancellation walkthroughs cover cancellation before dispatch, during execution, racing with completion, and with an unreachable executor; no path promises side-effect reversal.
- AC11 (R2, R12): The design distinguishes Operation and Execution, reuses Result values across execution reporting and operation acceptance, covers termination without an execution return, and does not introduce a separate Outcome entity or equate progress with a terminal Result.
- AC12 (R2, R6, R13): Walkthroughs permit concurrent independent Operations from one or several Agents while retaining at most one Execution attempt per Operation, including ambiguous admission, and enforcing resource/environment constraints.
- AC13 (R7, R12–R13): A Sub-agent/peer walkthrough covers correlated asynchronous interaction, independent supervision/business relationships, responsive waiting, best-effort delegated-turn stopping, and late-reply isolation, without implying persistence or reliable delivery.

## Out of Scope

- Product implementation, Phoenix scaffolding, library scaffolding, and production deployment work.
- Agent/Operation persistence, recovery, replay, and durable queues; persistence mechanisms and distributed consistency protocols are deferred for separate discussion.
- Review/approval workflows.
- Consensus, leader election, automatic Agent authority migration, and reliable delivery guarantees.
- Authentication/authorization between trusted cluster nodes.
- Mandatory external database servers or message brokers.
- Designing every planned UI or specifying concrete sandbox isolation technology before its need is established.
- Implementing or designing environment synchronization, replication, or migration.
- Side-effect rollback guarantees, cancellation delivery guarantees, and durable intermediate-event history.
- Human questions/replies modelled as operations, waiting human-request handlers, external-input routing to active operations, and a callback/completion system. Revisit human-input operations only in future callback-related work; do not design that system now. Ordinary user messages remain part of the Agent interaction interface.

## Review Status

The user approved the architecture baseline ("同意以上设计") and subsequently requested this documentation revision after agreeing on Operation/Execution, shared Result values with explicit acceptance, concurrent independent work, and OTP-based Sub-agent/Multi-agent interaction. The accepted boundaries retain Harness independence from `beamlet_actions`/`beamlet_runtime`, separation of physical execution nodes from product composition, and deferral of human-input operations and callback machinery. Persistence, recovery, and distributed consistency are explicitly left for later discussion.

This approval completes architecture review only. Application implementation, scaffolding, dependency additions, and future execution stages remain unauthorized; they require separately scoped and approved tasks.
