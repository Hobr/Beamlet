# F1–F3 implementation fixes

Scope: authorized primary checkout `/mnt/data/Project/Beamlet`, branch
`refactor/agent-core-extraction`, HEAD `a18f3c7488e08c13a4fc324e602e0a75d67e20bf`.
All findings are implemented and ready for fresh independent focused recheck;
parent review/acceptance/commit/finish remain pending. No parent checklist step was
marked complete by this fix pass.

## Findings resolved

- **F1**: ContextBuilder verifies one source, calls pure incremental conversion/append,
  and stops on its error before reading another. Core's accumulator checks exact next
  selected occurrence and material identity/shape/resolution before conversion. It
  stores reversed bounded messages and encodes each new message once, with JSON list
  brackets/comma accounting identical to the prior append limit. There is no repeated
  DB traversal or quadratic full-context rebuilding. Final request/current catalogue
  validation runs only at completion; incomplete tool-pair prefixes remain supported.
  Batch APIs use the same accumulator. New Repo-protocol regressions assert both
  errors and actual read counts: overflow returns context_limit at read16, including
  missing/corrupt/valid suffix variants, and invalid historical model reply returns
  invalid_reply after four total verification reads (two operation event reads),
  with zero suffix reads. Both build/materialize facades are exercised.
- **F2**: Event envelope validation excludes payload before independently validating
  that payload at depth32. Replay checks list properness without charging a list
  wrapper against each event. Material/source/input/operation domain values are
  validated independently, with description/result checked at their own roots.
  Added Codec/facade/direct-Core decode/reduce/replay boundary parity at depths31/32
  and refusal at33; improper lists, PIDs/functions reject safely. Material description
  and result root32 pass despite their containers; root33 rejects.
- **F3**: Inherited input/result entries now require exact normalized keys, canonical
  UUID/digest fields, positive sequence fields, exact consumed reference kinds and
  recorded resolution shapes. Evidence-resolution kind and resolution presence must
  agree. Existing source-in-closure/count checks remain; all existence, ownership,
  content digest, acceptance/preparation linkage and closure I/O stay outside Core.
  Nonempty valid input/result and resolved-result manifests preserve paused fork risk
  and do not inherit pending/consumed work. Malformed/missing/extra field vectors
  reject before traversal. Actual PostgreSQL and SQLite fork/history regressions pass.
- Index grammar corrected from “a eleven” to “an eleven”. Relevant boundary docs now
  describe incremental conversion and independent domain depth budgets.

## Files changed in this fix pass

- `apps/beamlet_agent/lib/beamlet/agent/context_builder.ex`
- `apps/beamlet_agent_core/lib/beamlet/agent/core/context.ex`
- `apps/beamlet_agent_core/lib/beamlet/agent/core/data.ex`
- `apps/beamlet_agent_core/lib/beamlet/agent/core/reducer.ex`
- `apps/beamlet_agent/test/beamlet/context_read_order_test.exs`
- `apps/beamlet_agent/test/beamlet/core_adapter_test.exs`
- `apps/beamlet_agent_core/test/core_test.exs`
- `apps/beamlet_agent_core/README.md`
- `.trellis/spec/backend/agent-durable.md`
- `.trellis/spec/backend/index.md`
- `.trellis/tasks/10-18-agent-core-extraction/research/implementation-report.md`
- `.trellis/tasks/10-18-agent-core-extraction/research/fix-report.md`

## Fresh validation

Commands run from umbrella root with `ERL_FLAGS='+S 2:2'` unless noted:

| Command | Result | Log |
| --- | --- | --- |
| `mix test apps/beamlet_agent_core/test apps/beamlet_agent/test --seed 631927` | Core10 + Agent109 passed | `/tmp/core-fix-focused-final.log` |
| `mix test --no-start apps/beamlet_agent_core/test apps/beamlet_agent/test/beamlet/core_adapter_test.exs apps/beamlet_agent/test/beamlet/context_read_order_test.exs --seed 631927` | Core10 + adapter/read-order5 passed | `/tmp/core-fix-no-start-final.log` |
| Isolated `elixir -pa _build/test/lib/beamlet_agent_core/ebin -pa _build/test/lib/beamlet_harness/ebin -pa _build/test/lib/jason/ebin -r apps/beamlet_agent_core/test/test_helper.exs apps/beamlet_agent_core/test/core_test.exs` | Core10 passed, no umbrella application startup | `/tmp/core-fix-isolated-final.log` |
| `mix test apps/beamlet_agent/test/beamlet/durable_agent_test.exs apps/beamlet_agent/test/beamlet/fork_test.exs apps/beamlet_agent/test/beamlet/history_export_test.exs --seed 631927` with PostgreSQL variables below | 78 passed | `/tmp/core-fix-postgres-final.log` |
| `mix compile --warnings-as-errors` | passed | `/tmp/core-fix-compile-final-2.log` |
| `BEAMLET_BACKEND_BUILD=1 mix compile --warnings-as-errors` | passed | `/tmp/core-fix-backend-final.log` |
| `mix format --check-formatted` | passed | `/tmp/core-fix-format-final.log` |
| `mix credo --strict --all` | no issues | `/tmp/core-fix-credo-final-2.log` |
| `mix dialyzer` | 0 errors/0 skips; existing PLT up to date, no refresh | `/tmp/core-fix-dialyzer-final-2.log` |
| `git diff HEAD --check` | passed | `/tmp/core-fix-whitespace.log` |

PostgreSQL uses task-owned `/tmp/agent-core-pg/data`, Unix socket
`BEAMLET_PG_SOCKET_DIR=/tmp/agent-core-pg`, `BEAMLET_PG_PORT=55983`,
`BEAMLET_PG_USER=kanade`, `BEAMLET_AGENT_TEST_ADAPTER=postgres`. Server stopped
following verification; retained datasets/logs remain outside the repository.

Earlier broad 512 ordinary/35 named/copied release/security/catalogue/two-process e2e
results remain initial-extraction evidence in implementation-report.md. They were
not rerun as final-fix evidence, per requested focused scope. Focused tests include
unchanged durable/fork/history assertions. No existing assertions were weakened.

## Intermediate diagnostics retained

`/tmp/core-fix-target-1.log` exposed a missing description_digest in the new model
fixture; fixed the fixture. `/tmp/core-fix-credo-1.log` recorded two nesting findings;
extracted small fold helpers. `/tmp/core-fix-no-start.log` recorded a test-helper
clause grouping warning; moved the helper after the grouped clauses.
`/tmp/core-fix-dialyzer*.log` retain unsuccessful analysis attempts. The redundant
is_map branch in a helper already called with a map caused the false-pattern warning;
a temporary @file diagnostic localized it (`/tmp/core-fix-diagnostic.log`). All
annotation changes were removed; the redundant condition was removed without
suppression. Final logs supersede these intermediate results.

## Workspace/index observation and residual risks

An index-only external change was observed during this pass: extraction/task files
became staged while final source edits remained unstaged. This child did not stage
anything. The supervisor confirmed they did not stage it and instructed preserving
the index and continuing authorized fixes. No attribution is made. Branch/HEAD and
source content remained expected; validation reviewed working-tree content using
`git diff HEAD`, not just the staged snapshot. Parent must reconcile the split before
commit. Snapshot inventories: `/tmp/core-fix-staged-inventory.log` and
`/tmp/core-fix-unstaged-inventory.log`. At report creation, unstaged modifications are:


This report is newly untracked; parent-owned task files and the earlier extraction
are among the staged paths. No index mutations, commit/archive, worktree operations,
or nested agents were performed by this child. Fresh independent recheck remains
required; no additional known product blocker remains from F1–F3. Optional differing
historical/current catalogue-schema coverage was not expanded in this pass; existing
historical-validation logic and integration assertions are preserved.
