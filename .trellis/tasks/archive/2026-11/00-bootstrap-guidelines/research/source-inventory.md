# Current Source Inventory

## Snapshot and Method

Read-only analysis at c71a6bc on dev. Git was clean before planning edits.
Inventory uses Git-tracked paths, current source/config reads, and CodeGraph's
current Console source bodies. No build, test, engine spike, graph rebuild, or
dependency installation was performed.

The cached pi-lens project graph was built at 87fd4578 and reported 73 percent
coverage. Its hub list is dominated by bundled Trellis tooling, so it was not
used as evidence of product architecture. Available tool discovery did not
expose GitNexus or ABCoder; direct reads are sufficient for this small source
tree. Ignore local Cargo registries/caches when identifying product ownership.

## Evidence Map

| Evidence | Observed behavior and documentation implication |
| --- | --- |
| Cargo.toml and three member manifests | Workspace metadata is inherited; candidate root dependencies are distinct from member use. |
| crates/lib/src/lib.rs | Generated add function and one inline unit test; no backend domain or runtime. |
| apps/node/src/main.rs | Hello-world entry point; no roles, database, transport, or script execution. |
| apps/console/src/main.rs:7-13 | Tokio main, color-eyre install, Ratatui init, App run, restore, returned Result. |
| apps/console/src/app.rs:33-68 | Draw, await event, key-press filtering, dispatch typed application events. |
| apps/console/src/app.rs:75-88 | No-op tick, quit flag, saturating counter mutation. |
| apps/console/src/event.rs:44-99 | Unbounded channel, runtime-dependent construction, OptionExt error conversion, deliberate ignored local send failure. |
| apps/console/src/event.rs:117-144 | Tokio select drives tick/input/closure; receiver closure ends producer; send failure during shutdown is ignored. |
| apps/console/src/ui.rs, Widget for &App | Rendering reads App through a borrowed widget implementation. |
| README.md and justfile | Supported development entry points; fmt runs hooks and update mutates tools/locks. |
| prek.toml | Actual formatting, cargo check/clippy/nextest, license, and file-hygiene gate definitions. |
| .editorconfig | UTF-8, LF, final newline, whitespace rules, file-type indentation. |
| rust-toolchain.toml, .cargo/config.toml | Pinned toolchain and Linux mold linker configuration; a Wasm target is not an implemented engine. |
| flake.nix, nix/devShell.nix | Standardized optional Nix environment; repository-local CARGO_HOME explains large ignored cache trees. |
| nix/packages/beamlet-console.nix and beamlet-node.nix | Per-package Cargo build/test flags and source/lock inputs; not proof that a build passed. |
| deny.toml and about.toml | Actual license configuration is authoritative; do not copy older dependency/license advice. |
| .github/dependabot.yml | Update configuration exists; no tracked product CI workflow was found. |
| AGENTS.md | Trellis routing; no independent local Rust convention document was found. |

## Spec Inventory Findings

- All six backend files are template scaffolding, including the index.
- guides/index.md is generic navigation without Beamlet routing.
- code-reuse-thinking-guide.md includes TypeScript and upstream Trellis paths.
- cross-layer-thinking-guide.md repeats unrelated template, docs-release, and
  marketplace examples. It should not imply Beamlet is the Trellis codebase.
- No implemented database/migration or tracing setup justifies separate
  backend database/logging rulebooks yet.
- Console application error behavior is concrete; move that topic under
  Console instead of inventing a library/domain error hierarchy.

## Limits That Must Not Become Rules

The Console producer JoinHandle is not retained, and the spawn result is not
propagated to App. The queue is unbounded. These are current scaffold facts,
not durability/backpressure recommendations.

Ratatui restore is called after App::run returns, including a returned error;
that alone does not establish panic-safe cleanup. EventHandler construction
requires a Tokio runtime. The only tracked product test found is the generated
library test; Console/backend coverage is not established.

Both binaries declare beamlet-lib as a dependency but currently do not call its
example API. Declared Rune/SeaORM/Kameo/tracing libraries are not initialized by
the inspected product source.

## Historical Context

The archived Rune-first task records a high-level engine/architecture direction,
with all experiments and implementation deferred:
.trellis/tasks/archive/2026-11/11-01-rune-durable-codemode/design.md

It may be linked as a future decision, never cited as a working implementation.
