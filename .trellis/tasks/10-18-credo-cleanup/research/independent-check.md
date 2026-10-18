# Independent check: Credo cleanup (durable/storage)

Reviewer: `trellis-check` sub-agent (independent of the implementer).
Tree: `dev` + uncommitted working-tree refactor of 24 source/test files plus 24
added lines in `.trellis/spec/backend/quality-guidelines.md`.
Nothing was committed.

## Verdict: PASS

Every acceptance criterion that is runnable in this environment was reproduced
independently: both Credo commands exit 0 with zero findings, umbrella and storage
test counts equal the recorded baseline with identical generated contract-test
names, and every other gate (format, warning-fatal compile, Sobelow, gettext,
Dialyzer, durable e2e, named distributed) is green. No behaviour change and no
gate weakening was found. One documentation-only precision fix was applied (see
"Fixes").

## Per-area findings

### 1. Gate weakening: none

- No `.credo.exs` (checked: file absent).
- `grep -rn "credo:disable\|@dialyzer\|--ignore" apps/` → no matches.
- `git diff` adds exactly one `@moduledoc false` (the nested
  `Beamlet.Storage.ContractFixture.DriverFailureStub`, allowed by the task) and no
  suppression attributes, no config, no `mix.exs` change, no directory exclusion.
- Credo run with repository defaults (no CLI flags beyond `--strict`/`--all`,
  which only *add* checks).

### 2. Behaviour equivalence (production diff reviewed file by file)

`apps/beamlet_storage`:

- `operation_records.ex`: `fetch/2` body moved verbatim into `read_operation/2`
  inside the same `Transaction.read/1`; `description/1` `cond` → `if` over
  `description_shape_valid?/1` with the same predicate order and short-circuit
  (`plain map` → non-empty → key subset → required keys → plain-map payload →
  `protocol_version >= 1`); the redundant trailing `with` clause became a direct
  `Records.json/2` return (same `{:ok, _kind}` guard first); `batch_operations/1`
  keeps reduce order, halt/cont semantics and the final reverse;
  `write_evidence/2` keeps the same changeset, `unique_constraint` name and error
  passthrough, and the stored-evidence digest comparison is now a head match on
  `%ExecutionEvidence{digest: digest}` against the same value (equivalent to
  `digest == input.digest`); `do_accept/3` and `accept_history/3` preserve the
  `Records.insert/2` error value and the `seq > 0 and seq <= agent.history_seq`
  reservation condition, and still pass `generation` from `input.agent`.
- `history.ex`: `event/3`/`operation/2` bodies moved into helpers inside the same
  read transaction; `read_events/3` rebuilds the query through
  `filter_through/types/turn/operation/origin` in the original order with the same
  `nil` guards (`[]`/`0` remain truthy and still apply their filter, because the
  new clauses match `nil` explicitly); `take_rows/6` `cond` → `if/else` with
  identical branches.
- `executor_journal.ex`: `fetch/3` helper extraction inside the same read
  transaction; `write_stop/2` and `write_terminal/2` split into
  `stop_query/1`/`terminal_query/1` (bucket-for-bucket identical `from(...)`,
  same `where` CAS on `lock_version`, same `update: [set: ...]`) plus
  `stop_conflict/2`/`terminal_conflict/2` with the identical three/two `case`
  clauses, `same_terminal?/2` and comments. `repo.update_all(query, [], log: false)`
  is still the only write.
- `admission.ex`: `probe/1` `cond` → `if state.reason != nil` (same branches);
  the SQL probe moved to `rollback_probe/1` but `Transaction.write/1`, both
  rollback atoms and the `rescue`/`catch` remain on `write_probe/1`, so probe
  exceptions still map to `:storage_unavailable`.
- `agent_records.ex`: `fetch/2` helper inside the same read transaction;
  `adoption_owner/3` single-clause `with`+`else` → `case` on `Records.get/3`
  (which only returns `{:ok, record} | {:error, :conflict}`), and the acceptance
  test is the same conjunction (`owner matches and accepted_result not nil`).
- `host.ex`: `open/1` reducer closure → `open_dataset/2` with the `nil`-opts
  clause first, same `Dataset.open/2` outcomes and same `Map.put`/`[reason | refused]`
  accumulation.
- `terminal_artifacts.ex`: `content/2` returns `decode_item/1` directly (same
  value); item size/digest checks moved to `validated_content/3` in the original
  order with the same `:limit`/`:invalid_data` atoms.
- `mix/tasks/beamlet.storage.migrate.ex`: alias only.

`apps/beamlet_runtime`:

- `admission/9 → admission/2`: the nine positional arguments travel in one
  internal map built by `admit_request/8`; every field is read back for the same
  decision — `key = {coordinator, attempt}`, `remaining_budget(remaining, lease)`
  (so lease-age reduction is unchanged), the three `cond` branches, the three
  `send(coordinator, {:rejected, attempt, reason})` payloads, `remember/3`,
  `claim_start/4` (same `valid_durable?` gate, `:durable_unavailable`,
  `:duplicate_admission`, then `start_intent/2`) and `admit/6`. No public function
  changed; the map is built and consumed inside the gateway.
- `claim_start/4` `cond` → `if valid_durable?` with the same two outcomes;
  `digest_matches?/2` `with` → `description = ...` + `case Codec.digest/2`, same
  `==` comparison, `_ -> false` and `rescue`.
- `runtime.ex`, `operation_coordinator.ex`, `persistence.ex`: `Beamlet.Storage.*`
  aliases only; every call arity and error atom (`:durable_not_admitted`,
  `:storage_unavailable`, `:storage_outcome_unknown`) unchanged.

`apps/beamlet_agent`:

- `advance_raw/9 → advance_raw/8`: the two command fields travel as
  `%{params: ..., command_id: ...}`; `command(scope_id, command_id, params)` is
  still called with the same argument order, and `adoption` keeps its
  `Map.put(attrs, :adoption, adoption)` behaviour. All call sites audited:
  `record_risk_accepted` (`%{"risk" => %{"accept" => true}}` + `command_id`, `nil`
  adoption), `resolve` (`params` map + `command_id`, real adoption), and `block/1`
  still uses the separate 6-arity clause that writes no command. The removed
  `advance_raw/8` was only a `nil`-adoption delegator, so its body is now the
  `nil`-adoption path of the new clause.
- `record_reply/2`, `consume_result/2`: the trailing bare assignment moved from the
  `with` head into the body; `with` still ends in `<-` and every failure value is
  still returned unchanged.
- `dependencies/1`: the last `with` clause (`:ok <- artifacts(...)`) became the
  body expression, same result.
- `pending_state/2`: `Enum.reduce_while` closure → `pending_entry_state/3` +
  `accepted_entry_state/1`; same `:cont :ok` / `:halt {:blocked,
  :unconfirmed_tool_result}` / `:halt {:blocked, :missing_operation}` outcomes and
  same accumulator match on `:ok`.
- `consumptions/1`: closure → `consumption_entry/2` + `reverse_ok/1`, same
  duplicate/dekind checks, same `Enum.reverse`.
- `server.ex`: `valid_keyword_options?/2` complexity split into
  `valid_option_keys?/1`, `valid_delegator?/1`, `valid_durable_pair?/1`,
  `valid_tools?/1` preserving the original evaluation order (`keys → id →
  delegator → durable/restored/durable_pair → binding_validator → tools`);
  `complete_tool` nesting extracted to `apply_consumption/2` with the same
  `commit_consumption` branches, `send(self(), {:advance, ...})` ordering and
  `Display.annotate` publish; `durable_input` `unless/else` → `if/else` with the
  branches swapped (equivalent).
- `trace_export.ex`: nested `with`s in `write/2` flattened into one `with`
  (identical success/failure passthrough, manifest write stays after all three
  streams), `page/3`, `checkpoint_pages/3` and `copy_artifacts/2` inner branches
  extracted (`continue_events/3`, `continue_checkpoints/3`,
  `copy_artifact_entry/4`, `omitted_artifacts/1`) keeping cursor/conflict/omission
  logic identical; `manifest_shape/1` split into three all-`:invalid_data`
  predicates, with `is_map(manifest["scope"])` still guaranteed before
  `manifest["scope"]["id"]` is read; `verify_artifacts/2` closure →
  `verify_artifact/3` + `verify_artifact_bytes/3` with the same
  `:artifact_missing`/`:artifact_size`/`:artifact_digest` reasons and count.

`apps/beamlet_daemon/lib/beamlet/daemon.ex`: alias only.

`history.ex` (Agent `dispatch/5`): bare assignment moved into the `with` body;
same snapshot/data access.

Net: no schema, migration, `mix.lock`, query, CAS/lock_version, transaction
boundary, admission probe, terminal/evidence decision, return value or error atom
changed. No side effect was reordered: the only reorderings are pure predicate
grouping (all-`:invalid_data` manifest checks) and branch inversion for
`unless/else → if/else`.

### 3. Test integrity: preserved

- No test removed, no assertion text weakened. The only two `assert` lines
  touched are pure alias substitutions
  (`Beamlet.Runtime.Directory.snapshots()` → `Directory.snapshots()`,
  `Beamlet.Agent.TraceExport.verify(dir)` → `TraceExport.verify(dir)`); all other
  test-file diff lines are `alias` additions/reordering and the `@moduledoc false`
  allowance.
- `storage_contract_test.exs`: the long `quote` was split into six named
  fragments (`common`, `fixture_helpers`, `attribute_helpers`, `durability_tests`,
  `atomicity_tests`, `receipt_tests`, `boundary_tests`) composed in the original
  order inside `__using__`; `bind_quoted` was replaced by `unquote(backend)`, so
  `@moduletag(:postgres_db)` and `@backend` still resolve to the same values.
- Generated test names verified identical by capturing `--trace` output before
  (`git stash`) and after the refactor: 132 unique names, byte-identical after
  stripping timings; the only textual differences are source line numbers
  (`[L#526]/[L#530]` instead of `[L#490]/[L#494]`) caused by the file split.
- Counts equal baseline: umbrella 439 passed / 49 excluded, storage suite
  59 passed / 13 excluded, both before and after.

## Commands run (verbatim results)

All from the repository root with `export ERL_FLAGS='+S 2:2'`.

| Command | Exit | Result |
| --- | --- | --- |
| `mix credo` | 0 | `2548 mods/funs, found no issues.` |
| `mix credo --strict` | 0 | `found no issues.` |
| `mix credo --strict --all` | 0 | `69 checks on 197 files`, `found no issues.` |
| `mix format --check-formatted` | 0 | — |
| `mix compile --warnings-as-errors` | 0 | — |
| `mix test --seed 631927` | 0 | 439 passed / 49 excluded (per-app: 35, 28, 15, 59/13, 53/6, 70, 68/20, 13/4, 25/1, 73/5) |
| `mix test apps/beamlet_storage/test --seed 631927` | 0 | 59 passed / 13 excluded |
| `mix sobelow` | 0 | `SCAN COMPLETE` |
| `mix gettext.extract --check-up-to-date` | 0 | only the pre-existing "same :priv directory" Gettext backend warnings |
| `mix dialyzer` | 0 | `Total errors: 0, Skipped: 0` (`PLT is up to date!`, no refresh) |
| `bash scripts/deployment/durable-e2e.sh` | 0 | phase 1 `1 passed, 2 excluded`; phase 2 (new OS process) `1 passed, 2 excluded`; evidence dir printed |
| named distributed suite (unique `--sname`, random cookie) | 0 | 33 passed: `beamlet_runtime 6`, `beamlet_node 20`, `beamlet_daemon 2`, `beamlet_web 5` |
| `git diff --check` | 0 | — |
| `git diff -- mix.lock scripts config apps/*/mix.exs` | — | empty |

Baseline Credo measured independently by stashing the refactor and re-running:

| Command (baseline) | Exit | Findings |
| --- | --- | --- |
| `mix credo --format=json` | 12 | 44 (41 refactor + 3 readability) |
| `mix credo --strict --all --format=json` | 14 | 106 (58 design + 41 refactor + 7 readability) |

### Preserved failed run (environment artifact, not a regression)

The first `mix dialyzer` invocation exited 1 with `Could not get Core Erlang code`
on 24 `beamlet_web`, 2 `beamlet_storage` and 1 `beamlet_agent` beams. Cause: that
run overlapped a concurrent `mix gettext.extract --check-up-to-date`, whose
`compile --force-elixir` rewrote exactly those 24 web / storage beams in the same
`_build/dev` directory while Dialyzer was reading them. Re-running Dialyzer alone
on the unchanged tree passed with 0 errors. The failure is recorded here rather
than deleted, per the repo's log-preservation rule.

## Scope

- `git diff --name-only`: only `apps/beamlet_agent`, `apps/beamlet_runtime`,
  `apps/beamlet_storage`, `apps/beamlet_daemon` (one alias) and
  `.trellis/spec/backend/quality-guidelines.md`.
- No `beamlet_web`, `beamlet_i18n`, `beamlet_cli`, `beamlet_node`,
  `beamlet_actions`, `beamlet_harness` file touched; no `mix.lock`, `scripts/`,
  `config/` or `apps/*/mix.exs` change; no schema or migration file change.
- No public API/module rename: the only new definitions are `defp` helpers and one
  internal map (`admit_request/8`).

## Fixes applied by this check

1. `.trellis/spec/backend/quality-guidelines.md` — the new Credo gate paragraph
   said "the initial cleanup run recorded 106 findings (exit 12 default, 14
   strict)", which could be read as 106 findings under the default profile. It now
   states the measured facts: 44 findings under the default profile (exit 12) and
   106 under `--strict --all` (exit 14). Content of the rule itself was kept: it is
   accurate (both commands currently exit 0 with no findings, suppression is
   absent, test counts match).
2. No code fix was needed. Re-verified after the edit: `mix credo` = 0,
   `mix credo --strict --all` = 0, `mix format --check-formatted` = 0,
   `git diff --stat` = 25 files (771 insertions / 616 deletions, the extra line
   being the doc sentence).

## Explicitly NOT verified

- Releases (`mix release`, `check-release.sh`, `check-named-release.py`): out of
  scope for this review because no manifest, runtime config, closure or deployment
  script changed. No release evidence is claimed.
- Browser/UI behaviour: no Web asset, HEEx or JS file changed; no browser run.
- PostgreSQL adapter contract half: the 13 excluded storage tests include the
  `:postgres_db` tag; no isolated PostgreSQL cluster was started, so
  `ContractSuite` was executed only on real SQLite files. The PostgreSQL-only
  fixture paths (`reject_downgraded/1`, `driver_failure/1` postgres clause,
  `settings/1` sampling) are alias/helper-only diffs and are unexercised here.
- Physical multi-host deployment and paid/live provider execution: not attempted;
  the distributed evidence is same-host named-VM automation only.
- LSP diagnostics: not used as evidence.
