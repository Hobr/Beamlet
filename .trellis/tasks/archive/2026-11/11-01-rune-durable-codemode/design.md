# Rune-first Durable Codemode Design

## 1. Decision Status

Only the high-level direction is frozen: a reusable Rust backend, Rune-first
Codemode, Node and Console, the shared Operation/Attempt/Report model,
Authority/Work coordination, SQLite with SeaORM, and Kameo remote first.
Agent/Harness, graphical clients, and other engines remain deferred.

The sections below are candidate detailed design notes, not a fully approved
implementation specification or proof of engine feasibility. Exact APIs,
schemas, journal ownership, replay mechanisms, resource policies, and layouts
may be refined later. No code experiments or implementation are authorized
at this stage.

Rune is the only first-release Codemode engine. Existing rquickjs, Wasmtime,
and RMQTT workspace declarations are not an instruction to integrate them.
Do not remove unrelated declarations merely to prepare this task.

## 2. Boundaries and Layout

Keep one reusable library and the existing two thin applications:

```text
apps/node                 configuration, lifecycle, collectors
apps/console              submission and evidence inspection
crates/lib/src/
  api/                    Client versus Host entry points
  model/                  engine/actor/database-independent contracts
  authority/              authorization, admission, result adoption
  work/                   receipts, bounded scheduling, execution evidence
  execution/codemode/     Rune adapter, invocation tracking, guest driver
  durable/                SQLite transactions, migrations, delivery records
  transport/              local access and Kameo remote adapter
  observability.rs        emitted tracing and metrics
```

These are module boundaries, not a demand for many crates or public traits.
A generated migration crate is acceptable when required by the chosen SeaORM
layout; it is schema tooling, not another domain layer.

Client submits, queries, and observes. Host configures and starts enabled roles
and services. The model must not expose Rune Values, SQLite connections, or
Kameo references as portable operation data. Heavy storage/execution/network
facilities belong behind dependency features and explicit Host construction.

## 3. Actors, Tasks, and Lifecycles

Each Runtime has at most one enabled AuthorityActor and one enabled WorkActor,
not one actor per operation. Handlers perform short control steps and delegate
long-running work to bounded, tracked execution tasks.

Task completion, errors, and panics return as evidence. Actor restart does not
prove that old tasks or external processes stopped. Reassociate or reconcile
old execution before starting replacements; a supervisor must not blindly
restart a side-effecting Attempt.

Rune's supported Send execution path versus a bounded dedicated-thread or
LocalSet driver must be established by the initial spike. Do not introduce
unsafe Send implementations to fit a preferred Tokio spawning pattern.

Kameo's researched 0.22 remote implementation uses a process-global Swarm.
Host owns bootstrap; clients and roles do not bootstrap their own network.
Initially deploy and test one networked Node per process. Verify this constraint
against the exact resolved version before integrating.

## 4. Domain Identity and Immutable Input

An Operation identifies logical work and fixes its definition. An Attempt
identifies an authorized actual execution. Reports are retained evidence;
Authority decides whether and how to adopt them.

Codemode itself is an ordinary Operation. Its host-issued operations carry
`caused_by_operation_id` and `invocation_key` provenance. The host fills those
fields. Provenance alone grants no permission inheritance, cancellation
propagation, lifecycle ownership, or waiting semantics.

Freeze source or an immutable artifact reference, start input, capability
bindings, grants, limits, engine fingerprint, and host API version before
execution. Changed source means a new Operation, not a modified retry.

Use explicit structured-data codecs and bounded payloads across boundaries.
Large/binary output uses artifact references rather than arbitrary live host
objects. Canonical encoding and BLAKE3 validate definitions; their algorithm
and encoding versions are recorded. A digest does not replace logical identity.

## 5. Stable Invocation Admission

The durable uniqueness scope is:

```text
(Codemode Operation P, invocation key cN) -> ordinary Operation C
```

Matching the same definition returns C. A different definition at that key is
a conflict. Equal arguments at c1 and c2 remain separate calls. A new Attempt
of P must not become a fresh invocation scope.

Allocate the monotonically ordered key synchronously when guest code invokes
the native host boundary, before creating or polling its async execution.
Create a tracked call descriptor at that point. An async service then obtains
durable Authority admission before any effectful execution.

If Rune's native async binding defers the function body until polling, use a
synchronous submit wrapper returning an awaitable handle. Never allocate keys
in an async body merely because it appears first in source code. Script authors
do not supply keys in ordinary use.

Authority admission atomically validates the definition, inserts or retrieves
the mapping, and records operation/attempt/delivery responsibility as required.
Store a database uniqueness constraint, not just a process-local map.

Do not allow two live continuations of P to admit uncovered work. Check an
active execution-generation token for admissions and journal writes. Fencing
new admissions does not stop external effects already started by an old
Attempt, and is not an automatic Authority takeover protocol.

## 6. Result Journal and Controlled Replay

Keep three distinct records:

1. General operation/attempt/report facts.
2. Codemode invocation and guest-delivery journal.
3. Diagnostic tracing and aggregate metrics.

Authority owns the logical invocation mapping and committed guest-delivery
schedule. A remote Work runner uses the Authority contract rather than assuming
it shares a transaction or database with Authority.

Commit an externally sourced result or rejection and its guest-delivery order
before resuming guest code. The commit records permission/order for delivery,
not proof that the VM consumed the value before a crash. Recreated VMs can
receive that recorded value again without creating another underlying call.

The Rune driver must release completion readiness according to the committed
schedule; wall-clock completion, arbitrary Future poll order, and hash-map
iteration cannot silently define replay behavior. Expose external time,
randomness, and other nondeterminism only through controlled recorded inputs
if those facilities are introduced. Mount only required host modules.

A controlled replay checks the recorded issued-call prefix and guest-input
prefix. Validate a recorded checkpoint before releasing uncovered effectful
work. Reject mismatched definitions, missing calls, changed control flow, or
incompatible fingerprints rather than guessing.

The first slice must prove this matching contract in a replay harness.
Unattended transparent replay of arbitrary scripts is not promised. Accepted
recovery actions remain query/reconnect, explicitly authorized reexecution,
a new continuation Operation, or abandonment without deleting evidence.

## 7. Durable Flow and Local Transactions

```text
Authority transaction:
  decision + Operation/Attempt + request delivery responsibility
    -> Work transaction:
         durable receipt before Accepted reply
         record entry into possible-effect execution
           -> tracked execution task
             -> Work transaction:
                  Report + report delivery responsibility
                    -> Authority transaction:
                         deduplicate + retain evidence + adopt decision
```

Each arrow crosses a transaction boundary; this is not a distributed
transaction. Actor ask/tell completion and transport delivery are not substitutes
for these commits. An admission timeout means the response is ambiguous.

Use transaction-scoped store operations, not independent save calls for a
decision and its delivery record. Embedding business state in the same SQLite
database requires access to the same transaction boundary. State in an external
database needs an explicit integration contract; no cross-database atomicity is
implied.

After a durable effect-entry record, absent completion evidence is unknown.
A duplicate request for the same Attempt returns its receipt/evidence rather
than entering execution again. Policy-approved reexecution creates a new
Attempt and preserves previous unknown evidence.

If the store cannot commit admission, entry, report, or delivery schedule,
fail closed at that boundary. Never continue with an in-memory-only promise.

## 8. Completion, Cancellation, and Limits

Track every host call, including calls whose awaitable is dropped or not
awaited. On normal script return, converge admitted calls within the configured
execution deadline. On interruption or deadline, retain observed output and
unresolved operation references. Do not report unqualified settled success
while admitted calls are unaccounted for.

This is a Codemode executor policy, not automatic lifecycle inheritance for
all provenance-linked Operations. Cancellation is a separate intent; dropping
an awaitable cannot undo an accepted operation or external effect. Continue
accepting late evidence after the VM ends.

Bound actor mailboxes, submission queues, running Attempts, active VMs,
per-script outstanding calls, payload/output size, and execution time.
Propagate structured overload responses rather than unbounded buffering.

Validate instruction budgets and cancellation checks with a non-yielding guest
loop. Native host functions require independent cancellation/resource policy.
Rune memory controls do not automatically account for all Rust allocations.
Start with trusted scripts and explicitly granted host tools; do not claim
complete adversarial isolation without the deferred sandbox layer.

## 9. Transport, Trust, and Versioning

Kameo remote is the first adapter over shared admission/report contracts.
Persist Node network identity, define the peer trust configuration, and reject
unauthorized capability/target requests at Authority. Discovery is not
authorization. Network request IDs and message type IDs are not Operation IDs.

Use a small versioned protocol envelope. Reject incompatible versions before
admission; avoid a universal replacement actor/protocol framework.

Do not assume independently startable remote Runtimes in one process. If a
direct libp2p dependency is needed for custom identity/network setup, align it
with the exact libp2p version used by resolved Kameo.

## 10. Storage and Compatibility

The first storage adapter uses SeaORM with SQLite. Keep Authority and Work
ownership explicit even if a local deployment stores them in one file.
Do not require a shared filesystem database across Nodes.

Migration code depends on sea-orm-migration, whether generated in a separate
crate or kept in the storage implementation. Node invokes migrations through
the library; end users need no globally installed sea-orm-cli.

Record schema, codec, host API, source/binding, and engine compatibility data.
A library version string alone may not describe the complete engine
configuration. Preserve readable historical evidence when execution recovery
is rejected. Never silently rebuild or erase an incompatible database.

## 11. Observability and Rollback

Library code emits tracing and metrics. Hosts install subscribers/recorders
and optional exporters. Include operation/attempt IDs in diagnostic fields,
not high-cardinality metric labels; redact credentials and sensitive payloads.

Develop with deterministic test capabilities and disposable databases first.
Before touching persistent operator data, test migration against a copied
database and retain a backup. Rollback stops new admissions and reports
unresolved Attempts; it does not fabricate cancellation or discard the outbox.
Schema/codec changes require an explicit compatibility or restore plan.
