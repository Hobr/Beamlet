# Reuse and Ownership

Use this guide before adding a helper, moving code across packages, or copying
behavior.

## Find the Existing Owner

The [workspace structure](../backend/directory-structure.md) identifies the
current packages. Search tracked product files first; local Cargo dependency
source and bundled Trellis scripts do not establish product conventions.

For Console, inspect these owners before adding a parallel implementation:

- [App and dispatch](../../../apps/console/src/app.rs) own application state.
- [Event types and producer](../../../apps/console/src/event.rs) own input messages.
- [Borrowed widget rendering](../../../apps/console/src/ui.rs) owns presentation.

A new key binding should feed the existing action path, not duplicate counter
logic in rendering. A new widget should consume the appropriate state rather
than introducing its own terminal reader.

## Choose Local or Shared Deliberately

[The shared library](../../../crates/lib/src/lib.rs) is still an example crate.
Both applications declare it, but neither currently calls its example API.
Do not infer an established client/runtime abstraction from that dependency.

Keep Console-only UI code local. Move behavior into the library when a real
shared contract warrants it, with source and tests that establish its purpose.
A planned future consumer alone does not establish an existing reuse pattern.

## Check the Meaning Before Extracting

AppEvent and EventTask are local terminal-loop concepts. Their names do not
make them equivalents of a future durable report or worker. Likewise, the
Console queue's current unbounded capacity is a limitation, not a general
instruction to build new execution queues the same way.

Read [the event guide](../console/event-loop.md) for the local pattern and
[the error guide](../console/error-handling.md) for its limits. Document a new
shared pattern after its implementation supplies evidence, rather than
inventing public traits during unrelated maintenance.
