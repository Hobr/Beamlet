# Implementation handoff: Credo cleanup (durable/storage)

Task: `.trellis/tasks/10-18-credo-cleanup`
Scope: `apps/beamlet_agent`, `apps/beamlet_runtime`, `apps/beamlet_storage`,
`apps/beamlet_daemon` (production + tests). Refactor only, no behaviour change.

## Result

| Command | Before | After |
| --- | --- | --- |
| `mix credo` | exit 12, 41 refactoring + 3 readability | exit 0, no issues |
| `mix credo --strict --all` | exit 14, 41 refactoring + 7 readability + 58 design (106) | exit 0, no issues |
| `mix credo --strict` | exit 14 | exit 0 |

No `.credo.exs`, no `--ignore`, no directory exclusion, no rule downgrade, no
`# credo:disable-*` comment, no `@dialyzer` attribute was added. `git diff` shows
no `.credo.exs` and no `credo:disable` anywhere under `apps/`.

## Per-file refactors and why they are behaviour-equivalent

### apps/beamlet_storage (production)

- `lib/beamlet/storage/operation_records.ex`
  - `fetch/2`: the body of `Transaction.read/1` moved to `read_operation/2`
    (identical `case`); `Beamlet.Storage.Transaction` became an `alias`
    (`AliasUsage`). Transaction boundary and `log: false` unchanged.
  - `description/1`: the five-clause `cond` was replaced by `if` over
    `description_shape_valid?/1` + `plain_map?/1` + `valid_protocol_version?/1`.
    The checks are evaluated in the original order with the same short-circuit
    (`plain map`, non-empty, key subset, required keys, plain-map payload,
    protocol_version >= 1), so the same input yields the same
    `{:error, :invalid_data}` or `Records.json/2` result. The redundant trailing
    `with` clause was dropped by returning `Records.json/2` directly.
  - `batch_operations/1`: the `Enum.reduce_while` closure became
    `collect_batch_member/2` + `duplicate_batch_member?/2` + `reverse_batch/1`;
    same order of validation, same halt/cont semantics, same reversal.
  - `write_evidence/2`: the insert branch moved to `insert_evidence/2`
    (same changeset, same `unique_constraint`, same error passthrough) and the
    stored branch to `stored_evidence_result/2` (`%ExecutionEvidence{digest:
    digest}` matched against `input.digest` exactly like the previous `if`).
  - `do_accept/3`: the trailing `Records.insert/2` + body became
    `insert_accept_event/5`; the `with`-without-`else` error passthrough became a
    `case` with `error -> error`, so failures keep the same shape.
  - `accept_history/3`: the two `case` branches became `reserved_position/3`
    (same `seq > 0 and seq <= agent.history_seq` condition) and
    `advance_position/4` (same `Records.advance_agent_history/4` call with the
    same `generation` taken from `input.agent`).
- `lib/beamlet/storage/history.ex`
  - `event/3`, `operation/2`: the query/`case` bodies moved into `read_event/3`
    and `read_operation/2` inside the same `Transaction.read/1` closure.
  - `read_events/3`: the five `if`/`case` query refinements became
    `event_query/2` with `filter_through/types/turn/operation/origin`; the
    refinements are applied in the original order, each one only when its filter
    is present (filters come from the existing validators, which yield `nil` or a
    validated value).
  - `take_rows/6`: `cond` with a single condition + `true` became `if`/`else`
    with the identical branch bodies and comment.
- `lib/beamlet/storage/executor_journal.ex`
  - `fetch/3` → `read_attempt/3` inside the same read transaction.
  - `write_stop/2` split into `stop_query/1` (same Ecto query, same `where`,
    `update`), `stop_conflict/2` (same three `case` clauses) and a thin
    `update_all` caller. `write_terminal/2` split the same way into
    `terminal_query/1` + `terminal_conflict/2` (same `same_terminal?/2` and
    fallback comment). Query construction order and CAS conditions are byte
    equivalent.
- `lib/beamlet/storage/admission.ex`
  - `probe/1`: `cond` with one condition + `true` became `if state.reason != nil`
    / `else`, same branches.
  - `write_probe/1`: the SQL probe inside the `Transaction.write/1` closure moved
    to `rollback_probe/1`; the closure, the rollback atoms and the
    `rescue`/`catch` (still on `write_probe/1`, so exceptions from the probe still
    map to `:storage_unavailable`) are unchanged.
- `lib/beamlet/storage/host.ex`
  - `open/1`: the reducer closure became `open_dataset/2` with an explicit
    `{_role, {_repo, nil}}` clause (same "no opts → leave accumulator" behaviour)
    and a `case Dataset.open/2` clause with the same two outcomes.
- `lib/beamlet/storage/agent_records.ex`
  - `fetch/2` → `read_agent/2` inside the same read transaction.
  - `adoption_owner/3`: the single-clause `with`+`else` became `case` on
    `Records.get/3` (which only returns `{:ok, record} | {:error, :conflict}`);
    the `cond` became `adoption_owner_check/3` with `owner matches and
    accepted_result not nil` — the same acceptance condition.
- `lib/beamlet/storage/terminal_artifacts.ex`
  - `content/2` returns `decode_item/1` directly (identical to binding
    `{:ok, bytes}` and returning `{:ok, bytes}`).
  - `decode_item/1`: the inner `cond` moved to `validated_content/3`; the order
    of the size/digest checks and their error atoms are unchanged.
- `lib/mix/tasks/beamlet.storage.migrate.ex`
  - `alias Beamlet.Storage.Operator`; `Operator.initialize/2` call site only.

### apps/beamlet_runtime (production)

- `lib/beamlet/runtime.ex`: `alias Beamlet.Storage.{Admission, Codec,
  ExecutorJournal, OperationRecords}` replaces the fully-qualified calls in
  `evidence/3`, `prepared/1` and `coordinators_available/1`.
- `lib/beamlet/runtime/executor_gateway.ex`
  - `admission/9` became `admission/2` over `admit_request/8` (the same eight
    fields: coordinator, id, attempt, incarnation, lease, op, remaining,
    durable). The `cond` branches, the `send` payloads, the capacity check, the
    lease-age reduction and the `claim_start`/`admit` calls are unchanged;
    `admit_message/2` still builds the two admit forms (8-element → no durable,
    9-element → durable).
  - `claim_start/4`: `cond` + `true` became `if valid_durable?` / `else` with the
    same `safe_journal` result handling (`duplicate_admission` vs
    `start_intent`).
  - `digest_matches?/2`: the single-clause `with` starting with `=` became
    `description = ...` + `case Codec.digest/2` returning the same boolean and
    the same `rescue false`.
  - `alias Beamlet.Storage.{Codec, ExecutorJournal}`.
- `lib/beamlet/runtime/operation_coordinator.ex`: aliases
  `Beamlet.Storage.{Admission, OperationRecords}` for the claim/evidence/accept/
  admission calls; no logic touched.
- `lib/beamlet/runtime/persistence.ex`: alias
  `Beamlet.Storage.{Admission, Codec, OperationRecords}`; call sites only.

### apps/beamlet_agent (production)

- `lib/beamlet/agent.ex`: top-level aliases `Beamlet.Agent.{Durable, History,
  Ref, Server, TraceExport}` and `Beamlet.Storage.AgentRecords`; `restore/3`,
  `fork/4`, `history/3`, `export/3`, `inactive/1`, `dormant_source/1` call sites
  only.
- `lib/beamlet/agent/durable.ex`
  - `record_reply/2`, `consume_results/2`: the non-pattern
    `data = state_with_provenance(...)` clause moved into the `with` body (same
    binding, same checkpoint data, same write call).
  - `advance_raw/9` removed: the two command fields are grouped in one
    `%{params: ..., command_id: ...}` map (`advance_raw/8`), and both call sites
    (`accept_risk/4`, `resolve/6`) pass it; the built `command/3` struct, the
    optional `:adoption` attribute and the `AgentRecords.advance/2` call are
    identical. The 6-arity variant is untouched.
  - `dependencies/2`: the redundant trailing `:ok <- artifacts(...)` clause
    became the `with` body, so `artifacts/2`'s own return value is propagated.
  - `pending_state/2`: the reducer closure became `pending_entry_state/3` +
    `accepted_entry_state/1`; the halt/cont tuples and both `{:blocked, ...}`
    reasons are unchanged.
  - `consumptions/1`: the reducer closure became `consumption_entry/2`, and the
    final `case` reversal became `reverse_ok/1`; `1..128` bound, duplicate check
    and `@consumption_kinds` filter are unchanged.
  - `adopt_messages/3` uses `Context.append/2`; `fields/3`, `uuid/1`, `text/2`,
    `count/1`, `json/1`, `digest/1` use the new `Records`/existing `Codec`
    aliases.
- `lib/beamlet/agent/history.ex`: `dispatch("context", ...)` moved
  `data = snapshot["checkpoint"]["data"]` into the `with` body; `Records` alias
  for `uuid/1`.
- `lib/beamlet/agent/server.ex`
  - `valid_keyword_options?/2` split into `valid_option_keys?/1`,
    `valid_delegator?/1`, `valid_durable_pair?/2`, `valid_tools?/1`; the option
    list, the `and`/`or` order and every predicate are preserved, so the same
    option keyword list is accepted or rejected with
    `{:error, :invalid_agent_options}`.
  - `complete_tool/3`: the inner `case commit_consumption` moved to
    `apply_consumption/2`; the `:advance` message, the annotated
    `publish_activity` map and the `fail/2` calls are identical.
  - `durable_input` branch: `unless replayed? do A else B end` became
    `if replayed? do B else A end` — identical results, including the
    `Display.annotate/2` and `:advance` side effects on the non-replayed path.
- `lib/beamlet/agent/trace_export.ex`
  - alias group `Beamlet.Storage.{AgentRecords, Artifacts, Codec, History,
    Records}` (fixes `AliasOrder` and the two `Records.uuid/1` call sites).
  - `write/2`: the nested `with` + `with` + `case` became one `with` (same
    clause order: policy, dir, events, checkpoints, artifacts) plus
    `write_manifest/2` (same `encode/1`, same `File.write/2` mapping).
  - `page/2` → `continue_events/3` and `checkpoint_pages/2` →
    `continue_checkpoints/3`: the paging cursor/`cond`/`if` decision is moved one
    level down with the same conditions (`is_nil(next) or empty`, `next <=
    cursor` → `{:error, :conflict}`).
  - `copy_artifacts/2`: the reducer closure became
    `copy_artifact_entry/4` (same `copy_artifact/3`, same `included`/`missing`
    accumulation) and the dropped-cap map-construction moved to
    `omitted_artifacts/1`.
  - `manifest_shape/1`: the 13-branch `cond` became four branches over
    `valid_manifest_header?/1`, `valid_manifest_collections?/1`,
    `valid_manifest_scope?/1`; the field checks keep the original order and all
    still return `{:error, :invalid_data}` (except the version error, which stays
    first).
  - `verify_artifacts/2`: reducer closure became `verify_artifact/3` +
    `verify_artifact_bytes/3`, same size/digest/missing atoms and order.

### apps/beamlet_daemon (production)

- `lib/beamlet/daemon.ex`: `alias Beamlet.Storage.Host`; `storage/2` call site.

### Tests (structure only — no assertion changed)

- `apps/beamlet_storage/test/beamlet/storage/storage_contract_test.exs`: the one
  ~700-line `quote` is now six named fragments (`common/1`,
  `fixture_helpers/0`, `attribute_helpers/0`, `durability_tests/0`,
  `atomicity_tests/0`, `receipt_tests/0`, `boundary_tests/0`) composed by
  `__using__/1` with `unquote`. `bind_quoted` was replaced by
  `@backend unquote(backend)` / `if unquote(backend) == :postgres`, so the
  generated module sees the same literal backend. Every `test "..."` name and
  body is byte-identical (verified by diff and by `--trace`: 12 SQLite tests
  pass, the same 13 PostgreSQL tests stay excluded). `stop_repo/1` now uses an
  implicit `try` (`repo.stop()` + `catch`), which is the same rescue behaviour.
- `apps/beamlet_storage/test/support/contract_fixture.ex`: `@moduledoc false` on
  the anonymous `DriverFailureStub`; aliases for
  `Connections`/`Records`/`Transaction`; the PostgreSQL connection sampling
  closure became `sample_connection/1` (same checkout, same query, same 200 ms
  hold, same 10 s timeout).
- `apps/beamlet_agent/test/beamlet/{durable_agent_test,fork_test,history_export_test}.exs`
  and `apps/beamlet_daemon/test/beamlet/durable_e2e_test.exs`: alias groups for
  `Beamlet.Agent.Integration.Caller`, `Beamlet.Agent.TraceExport`,
  `Beamlet.Agent.AuthoritySupervisor`, `Beamlet.Harness.{Context, Model,
  Tools.Deterministic}`, `Beamlet.Runtime.{Directory, Persistence,
  SharedSupervisor}`, `Beamlet.Storage.Codec`; call sites shortened; two alias
  groups re-sorted (`AliasOrder`). `fork_test` also swapped the two
  `Beamlet.Storage.Schema.*` alias lines into alphabetical order. No test body,
  assertion, tag or exclusion changed.

## Final gates (all from the repo root, `ERL_FLAGS='+S 2:2'`)

| Command | Exit | Result |
| --- | --- | --- |
| `mix format --check-formatted` | 0 | clean |
| `mix compile --warnings-as-errors` | 0 | clean (also verified with `--force`) |
| `mix test --seed 631927` | 0 | 439 passed / 49 excluded (35/28/15/59+13/53+6/70/68+20/13+4/25+1/73+5) |
| `mix test apps/beamlet_storage/test --seed 631927` | 0 | 59 passed / 13 excluded |
| `mix credo` | 0 | no issues |
| `mix credo --strict --all` | 0 | no issues |
| `mix sobelow` | 0 | SCAN COMPLETE, no findings |
| `mix gettext.extract --check-up-to-date` | 0 | no catalogue drift |
| `mix dialyzer` | 0 | 0 errors, 0 skipped, PLT up to date (not refreshed) |
| `git diff --check` | 0 | no whitespace errors |
| `git diff --stat -- mix.lock scripts config` | 0 | empty (no change) |

Not run here (parent runs them): `scripts/deployment/durable-e2e.sh` and the
named distributed suite (33 tests).

## Invariants confirmed

- No schema, migration, `priv/`, transaction/CAS/admission, error-reason or
  return-value change: the only added/removed `def` line in the whole diff is
  `Beamlet.Agent.HeldTool.descriptor/0` in a test file, whose body is the same
  call through an alias.
- No public module renamed; new helpers are all `defp`; new support code is
  `@moduledoc false`.
- No test removed, renamed, weakened or re-tagged; the storage contract suite
  still runs 12 tests per adapter and the PostgreSQL half stays excluded by
  `:postgres_db`.
- No `.credo.exs`, `--ignore`, exclusion, rule downgrade or suppression comment.
- No `mix.lock`, `config/**`, `apps/*/mix.exs`, `scripts/**`, Web or i18n change.
- `.trellis/spec/backend/quality-guidelines.md` gained a "Credo Gate for the
  Merged Durable Code" section (remedy = refactor, suppression not allowed,
  test-count guard).

## Residual risk

None outstanding. The only judgement calls are unreachable-value equivalences in
`Beamlet.Storage.History`'s filter helpers (`filter_through/2` and friends match
`nil` instead of testing truthiness); every caller feeds them values produced by
the existing validators (`nil` or a validated value), so no reachable input
differs. `trace_export`'s `manifest_shape/1` keeps its original check order, so
the first failing field is unchanged.
