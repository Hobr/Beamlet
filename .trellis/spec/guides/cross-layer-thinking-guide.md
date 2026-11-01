# Cross-Layer Changes

Use this guide when a change crosses Console events, package dependencies, or
build inputs.

## Console Event Changes

Trace a new action through its actual owners:

1. [event.rs](../../../apps/console/src/event.rs): typed Event/AppEvent and producer.
2. [app.rs](../../../apps/console/src/app.rs): key-to-action conversion and dispatch.
3. [ui.rs](../../../apps/console/src/ui.rs): borrowed rendering of updated state.
4. [main.rs](../../../apps/console/src/main.rs): returned errors and terminal cleanup.

Check whether the input is filtered, queued, mutated, and rendered where
expected. A key press queues an AppEvent for later dispatch; it is not a direct
state update. See the [event guide](../console/event-loop.md) rather than
duplicating the full loop here.

For an error-path change, follow the returned Result and explicit restoration
separately from background-task health. The latter has different
[limitations](../console/error-handling.md).

## Manifest and Build Changes

A package-boundary change can involve:

- [Root declarations](../../../Cargo.toml) and the consuming member manifest.
- [justfile](../../../justfile) package names and build/check recipes.
- [Console packaging](../../../nix/packages/beamlet-console.nix) or
  [Node packaging](../../../nix/packages/beamlet-node.nix).

The Nix definitions select a package for build/test and include root Cargo
manifests plus apps/ and crates/ as source inputs. If a real authorized change
moves required source elsewhere, check those inputs too. These packaging
definitions do not imply that every target or feature was tested.

Use the [quality guide](../backend/quality-guidelines.md) for checks appropriate
to the changed files. Treat environment setup and dependency updates as
separate maintenance, not prerequisites silently added to a docs task.

## Review the Full Boundary

Confirm that producer and consumer still share the same type and meaning,
that errors remain visible at their real boundary, and that build entry
points still reference the intended package. Preserve unrelated user changes.

There is no implemented network/schema/recovery boundary to trace yet;
consult the [current status](../backend/index.md#implementation-status) instead
of substituting hypothetical backend flows for the code being changed.
