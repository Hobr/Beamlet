# Spec Bootstrap Writing Plan

## Gate

The user approved this documentation-only plan. Execute the spec rewrite and
static checks with one owner. This does not authorize product-code edits,
runtime experiments, another backend task, or automatic commits.

## Ordered Work After Approval

- [x] Recheck current Git status and source/config changes since c71a6bc.
- [x] Confirm the approved topic map still matches the source.
- [x] Activate this existing task through the normal reviewed-workflow gate.
- [x] Write the root index and Rust workspace/directory guidance.
- [x] Write the Console event-loop and error-handling guides from inspected
      symbols, with short source examples and explicit scaffold limitations.
- [x] Write quality guidance from actual scripts/config, distinguishing command
      definitions from test or build results.
- [x] Replace generic thinking guides with concise Beamlet-specific guidance.
- [x] Remove obsolete backend database/logging/error templates and update all
      live navigation and references in the same documentation change.
- [x] Perform a claim-by-claim source review and the static checks below.
- [x] Update PRD acceptance only for outcomes actually verified.
- [x] Present the spec-writing result for review; do not automatically implement
      Rune or treat this as approval for another product task.

## Static Verification

- Parse task JSON and JSONL; validate manifest targets with task.py validate.
- Inventory every Markdown file under .trellis/spec/ and ensure the proposed
  indexes cover the final document set.
- Check local Markdown links and cited source paths.
- Search for unfilled-template markers, empty headings, irrelevant languages,
  and upstream-only file paths. Manually review matches rather than banning
  legitimate mentions of absent or deferred capabilities.
- Search live references to the removed spec paths; preserve archived history.
- Check discovery with get_context.py --mode packages.
- Run git diff --check and inspect the complete spec diff.
- Confirm that no apps/, crates/, Cargo*, Nix/build config, scripts, skills, or
  archived decision records were changed.

These are documentation checks, not runtime experiments. Do not run
cargo build/test, VM prototypes, interactive Console sessions, just fmt,
just update, dependency installation, or graph rebuilds for this task.

## Execution Boundary

Only .trellis/spec/ and .trellis/tasks/00-bootstrap-guidelines/ are write targets
during the writing phase. Normal session-journal/closure bookkeeping may follow
only after completion. Product code and frozen architecture records remain
unchanged. Do not stage unrelated user edits or create commits implicitly.

## Risk and Rollback

Sparse backend source is a documentation constraint: record what is absent,
rather than inventing patterns. Re-read source before writing if the repository
changes in another session. Treat source/scaffold defects as limitations to
describe, not bugs to fix under this task.

If the final spec map changes materially, revise the plan and return for review.
Restore moved topics and indexes as one coherent set if rollback is needed;
preserve user changes and avoid destructive Git commands.
