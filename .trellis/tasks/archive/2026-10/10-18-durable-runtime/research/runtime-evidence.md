# Stage B runtime evidence (Runtime authority records + executor journal)

Date: 2026-10-18. Branch `feat/durable`. Baseline: stage A commit `3aefa85`
(`apps/beamlet_storage` record facades + `Dataset`), parent design and
`docs/architecture/persistence-delivery.md` stage B.

## What is implemented (opt-in only)

`Beamlet.Runtime.Persistence` is the single explicit durable option
(`persistence: %Persistence{} | keyword`). It carries opaque authority/journal
Repo handles plus stable `authority_id`, `executor_id`, `executor_boot_id` and an
optional owned-Agent/turn identity (`agent_id`, `turn_id`,
`expected_version`, `expected_generation`). Nothing reads application env,
starts a Repo, migrates or stores PIDs/refs/monitors/timers. Without the option
every existing path is unchanged (the previous Runtime suite passes untouched).

Durable ordering in the normal Runtime path:

1. `Runtime.submit/2` calls `OperationRecords.prepare/2` before starting any
   coordinator. The committed response supplies the Operation UUID, the one
   prepared Execution (`attempt_id`, `executor_id`, `executor_boot_id`, budget),
   `description_digest` and the Operation `lock_version`. A failed write returns
   `{:error, :invalid_operation | :unavailable}` and starts no coordinator work.
2. The coordinator claims dispatch (`prepared -> send_claimed`, CAS) and only a
   committed claim allows the admit message. Storage errors end the operation
   with `:durable_unavailable`; a replay/conflict is never permission to send.
   The admit tuple gained an optional ninth element with authority/operation/
   attempt/executor identities and the description digest. The eight-element
   wire form still means "ephemeral" and existing tests/senders are unchanged.
3. The Gateway validates durable identity against its own configured persistence
   (authority/executor/boot and attempt id), checks the journal for an existing
   row (`:duplicate_admission`, no second worker), then commits
   `ExecutorJournal.claim_start/2` (`start_intent`) **before** starting the Task.
   A failed write (including an unavailable Repo) rejects with
   `:durable_unavailable` and never charges capacity or calls a handler.
4. A terminal worker observation is written with `ExecutorJournal.record_terminal/2`
   (first stop cause via `record_stop/2`, terminal result, empty terminal
   artifacts container, receipt id/digest/content) **before** the completion
   message. Only then does the Gateway send
   `{:completed, attempt, handle, result, receipt}` (the four-element form is
   still accepted). A failed terminal write sends `{:rejected, ..., :durable_unavailable}`
   instead: no durable completion is reported.
5. The coordinator persists the receipt as authority evidence
   (`OperationRecords.record_evidence/2`, `evidence_id = receipt_id`) and then
   `OperationRecords.accept_result/2` (CAS on the Operation `lock_version`,
   `accepted_result IS NULL`) before notifying the sink. Identical retries replay;
   different content stays `:conflict` and never overwrites. When acceptance does
   not commit, the sink receives no terminal Result.
6. On executor boot (`ExecutorGateway.init/1`) the Gateway calls
   `ExecutorJournal.mark_unknown_after_restart/2` with its own boot id. Prior
   boots' `start_intent` rows become `unknown_after_restart`, no worker is
   rebuilt, no capacity is restored and the state can never become terminal. If
   that write fails, the executor reports not-ready so durable admission is blocked.
7. `Runtime.evidence/3` is the read-only query: authority Operation + single
   attempt and the journal row by stable IDs, with no coordinator, dispatch or
   sink. `journal: :not_found` is explicitly not proof of non-execution.

Stop provenance is unchanged: the first deadline/cancel trigger owns the cause
(`record_stop` before `Process.exit`), a normal return is `:ok`, an unrelated
crash stays `:worker_lost`, kill escalation stays the first trigger, and a stop
request alone never becomes "worker stopped". Existing admission timeout,
cancel timeout, retention, tombstones, lease/report checks, progress accounting,
capacity release, owner-loss handling and bounded messages are untouched.

## Callable durable entry points

```elixir
persistence = Beamlet.Runtime.Persistence.new(
  authority_repo: Beamlet.Storage.SQLiteAuthorityRepo,
  journal_repo: Beamlet.Storage.ExecutorJournalRepo,
  authority_id: authority_uuid,
  executor_id: executor_uuid,
  executor_boot_id: boot_uuid,
  owner: nil # or %{agent_id:, turn_id:, expected_version:, expected_generation:}
)

{:ok, _pid} = Beamlet.Runtime.SharedSupervisor.start_link(
  execution: true, persistence: persistence, handlers: ..., pools: ...)

{:ok, ref} = Beamlet.Runtime.submit(operation, persistence: persistence)
{:ok, %{authority: _, journal: _}} = Beamlet.Runtime.evidence(persistence, ref.id, attempt_id)
```

## Commands actually run (real counts)

| Command | Result |
| --- | --- |
| `mix format --check-formatted` | exit 0 |
| `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_runtime/test/beamlet/durable_runtime_test.exs` | **8 passed, 0 failed** |
| `mix test apps/beamlet_runtime/test` | **51 passed, 6 excluded** (43 pre-existing incl. deadline classification + 8 new) |
| `mix test` (whole umbrella, per-app) | **289 passed, 0 failed, 42 excluded** (harness 35, actions 28, storage 51+13, runtime 51+6, agent 26, node 68+20, daemon 5+2, cli 18+1, web 7); exit 0 |

Runtime durable tests use two real SQLite files through `Beamlet.Storage.Dataset`
(no in-memory database), one isolated temp directory per test, and stop both
Repos afterwards. No PostgreSQL run was made in this stage; the exercised
contract is SQLite only.

## Test coverage added (`apps/beamlet_runtime/test/beamlet/durable_runtime_test.exs`)

- prepare/claim exist at handler entry; exactly one journal row; attempt in
  `send_claimed` (ordering barrier: handler already running => start intent exists).
- journal becomes unwritable after boot => rejection, zero handler starts, one
  authority error Result accepted.
- sink-side barrier: when the sink sees the Result, the journal row is `terminal`
  and the authority already holds the accepted Result with `accepted_evidence_id`
  equal to the journal `receipt_id`.
- simulated VM loss + new boot => prior `start_intent` becomes
  `unknown_after_restart`, no handler start, capacity equals configured pools,
  and a late terminal write is `:conflict`.
- duplicate receipt replay returns the same accepted Result; conflicting
  receipt is `:conflict`; later evidence with a new id is stored and the
  accepted Result/evidence stay unchanged.
- first deadline cause with a competing cancel, then a normal return: Result
  `:ok` and journal `stop_reason` `deadline`, `terminal`.
- unrelated crash after a cancel request: `:error`/`:worker_lost` with journal
  `stop_reason` `cancelled`.
- expired deadline: `:deadline`/`:worker_stopped`, journal `deadline`, `terminal`.

## Remaining gaps / honest limits

- No `ExecutorJournal.acknowledge/2` call is wired: the design keeps authority
  evidence, `accepted_result` and acknowledgement separate, and stage B does not
  define an ACK wire message. Journal rows therefore stay `acknowledged=false`.
- Journal/authority writes run synchronously in Gateway and coordinator
  callbacks. They are bounded by the stage-A transaction timeout (5000 ms), but a
  slow disk serializes admission/stop handling; no durable commit queue exists.
- `description_digest` covers kind/protocol/payload/budget/claims only;
  credentials, placement hints and metadata stay memory-only.
- Durable mode requires the handler output and Result reason/metadata to be
  stage-A codec-safe plain data. A non-persistable terminal observation is
  reported as "no durable completion" (`:durable_unavailable`), never as success.
- Only one configured executor identity is supported per authority persistence
  option (one attempt, no retries, no multi-executor failover).
- PostgreSQL, the `:distributed` suite, dialyzer and credo were not run in this
  slice; ephemeral distributed behaviour is unchanged by construction because
  the extra admit element only appears when persistence is configured.

## Parent acceptance (2026-10-18)

Independent review returned BLOCK with two P1 findings and several P2s; the parent fixed
them rather than shipping the slice as-is.

P1 — post-run terminal failure was reported as a definite `:error/:durable_unavailable`,
indistinguishable from "never executed". The gateway now sends `{:unrecorded, ...}` after
the handler ran, and the coordinator accepts `:uncertain`. A pre-dispatch rejection still
maps to `:error`.

P1 — `unknown_after_restart` was filtered by a caller-supplied boot id that nothing
regenerated, so an in-VM gateway restart left `start_intent` rows reachable by neither
terminal nor restart classification. At boot the gateway now marks every remaining
`start_intent` row for its authority/executor (supervision has already killed its workers);
`ExecutorJournal.mark_unknown_after_restart` accepts an omitted `keep_executor_boot_id` for
that case and still supports the filtered form.

P2 fixes: `claim_dispatch` uses the prepared attempt's `lock_version` (returned by
`prepare`) instead of a hardcoded 0; a durable submit refuses before writing when no
coordinator supervisor is running; `evidence/3` separates `:not_found` from
`:unavailable`; `status/1` no longer surfaces an unaccepted Result; the gateway recomputes
the description digest from the operation it will execute and rejects a mismatch; the
durable/ephemeral admit constraint and the per-operation `%Persistence{}` requirement are
documented in `operation-runtime.md` and the `submit/2` docstring.

Parent-run gates after those fixes:

| Command | Result |
| --- | --- |
| `mix format --check-formatted` | exit 0 |
| `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_runtime/test` | **52 passed, 6 excluded** |
| `mix test apps/beamlet_runtime/test/beamlet/durable_runtime_test.exs` | **9 passed** |
| `mix test` (umbrella) | **290 passed, 0 failures** |

The new test `a terminal write that cannot commit leaves the result uncertain, not an
error` stops the journal Repo after the handler started and asserts an `:uncertain` Result.
The restart test now asserts the orphaned intent is already `unknown_after_restart` after
the supervised gateway restart, and that a later boot keeps it non-terminal.

Still not covered: kill escalation and cancel-first races in durable mode, the
`owner:`/`expected_version` agent path, duplicate-admission and digest-mismatch negative
tests, and a fail-injected boot marker. Physical durability, cross-host behaviour and
PostgreSQL are unchanged from stage A.
