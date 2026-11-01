# Baseline Evidence and Feasibility Gates

## Evidence Status

This note captures the repository snapshot and prior discussion, not new
engine benchmark results. Current baseline: e06b2d5 on dev, inspected during
task creation on 2026-11-01. No backend spike or recovery test has run.

The user's explicit decision is to freeze the design and choose Rune for the
first Codemode implementation. Task creation permits documentation only.

## Repository Facts

- Cargo.toml lists apps/console, apps/node, and crates/lib.
- crates/lib/Cargo.toml has no dependencies; its source is the generated add
  example. There is no existing durable backend to preserve or claim as working.
- apps/node depends on beamlet-lib and still prints Hello, world.
- apps/console depends on futures, Tokio, color-eyre, crossterm, ratatui,
  and beamlet-lib. Root declarations alone do not implement console commands.
- The root declares rune 0.14, rquickjs 0.14, Wasmtime, RMQTT, SeaORM,
  BLAKE3, UUID, metrics, and test-library candidates.
- UUID now explicitly enables serde. The direct libp2p dependency from an
  earlier snapshot is absent; do not report the old 0.57 declaration as current.
- sea-orm-migration is not declared in the current root manifest.
- justfile builds Node and Console, checks the workspace, runs nextest, and
  uses prek. prek.toml defines Rust formatting/check/clippy/test and license
  gates. Do not run the update recipe as part of this task.
- .trellis/spec/backend/*.md are largely unfilled templates. The separate
  bootstrap-guidelines task is not this task's implementation target.

## Agreed Architectural Constraints

- Keep Operation/Attempt/Report generic; Codemode calls use the same model.
- Host-supplied provenance is not permission or lifecycle inheritance.
- One role actor coordinates many tracked execution tasks.
- Unknown effects are not ordinary failure; cancellation does not undo effects.
- Local transactions commit delivery responsibility with the owning decision.
- Recover facts rather than serialize guest stacks.
- Node/Console first; Agent/Harness and graphical clients are deferred.
- Only Kameo remote is implemented as the first network adapter.
- Rune is selected; rquickjs/Nova are not parallel delivery targets.

## Rune Primary References and What They Do Not Prove

- [Rune async guide](https://rune-rs.github.io/book/async.html)
- [Rune sandboxing guide](https://rune-rs.github.io/book/sandboxing.html)
- [Rune module API](https://docs.rs/rune/latest/rune/struct.Module.html)
- [Rune VM API](https://docs.rs/rune/latest/rune/struct.Vm.html)

These describe available mechanisms, not an end-to-end durable host.
Recheck the APIs against the exact resolved 0.14 version before writing code.
Required new evidence is synchronous call initiation, controlled completion
readiness, generation fencing, replay-prefix matching, and effective limits.
Native async support alone proves none of these.

## Persistence and Transport References

- [SeaORM migration setup][migration-setup]
- [SeaORM migration execution][migration-run]
- [Kameo 0.22.0 remote implementation][kameo-remote]
- [Kameo 0.22.0 Swarm implementation][kameo-swarm]

The local sea-orm-cli version previously checked was 2.0.4. Installing that
binary does not supply a Rust dependency to project migration code.
Generated migrations still depend on sea-orm-migration. Runtime migration must
work without the CLI being installed on deployment machines.

The researched Kameo remote implementation uses a process-global Swarm.
Persist network identity and initially use separate Node subprocesses.
Revalidate against the actual lockfile version; never infer network/bootstrap
or durable acceptance guarantees solely from remote ask/tell.

## Review Boundaries

Complete transparent replay, exactly-once external effects, and adversarial
isolation remain unproven and are not release claims. Preserve unknowns and
reject divergence rather than inventing successful recovery. Any failure of
the Rune feasibility gate requires review, not silent contract weakening.

[migration-setup]: https://www.sea-ql.org/SeaORM/docs/migration/setting-up-migration/
[migration-run]: https://www.sea-ql.org/SeaORM/docs/migration/running-migration/
[kameo-remote]: https://github.com/tqwewe/kameo/blob/v0.22.0/src/remote.rs
[kameo-swarm]: https://github.com/tqwewe/kameo/blob/v0.22.0/src/remote/swarm.rs
