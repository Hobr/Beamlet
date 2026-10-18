# Agent Core implementation report

Implementation checkout: `/mnt/data/Project/Beamlet`, branch
`refactor/agent-core-extraction`, HEAD
`a18f3c7488e08c13a4fc324e602e0a75d67e20bf`. No worktree, reset, checkout,
commit, merge, rebase or push. Product changes were made only by this child.

## Change inventory

- `apps/beamlet_agent/test/beamlet/core_adapter_test.exs`
- `apps/beamlet_agent_core/.formatter.exs`
- `apps/beamlet_agent_core/README.md`
- `apps/beamlet_agent_core/lib/beamlet/agent/core/context.ex`
- `apps/beamlet_agent_core/lib/beamlet/agent/core/data.ex`
- `apps/beamlet_agent_core/lib/beamlet/agent/core/decision.ex`
- `apps/beamlet_agent_core/lib/beamlet/agent/core/reducer.ex`
- `apps/beamlet_agent_core/mix.exs`
- `apps/beamlet_agent_core/test/core_test.exs`
- `apps/beamlet_agent_core/test/test_helper.exs`
- `.trellis/spec/backend/agent-durable.md`
- `.trellis/spec/backend/directory-structure.md`
- `.trellis/spec/backend/index.md`
- `apps/beamlet_agent/README.md`
- `apps/beamlet_agent/lib/beamlet/agent/context_builder.ex`
- `apps/beamlet_agent/lib/beamlet/agent/durable.ex`
- `apps/beamlet_agent/lib/beamlet/agent/reducer.ex`
- `apps/beamlet_agent/lib/beamlet/agent/server.ex`
- `apps/beamlet_agent/mix.exs`
- `mix.exs`

Task artifacts were supplied by the parent. This child additionally updates
`implement.md` progress and this `research/implementation-report.md`.

## Implementation notes

Core depends directly on Harness/Jason only and has no Application callback.
Reducer semantics moved without changing state keys, event/reducer/checkpoint
versions or persistence encoding. The Agent adapter retains Storage.Events,
Codec UUID/envelope/limits and canonical digest validation. The input digest is
transient normalized data, never persisted as a new state/event field.
Core UUID binary parsing has explicit compatibility vectors against the unchanged
Codec/Ecto validator; the adapter still uses Ecto-backed UUID validation.

ContextBuilder retains History/Loader/Inheritance and OperationRecords reads and
verification. Core receives source-bound materials, verifies ordered membership,
completeness, operation identity and resolution association, and converts messages.
Mixed input/operation materials refuse to prevent message substitution. Stored
model replies retain historical catalogue validation. Current catalogue validation,
complete-boundary semantics, inherited sources, fork risk and exact-limit assertions
are preserved. Explicitly repeated selected timeline occurrences remain supported:
existing tests require 128 repeated small inputs to succeed and repeated large inputs
to return context_limit. Extra/duplicated materials beyond selected occurrences fail.

Decision contains existing reply position, resume action/classification and safe-fork
logic actually called from Server/Durable. Storage transactions, CAS, prepared/
accepted/consumed separation, command unknown-outcome reconciliation, fixed-request
recovery and owner retirement code are unchanged. Manual diff review confirmed
preflight returns only :ok/error and formal projections still replay committed
response events in Durable.committed/2.

## Validation evidence (fresh runs only)

- Baseline `mix test apps/beamlet_agent/test --seed 631927`: 104 passed,
  `/tmp/agent-core-baseline.log`.
- Final focused `ERL_FLAGS='+S 2:2' mix test apps/beamlet_agent_core/test apps/beamlet_agent/test --seed 631927`:
  Core 7 + Agent 106 passed, `/tmp/agent-core-focused-final-3.log`.
- No-start pure/adapter run with `mix test --no-start apps/beamlet_agent_core/test apps/beamlet_agent/test/beamlet/core_adapter_test.exs --seed 631927`:
  7 + 2 passed, `/tmp/agent-core-pure-final-4.log`.
- Isolated PostgreSQL 18.6 initialized under `/tmp/agent-core-pg`, Unix socket,
  port 55983/user kanade. Final `BEAMLET_AGENT_TEST_ADAPTER=postgres
  BEAMLET_PG_SOCKET_DIR=/tmp/agent-core-pg BEAMLET_PG_PORT=55983
  BEAMLET_PG_USER=kanade ERL_FLAGS='+S 2:2' mix test
  apps/beamlet_agent/test/beamlet/durable_agent_test.exs
  apps/beamlet_agent/test/beamlet/fork_test.exs
  apps/beamlet_agent/test/beamlet/history_export_test.exs --seed 631927`:
  78 passed, `/tmp/agent-core-postgres-final.log`.
- `BEAMLET_BACKEND_BUILD=1 ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors`:
  passed, `/tmp/agent-core-backend-final.log`.
- Warning-fatal root compile passed, `/tmp/agent-core-compile-final.log`.
- Strict Credo passed without suppression, `/tmp/agent-core-credo-final-2.log`.
- `bash scripts/deployment/check-local.sh` under the isolated PG variables:
  `/tmp/agent-core-check-local-3.log`, evidence `/tmp/beamlet-acceptance.QYJ2am`.
  Full ordinary suite: 512 passed, 37 excluded. This run began before the final
  mixed-material guard; final focused and PG runs cover that guard.
  Named/static/release/e2e completion is recorded below when available.

## Failed/intermediate evidence retained

- `/tmp/agent-core-focused-1.log`: 103/104 Agent passed; duplicate-selected-timeline
  rejection broke the existing exact-limit assertion. Corrected, assertions unchanged.
- `/tmp/agent-core-credo-1.log`: four extraction findings, fixed by refactoring.
- `/tmp/beamlet-acceptance.hsZB3X`: first full invocation lacked PG socket environment;
  20 PostgreSQL fixture failures, not product failures. Fresh isolated cluster added.
- `/tmp/agent-core-pg/server.log`: first PG start failed due empty -h shell argument;
  corrected start uses quoted empty host, `/tmp/agent-core-pg/server-2.log`.
- `/tmp/agent-core-focused-final.log` and `/tmp/beamlet-acceptance.kcQnPH`:
  strict JSON-only observation hardening broke memory Result atom reasons, including
  uncertainty classification/Node flows. Corrected to preserve Jason-supported atom
  reasons and uncertainty precedence, with a dedicated pure regression. The final
  fresh focused/PG/full runs above supersede those results.

## Residual risks and review focus

Independent review is pending. Context now loads the selected verified material set
before converting messages; unusually malformed sources combined with an earlier
context overflow may expose a different error first. No existing assertion was
removed or weakened. Harness has Req transitively; Core itself calls only pure
validators and Jason. Same-host named/release evidence does not claim physical-host
acceptance. Old erased implementation runs provide no acceptance evidence.


## Additional completed gates

- Named umbrella: 35 passed, 514 excluded; per-app results in
  `/tmp/beamlet-acceptance.QYJ2am/distributed.log` (Runtime 7, Node 20,
  Server 2, Web 5, CLI 1). Same-host isolated named peers only.
- Ordinary results: 512 passed/37 excluded (parsed sum, correcting earlier
  arithmetic in intermediate progress updates).
- Root format/warning-fatal compile/default Credo/strict Credo passed via check-local.
- Dialyzer passed: 0 errors/skips; automatically added 12 modules to the existing
  PLT for the extraction, without a forced PLT rebuild. See `dialyzer.log`.
- Sobelow passed (`sobelow.log`), catalogue check passed (`gettext.log`),
  xref cycles check passed (`cycles.log`), PTY reader passed (`pty-reader.log`).
  Gettext emits existing duplicate-backend warnings during extraction; no drift.
- Backend default/server/CLI releases and production Web compile/assets/digest/release
  built under `_build/host-naming.NZVAxJ`; corresponding `build*.log`,
  `compile-prod.log`, `tailwind.log`, `esbuild.log`, `digest.log` record results.
- Isolated pure tests ran using only Core/Harness/Jason beam paths (no umbrella
  startup and no Agent/Runtime/Storage/Ecto on the provided paths):
  `ERL_FLAGS='+S 2:2' elixir -pa _build/test/lib/beamlet_agent_core/ebin
  -pa _build/test/lib/beamlet_harness/ebin -pa _build/test/lib/jason/ebin
  -r apps/beamlet_agent_core/test/test_helper.exs
  apps/beamlet_agent_core/test/core_test.exs`: 7 passed,
  `/tmp/agent-core-isolated.log`.

## Final integrated result

`check-local.sh` exited successfully and printed `Integrated local checks complete`
in `/tmp/agent-core-check-local-3.log`. Its copied release checks passed native
Server launch/RPC/pid/stop/observed exit, default/authority/executor startup modes,
authority bootstrap to executor and an actual deterministic Gateway turn, all nine
invalid-host cases, copied CLI closure/three independent stdin sessions/same Ref
on reattachment, and copied Web secret rejection/native controls/HTTP/CSS/JS.
Copied manifest and tree hashes are retained in
`/tmp/beamlet-acceptance.QYJ2am/copied/` (server tree manifest hash
`8f362dc258788c371a64f0d36d3d235bdb7f4d018ee114c569518efe3142d5a5`).

`bash scripts/deployment/durable-e2e.sh` passed both independent OS-process phases
(1 test each), evidence `/tmp/beamlet-durable-e2e-q9kUXb`, log
`/tmp/beamlet-acceptance.QYJ2am/durable.log`. Missing Web secret rejection,
whitespace and Python cleanup regressions passed (`web-secret.log`,
`whitespace.log`, `python-cleanup.log`). No verification gate was silently dropped.
Root format check passed again after final source changes
(`/tmp/agent-core-format-final.log`). All final source changes are included in the
built/copied artifacts and final focused/PG runs; the full ordinary process began
before the final material-key guard as noted above. No source changed after those
final focused runs or the release builds.

The task-owned PostgreSQL server is stopped after verification; its directory and
logs remain outside the repository. No files were staged. No existing test file
was edited, no assertion removed, no suppression introduced. Independent review
and parent acceptance/commit/archive remain pending.

Suggested logical commit scope for the parent: one coupled extraction commit
covering Core application, Agent adapters/decision call sites, regression tests,
and boundary documentation. No storage schema/migration or lockfile change exists.

## Review-fix evidence supersedes initial implementation limitations

The broad 512 ordinary/35 named/copied-release/e2e results above describe the initial
extraction baseline. Independent review then requested F1–F3 changes. The previous
bulk-context first-error limitation is fixed by incremental conversion between
reads. Event/replay/material wrappers no longer consume domain nesting budgets;
normalized inherited-source validation is hardened. Final fix-specific inventory,
regressions, commands, log paths and remaining review status are in
`research/fix-report.md`. The earlier broad release suite is not claimed as a fresh
run after these fixes. Parent review/commit/finish steps remain pending.
