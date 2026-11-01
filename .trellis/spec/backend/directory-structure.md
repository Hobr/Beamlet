# Workspace and Directory Structure

## Package Ownership

The [root manifest](../../../Cargo.toml) is authoritative for workspace members.

| Path | Current responsibility |
| --- | --- |
| [apps/console](../../../apps/console/Cargo.toml) | Tokio/Ratatui terminal application |
| [apps/node](../../../apps/node/Cargo.toml) | Node binary scaffold |
| [crates/lib](../../../crates/lib/Cargo.toml) | Shared library scaffold |

The current product source layout is:

```text
apps/console/src/
  main.rs       runtime and terminal entry point
  app.rs        application state and dispatch
  event.rs      terminal/tick producer and typed events
  ui.rs         borrowed App widget rendering
apps/node/src/
  main.rs       binary entry point
crates/lib/src/
  lib.rs        library entry point and inline example test
```

Keep application-specific terminal behavior in Console. A move into the shared
library needs genuinely reusable behavior and a defined public contract; the
mere existence of a shared crate is not a reason to move TUI internals there.
See the [reuse guide](../guides/code-reuse-thinking-guide.md).

## Manifest Pattern

The three member manifests inherit package metadata such as version, edition,
repository, and license from the workspace. Follow that existing inheritance
rather than introducing conflicting per-member values.

Both application manifests declare the shared library using:

```toml
[dependencies]
beamlet-lib.workspace = true
```

The corresponding path dependency is defined once in the root manifest.
Currently neither binary calls the library's example API.

A root workspace dependency is an available declaration, not automatic use by
every member. Console inherits futures and Tokio while also declaring its
terminal libraries locally. Node depends only on the shared library, whose
dependency table is empty. Read the member manifest before claiming that a
candidate infrastructure library is part of an application's behavior.

## Product Source Versus Tooling

[AGENTS.md](../../../AGENTS.md) routes Trellis workflow and guidance.
The bundled .trellis/scripts/ tooling is not the Beamlet backend.

The [Nix development shell](../../../nix/devShell.nix) sets repository-local
CARGO_HOME. Local Cargo registries, caches, target output, and advisory databases
can dwarf the application tree. Use Git-tracked inventory and scoped source
reads when looking for local patterns; dependency source is not product code.
