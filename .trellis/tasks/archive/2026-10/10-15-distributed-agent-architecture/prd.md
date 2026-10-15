# Distributed Agent Architecture and Module Boundaries

## Goal and User Value

Agree on a maintainable Elixir/OTP architecture for an AI Agent running across a trusted BEAM cluster. Separate reusable execution mechanisms, Agent reasoning, Harness integrations, and user interfaces so they can evolve without coupling the whole product to one Mix application.

This task produces requirements, architecture decisions, and a future execution plan only. It does not implement application code or authorize implementation.

## Background and Repository Evidence

- `mix.exs` defines `Beamlet.Umbrella.MixProject`, with `apps_path: "apps"` and no root dependencies. `apps/` is currently empty.
- `config/config.exs` contains only the generated umbrella configuration scaffold.
- `README.md` contains build notes and ecosystem references only. Commit `cacf6b0` removed the earlier speculative package list; there is no repository-imposed Effect-system split or finalized package naming.
- `flake.nix` selects OTP 29 and Elixir 1.20 in the development shell; this is configuration evidence, not proof of the currently installed runtime.
- `.trellis/spec/backend/index.md` contains bootstrap placeholders rather than established architecture conventions. It requires English documentation; user-facing discussion remains in Chinese.

## Confirmed Requirements

### R1 — Independent umbrella applications

Separate responsibilities into maintainable libraries/applications rather than one tightly coupled Mix application. Define dependencies and ownership explicitly; avoid splitting into pass-through libraries without meaningful responsibilities.

### R2 — General-purpose distributed action execution

The lower-level libraries support actions submitted by arbitrary callers, including but not limited to Agents. They own the abstraction needed to submit, distribute, execute, and collect action outcomes without importing Agent-loop, Tool-specific, or UI semantics.

### R3 — Agent and Harness separation

The Agent library owns the Agent loop. Harness responsibilities include providing available Tools, environments, and sandbox integrations. Harness authors must not need to know about or depend on the actions/runtime system: their Tool, environment, and model interfaces are execution-backend-neutral. An integration adapter, not Harness, translates between those interfaces and action descriptions/events/requirements. The generic execution layer remains independent of AI-specific scenarios.

### R4 — User-selected authority

The user can select a node to maintain an Agent loop. Agent-created actions, including Tool calls and LLM requests, can execute on eligible nodes in the same cluster, with outcomes returned to the Agent's authority.

### R5 — Composable node roles

All participating nodes belong to one BEAM cluster. Registration declares a combination of interaction, Agent authority, and action execution roles. Interaction-only, authority-only, executor-only, and combined-role nodes must be accounted for.

### R6 — Capabilities and resources

Nodes report the actions they can run and the resources they have available. The design explains how this information influences eligibility and placement without promising distributed consistency.

### R7 — UI independence

Phoenix is the initially planned UI framework, but Agent operation must not depend on Phoenix or any particular UI. Other interfaces must be able to interact with the same Agent functionality.

### R8 — MVP operating assumptions

The first version prioritizes starting and running within a cluster. Cluster nodes are trusted. No external database server or message queue may be required. Prefer existing Elixir/OTP mechanisms where they fit.

### R9 — Future extension space without future-system design

Preserve necessary interfaces and ownership boundaries for later action persistence, recovery, review, and higher availability. Do not design those systems now; the exclusions below define the limit of this task.

### R10 — Environment locality and ownership

Stateful environments may constrain actions to the nodes that host or can access them. Supporting an action type alone does not make a node eligible for an action requiring a specific environment. Environment synchronization, replication, and migration are not project responsibilities; deployments or external environment providers may arrange sharing independently. The framework respects declared environment availability rather than assuming shared filesystems or interchangeable Shell sessions.

### R11 — Live intermediate output

The MVP supports optional intermediate action output, including LLM deltas and Tool progress, independently of terminal outcomes and independently of Phoenix. Intermediate events are ephemeral, not a reliable or complete history.

### R12 — Best-effort cancellation

Callers can request cancellation through a UI-independent interface. Distinguish a cancellation request from observed execution termination and handle completion/cancellation races explicitly. Neither reversal of side effects nor confirmation of remote termination during disconnection is promised.

## Deliverables

- `prd.md`: converged requirements, constraints, and acceptance criteria.
- `design.md`: terminology, application dependencies, responsibilities, OTP process ownership, node roles, action contracts, trade-offs, and representative flows.
- `implement.md`: architecture review checks and a separately gated future execution plan, not implementation authorization.
- `research/`: repository/primary-source evidence supporting important OTP and ecosystem choices, with recommendations distinguished from confirmed facts.

## Acceptance Criteria

- AC1 (R1–R3, R7): The design includes an acyclic umbrella dependency diagram, responsibility ownership, and public interaction points. The generic action layer has no dependency on Agent, Harness-specific Tool semantics, or Phoenix. Harness compiles and can be exercised directly without actions/runtime; only its integration adapter knows both contracts.
- AC2 (R4–R6): A walkthrough shows a UI on node A interacting with an Agent on user-selected node B while an eligible executor on node C runs an action and returns its outcome. Combined roles and ineligible execution targets are also covered.
- AC3 (R3–R6, R10): The design distinguishes action capability, environment availability, and available resources. A Tool action requiring an environment is not placed on a node lacking access to it, even when that node supports the Tool. No environment synchronization or migration is assumed.
- AC4 (R4, R8): Action submission and outcome semantics are explicit. Unsupported reliability guarantees and the limits of failure observation are documented rather than implied.
- AC5 (R7): An Agent can be started and interacted with through a non-Phoenix caller without changing its loop or action contracts.
- AC6 (R8): The proposed MVP can operate without external database or message-broker services; additional dependencies have a concrete justification.
- AC7 (R9): Future extension points are identified without specifying persistence, recovery, review, consensus, or high-availability machinery.
- AC8 (all): The user reviews the converged design. No application code is added or modified, and no implementation is started as part of the architecture discussion.
- AC9 (R11): An execution-to-Agent-to-UI walkthrough shows intermediate output separately from the final result, including finite output handling and a subscriber disconnect without durable replay.
- AC10 (R12): Cancellation walkthroughs cover cancellation before dispatch, during execution, racing with completion, and with an unreachable executor; no path promises side-effect reversal.

## Out of Scope

- Product implementation, Phoenix scaffolding, library scaffolding, and production deployment work.
- Action persistence, recovery, replay, and durable queues.
- Review/approval workflows.
- Consensus, leader election, automatic Agent authority migration, and reliable delivery guarantees.
- Authentication/authorization between trusted cluster nodes.
- Mandatory external database servers or message brokers.
- Designing every planned UI or specifying concrete sandbox isolation technology before its need is established.
- Implementing or designing environment synchronization, replication, or migration.
- Side-effect rollback guarantees, cancellation delivery guarantees, and durable intermediate-event history.
- Human questions/replies modelled as actions, waiting human-request handlers, external-input routing to active actions, and a callback/completion system. Revisit human-input actions only in future callback-related work; do not design that system now. Ordinary user messages remain part of the Agent interaction interface.

## Review Status

The user approved the latest revised architecture summary ("同意以上设计"). Requirements and the design baseline are accepted, with no raised scope question remaining open. The accepted baseline includes Harness independence from actions/runtime, explicit separation of physical execution nodes from product composition, and deferral of human-input actions and callback machinery.

This approval completes architecture review only. Application implementation, scaffolding, dependency additions, and future execution stages remain unauthorized; they require separately scoped and approved tasks.
