# Rust Workspace Guidelines

Read this directory for changes to the Rust workspace, shared library, or
Node scaffold. The directory name is retained as the existing Trellis entry
point; it does not imply an implemented server stack.

## Before Development

1. Read [directory structure](directory-structure.md) for package ownership and
   dependency inheritance.
2. Read [quality guidelines](quality-guidelines.md) for the existing checks.
3. For Console behavior, also read the [Console index](../console/index.md).
4. For shared or cross-boundary changes, use the [thinking guides](../guides/index.md).

## Implementation Status

- [Node main](../../../apps/node/src/main.rs) prints a greeting; it does not
  start runtime roles or network services.
- [The shared library](../../../crates/lib/src/lib.rs) contains the generated
  add example and its inline unit test, not a backend domain model.
- [Console](../console/index.md) contains the implemented terminal event/state
  loop. Its scaffold is not a durable-work scheduling model.
- [Workspace dependency declarations](../../../Cargo.toml) include Rune,
  SeaORM, Kameo, and tracing candidates. The inspected member sources do not
  initialize these systems. No database schema, migration flow, logging setup,
  operation protocol, or recovery implementation is established.

Add database, logging, or domain-specific guides when real implementation or
an explicitly approved contract supplies evidence. Do not invent ORM query
patterns, error hierarchies, or actor conventions to fill absent topics.

## Quality Check

Use the [quality guide](quality-guidelines.md) for the kind of change made.
Check source references and navigation for documentation changes. A source
listing or command definition is not evidence that a runtime check passed.
