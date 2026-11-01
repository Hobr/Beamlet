# Rune-first Durable Codemode Backend

## Goal

Freeze and record the high-level direction for a reusable Rust durable-execution
backend, with Rune as the first Codemode engine and Node/Console as future
validation entry points. This task delivers a decision record, not a working
backend.

## Design-Freeze Acceptance

- [x] Record the selected engine, shared execution model, role boundaries,
      storage direction, transport direction, and application entry points.
- [x] Record deferred scope, including Agent/Harness, graphical clients, and
      other engines.
- [x] Distinguish the frozen high-level direction from provisional detailed
      design and future implementation/acceptance work.
- [x] Preserve the plan without product-code changes, code experiments, or
      runtime testing.

## Planning Status

The user clarified that the current scope is a high-level design freeze only,
with Rune selected as the first Codemode engine. No code experiments,
prototypes, product implementation, or runtime testing are authorized.
The user requested closure after the high-level plan was recorded. The task
is being archived as a documentation-only design freeze; backend implementation
and its acceptance criteria are not completed.

The requirements below describe future goals. Detailed APIs, schemas, replay
mechanisms, resource policies, and implementation steps remain provisional;
they require later review and fresh authorization before execution.

## Confirmed Repository Baseline

- Baseline commit: `e06b2d5` on `dev`; clean before task creation.
- Workspace members: `apps/console`, `apps/node`, and `crates/lib`.
- `beamlet-lib` is a template library with no dependencies.
- Node is a template binary that depends on the library.
- Console already has terminal application dependencies and uses the library.
- Rune 0.14 and infrastructure candidates are declared in the workspace.
  Declaration does not establish integration, compilation, or runtime behavior.
- Backend coding specs remain bootstrap templates; they are not evidence of
  implemented conventions.

## Future Backend Requirements (Deferred)

### R1. Scope and Reuse

The first implementation serves Codemode only. General execution contracts must
remain independent of Session, Prompt, Agent, model tool-call IDs, and Rune
runtime objects. Node and Console are thin hosts over a reusable library.

### R2. One Execution Model

All work uses the same Operation, Attempt, and Report model. An Operation fixes
its logical input; an authorized reexecution creates a distinct Attempt.
Codemode-issued calls are ordinary Operations with provenance, not a separate
child entity or scheduling system.

### R3. Durable Acceptance and Delivery

Acceptance and responsibility for delivery must survive process exit.
Retransmitting the same Attempt must not create another execution. State
changes that promise work and their delivery responsibility must commit
atomically within the owning local store. A network acknowledgement alone is
not proof of durable acceptance or external execution.

### R4. Evidence-Based Recovery

A possibly completed external effect with missing evidence remains unknown,
not an ordinary failure or permission to retry. Cancellation expresses intent;
late reports remain evidence. Recovery rebuilds state from records, not
serialized VM stacks or Futures. No automatic Authority takeover is promised.

### R5. Rune-Only Codemode

Rune is the first and only implemented engine. Host calls use controlled
capability access, bounded concurrency, and bounded input/output. Long work
must not block actor handlers. CPU-bound guest execution must be interruptible
or budgeted; a Tokio timeout alone is insufficient for a non-yielding loop.

### R6. Stable Dynamic Invocation Identity

Reexecuting the same logical script execution must match its recorded logical
host calls without script authors supplying invocation keys. Equal arguments
at different call positions remain distinct calls. The same call identity
with a changed definition is a conflict, never silent reuse.

Controlled replay matching must be demonstrated. Complete transparent program
replay is not a default product promise, and engine selection alone is not
evidence that matching works.

### R7. Explicit Execution Completion

A script returning does not erase admitted calls. Normal completion converges
tracked calls within the configured execution deadline; interruption preserves
partial output and unresolved call references. There is no silent detached
execution or assumption that dropping a Future reverses external effects.

### R8. Deployment and Access

One enabled AuthorityActor and one enabled WorkActor coordinate each Runtime;
managed execution tasks provide concurrency. The first remote transport is
Kameo remote. A remote-only client must not start local roles, a database, an
execution engine, or a broker.

### R9. Storage, Compatibility, and Diagnosis

Use SQLite with SeaORM and versioned migrations for the first backend.
Persist enough version and immutable-input information to reject incompatible
execution recovery. Structured tracing and metrics complement durable facts;
library code must not install global collectors.

### R10. Developer Validation

Console supports script submission and evidence inspection against Node.
The validation path must exercise the same public contracts as embedding
callers, rather than a separate privileged test-only execution route.

## Future Implementation Acceptance Criteria (Not Executed)

- [ ] A1 (R1, R5, R10): A Rune script runs through Console and Node without any
      Agent, model provider, or graphical application.
- [ ] A2 (R2, R6): Loops, repeated equal arguments, and concurrent calls produce
      distinct ordinary Operations; replay of the same controlled trace
      returns their original identities across VM recreation and Attempts.
- [ ] A3 (R6): Changed capability, target, input, or recorded control flow is
      rejected as divergence before uncovered effectful work is released.
- [ ] A4 (R3): Repeated request/report delivery preserves one durable receipt
      per Attempt and does not start an additional execution.
- [ ] A5 (R3, R4): Crashes around admission, effect-entry, report commitment, and
      guest-result delivery preserve committed facts and expose unknowns
      without blind reexecution.
- [ ] A6 (R4, R7): Cancellation, script exit, actor restart, and late reports do
      not delete evidence or imply that old execution has stopped.
- [ ] A7 (R5): Dead-loop, concurrency, queue, and output-limit tests produce
      bounded, observable behavior; storage failure never silently falls back
      to unrecorded execution.
- [ ] A8 (R8): Separate Node processes exchange durable requests and reports
      through Kameo remote; a client-only configuration starts no local roles
      or storage/engine services.
- [ ] A9 (R9): Fresh and upgraded databases retain facts; incompatible recovery
      fails explicitly. Runtime migration needs no globally installed CLI.
- [ ] A10 (R9, R10): Console shows operation identities, attempt evidence,
      unknown outcomes, and cancellation intent. Logs redact secrets and
      metrics avoid operation/attempt IDs as labels.

## Out of Scope

- Agent/Harness, LLM providers, Session/Prompt abstractions.
- Graphical clients; Flutter plus flutter_rust_bridge remains a future direction.
- Other engines, Wasm execution, serialized stacks, or VM snapshot recovery.
- A general workflow/DAG engine or background-job management product.
- MQTT/RMQTT, HTTP, and WebSocket message adapters in this first slice.
- Mandatory brokers, commercial database deployments, or sandbox infrastructure.
- Consensus, automatic Authority failover, or exactly-once external effects.
- A complete malicious-code sandbox or arbitrary untrusted host-tool access.
- A redesign of the existing Console UI or simultaneous delivery of every
  possible CLI, REPL, and TUI interaction.

## Risks and Deferred Claims

Rune invocation timing, controlled scheduling, preemption, and allocation
coverage are implementation feasibility gates, not proven facts. If the spike
cannot satisfy R5/R6, stop for design review rather than weaken the contracts
or silently select another engine. See `design.md` and `implement.md`.
