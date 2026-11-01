# Console Guidelines

Read this layer when changing apps/console/. The current application is a
counter TUI, not a Codemode client or backend administrator.

## Before Development

1. Read [event flow and state ownership](event-loop.md).
2. Read [error handling and terminal lifecycle](error-handling.md).
3. Use the shared [quality guidelines](../backend/quality-guidelines.md).
4. For package changes, read [workspace structure](../backend/directory-structure.md).

## Source Map

| Source | Owner |
| --- | --- |
| [main.rs](../../../apps/console/src/main.rs) | Tokio runtime, error reporting, terminal lifecycle |
| [app.rs](../../../apps/console/src/app.rs) | App state, event dispatch, key-to-action translation |
| [event.rs](../../../apps/console/src/event.rs) | Event types, receiver, tick/input producer |
| [ui.rs](../../../apps/console/src/ui.rs) | Widget implementation for borrowed App |

The [Console manifest](../../../apps/console/Cargo.toml) defines the actual
terminal dependencies. Root declarations of CLI/REPL libraries do not establish
implemented command parsing or interactive modes.

## Quality Check

Trace any changed event through producer, dispatch, state, and rendering.
Check the returned-error and terminal-cleanup path separately.
Use the [cross-layer guide](../guides/cross-layer-thinking-guide.md) when a
change spans these boundaries. Read known scaffold limitations in the two
topic guides before reusing their concurrency or error behavior elsewhere.
