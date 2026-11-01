# Bootstrap Beamlet Development Guidelines

## Goal

Replace generic Trellis scaffolding with concise English guidance grounded in
the current Beamlet source and build configuration. Future contributors should
know which code to extend without mistaking an architectural plan or a declared
dependency for implemented behavior.

## Authorization

The user approved the reviewed documentation plan and authorized writing and
static verification of the specs. Only spec documents and this task's records
may change. Product-code edits, runtime experiments, backend implementation,
and automatic commits remain out of scope.

## Confirmed Context

Baseline: c71a6bc on dev. The three workspace members are apps/console,
apps/node, and crates/lib. Console is a counter-TUI scaffold; Node and
the library remain generated examples. The archived Rune-first decision record
is a high-level future direction, not a source of implemented backend patterns.

At the inspected baseline, the backend files were empty templates and the
thinking guides contained unrelated upstream examples. No separate
contribution/convention document was found beyond AGENTS.md and build/config
files. See research/source-inventory.md for source evidence.

## Scope

- All project guidance under .trellis/spec/.
- Current Rust workspace structure, dependency inheritance, quality gates, and
  the implemented Console event/error/rendering boundaries.
- Source reads from apps/, crates/, root configuration, and Nix packaging.
- Removal or reshaping of template topics that do not match the repository.

## Requirements

- R1: Every important rule has a real source, configuration, test, or project
  document reference. Distinguish observed behavior from recommendations.
- R2: Document the current package boundaries and dependency usage without
  implying that Rune, SeaORM, Kameo, or tracing has been integrated.
- R3: Document Console's actual event flow, error propagation, terminal
  restoration path, and known scaffold limitations without blessing those
  limitations as general backend conventions.
- R4: Keep all navigation and relative links consistent with the final file
  set. Keep the spec tree small and avoid duplicated rules.
- R5: Remove template instructions, empty headings, unrelated examples, and
  unimplemented database/logging prescriptions.
- R6: Make no product, dependency, runtime, tooling, or agent-skill changes.
  Verify documentation statically; do not run Rust/VM/TUI experiments.

## Acceptance Criteria

- [x] A1 (R1, R2): Workspace and dependency guidance cites current manifests
      and clearly labels Node/library scaffolds and inactive candidates.
- [x] A2 (R1, R3): Console guidance traces actual startup, events, mutation,
      rendering, errors, and cleanup using current symbols and file paths.
- [x] A3 (R4): All spec files are reachable from indexes; all local links and
      source references resolve after the topic reshaping.
- [x] A4 (R5): No template placeholders, empty sections, or unrelated
      TypeScript/Trellis-product examples remain in .trellis/spec/.
- [x] A5 (R1, R5): No database, migration, logging, durable recovery, or engine
      behavior is presented as implemented without source evidence.
- [x] A6 (R6): Changes are limited to spec documents and this task's management
      artifacts; document checks do not modify product source or dependencies.

## Out of Scope

Rune feasibility work, backend APIs/schema implementation, new tests, Console
refactoring, dependency changes, CI/build-tool changes, Trellis runtime/skill
customization, graph installation/rebuilds, and committing or archiving this
task before the spec-writing work is reviewed and completed.

## Review Status

The user accepted the completed documentation result by requesting archival.
All acceptance criteria passed static verification; see
[verification results](research/verification.md). Product code, dependencies,
and earlier architecture records remain unchanged. No runtime checks or
experiments were run. Archive and session bookkeeping are authorized; the spec
changes and closure records remain uncommitted.
