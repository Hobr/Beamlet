# Stage C evidence — durable Agent history, checkpoints and paused restore

Date: 2026-10-18. Branch `feat/durable`. Prerequisites committed: stage A
`3aefa85`, stage B `11577fb`. Everything below was actually run in this slice.
This file was written after the stage-C fix round and replaces the earlier
version of the same file, whose coverage claims were overstated in two places
(see "Corrections to the earlier claim").

## What is implemented (opt-in only)

`Beamlet.Agent.Durable` is the single explicit durable option. A Server started
without `durable:` runs exactly the old code path: `durable_input/3`,
`record_reply/2`, `commit_batch/5`, `commit_consumption/2`, `fail/2` and `stop`
only take a durable branch when `s.durable` is a `%Durable{}`, and the restore
state only exists when `restored:` is supplied. `{:input, text}` (two-element)
is still the ephemeral command form. No application env, no auto-started Repo,
no migration, no new scheduler, no event replayer.

### Durable ordering in the Agent path

1. `Agent.input(ref, text, command_id)` → `Durable.accept_input/2` commits command
   dedupe, the `input.accepted` event, the turn and the `await_model_result`
   checkpoint in one `AgentRecords.accept_input/2` transaction **before** the
   Server sends `{:advance, turn}`. A repeated command identity + params returns
   the stored response with `replayed?: true` and dispatches nothing; different
   params is `:conflict`.
2. `complete(s, :model, {:ok, reply})` first calls `Durable.record_reply/2`
   (`AgentRecords.advance/2`), then validates the batch. A crash after that commit
   leaves `continuation: "reply_recorded"`; restore + continue re-validates the
   stored reply (`Server.replay_reply/1`) and never requests the model again.
   `record_reply/2` accepts only a plain, total normalization of the provider
   reply: a malformed reply becomes `fail(:invalid_reply)`, never a crash.
3. `batch/2` validates the whole reply and batch, builds **the same
   `%Beamlet.Actions.Operation{}` the Runtime will dispatch**, then
   `Durable.prepare_batch/2` commits every Operation, one prepared Execution
   attempt per Operation, one event per Operation (with `turn_id`) and the
   `await_tool_results` checkpoint (with the real model `step`) in a single
   `OperationRecords.prepare_batch/2` transaction. An illegal batch stores zero
   Operations and dispatches nothing.
4. Dispatch goes through the normal `OperationOwner` → `Beamlet.Runtime.submit/2`
   with `persistence:` **and** `prepared:` (`operation_id`, `attempt_id`,
   `attempt_version`, `description_digest`, `lock_version`), so the Runtime writes
   no Operation of its own and the accepted Result lands on the batch row. A
   durable Agent without the `runtime` wiring blocks the batch with
   `:missing_durable_runtime` before committing or dispatching anything.
5. When every Tool result is in, `complete_tool/3` → `Durable.consume_results/2`
   → `AgentRecords.consume_result/2`: the tool messages, the `result.consumed`
   marker per Operation and the next checkpoint commit in one transaction keyed
   by `(agent_id, operation_id, consumption_kind)`. The facade sorts by
   `ordinal`, so out-of-order completion still enters the context in original
   order; a foreign (source-Agent) Operation is rejected by stored ownership.
6. `fail/2` and `stop` commit a `blocked` checkpoint with a safe reason, keep the
   returned version and pause the instance (`status: :paused`,
   `continuation: "blocked"`), so `Agent.continue` is reachable. If the block
   write itself fails the instance stops as `:error` with
   `final: {:block_write_failed, reason}` instead of claiming the durable fact.
   `stop` on an idle durable instance writes nothing.
7. A `:uncertain` Tool or model Result never becomes an observation: a durable
   turn blocks with `:uncertain_external_effect` (no tool message, no further
   model step, no further Tool dispatch). Ephemeral Agents keep today's
   behaviour.

### Batch/accept binding (why it is not just "another version CAS")

`OperationRecords.prepare_batch/2` reserves **two** Agent history positions per
member: the `operation.prepared` event and the position its own
`operation.result_accepted` event will write (`accept_seq`, returned per member).
Concurrent accepts of one batch therefore never contend on the Agent
`lock_version`, which a strict per-accept CAS would make impossible (results
arrive in arbitrary order). The accepted Result itself is still guarded by the
Operation `accepted_result IS NULL` + `lock_version` CAS, and the accept is
fenced by the Agent generation. The batch's single `cas_agent` reserves the whole
range up front, so Agent `lock_version` only moves at prepare/advance/consume.

### Callable surface

```elixir
# opt-in open (one transaction: Agent + await_input checkpoint + create command)
{:ok, %Durable{}} =
  Beamlet.Agent.Durable.open(repo, %{
    agent_id: uuid, authority_id: uuid, alias: "a1" | nil,
    command_id: uuid,
    definition: %{                       # references only, never credentials
      "schema_version" => 1,
      "model" => %{"provider" => "openai-compatible",
                   "config" => %{...}, "secret_ref" => "vault/model" | nil},
      "tools" => %{"echo" => %{"profile" => "echo",
                               "environment" => nil, "secret_ref" => nil,
                               "artifact_refs" => []}},
      "environment" => nil
    }
  })

# live Runtime wiring a durable Tool batch is dispatched through
{:ok, %Durable{}} =
  Beamlet.Agent.Durable.with_runtime(durable, %{
    authority_repo: Beamlet.Storage.SQLiteAuthorityRepo,
    journal_repo: Beamlet.Storage.ExecutorJournalRepo,
    executor_id: uuid, executor_boot_id: uuid
  })

{:ok, ref} =
  Beamlet.Agent.start(node(), id: "a1", model: binding, tools: tools,
                      catalogue: catalogue, durable: durable)

{:ok, turn} = Beamlet.Agent.input(ref, text, command_id)   # durable path
{:ok, ref}  = Beamlet.Agent.restore(locator, expected_version, command_id)
{:ok, view} = Beamlet.Agent.continue(ref, expected_version, decisions, command_id)

locator = %{repo: repo, agent_id: uuid, model: binding,
            tools: %{"echo" => %{id: "echo-profile", capability: "echo"}},
            catalogue: catalogue, environment: nil,
            runtime: runtime_config_or_nil}
decisions = %{} | %{"resolution" => "confirmed_failed" | "confirmed_executed"}
```

`Durable` also exposes the ordered commit steps used above
(`accept_input/2`, `record_reply/2`, `prepare_batch/2`, `consume_results/2`,
`block/2`, `decide/2`, `restore/3`, `state/1`, `runtime/1`, `persistence/2`,
`model_persistence/1`) so an embedding caller can drive the same transactions.
`Beamlet.Runtime.submit/2` gained the optional `prepared:` map (an attempt another
authority transaction already committed) alongside `persistence:`.

Restore returns a `status: :paused` instance that performs no model, Tool or
network work and rebuilds its display annotations from the restored messages
(annotations stay in memory and are never persisted). `Agent.restore/3` checks
that the instance id (`alias || agent_id`) is not registered **before** the
restore transaction, so a rejected duplicate returns `{:error, :already_active}`
without bumping the generation of the running instance. Continuing is a separate
explicit call that validates `expected_version` and the stored continuation
*before* recording anything (an unsupported position returns
`{:error, {:unsupported_continuation, position}}` and writes nothing), then
records the decision (deduped `agent.decision` event + command row). Missing
secret/profile/environment reference, unsupported schema, missing checkpoint,
unconfirmed Tool result or missing artifact returns `{:error, {:blocked, reason}}`
with nothing written and nothing dispatched.

### Stage-C storage extensions (only where needed)

- `AgentRecords.advance/2` — advances the active turn's checkpoint with an
  optional idempotent command identity (reply commit, decision, blocked state).
- `AgentRecords.restore/2` — CAS generation+version bump with a new head
  checkpoint, event and command; it now takes the restored checkpoint's
  `turn_id` so the restored head is a real turn head for `consume_result/2`.
- `AgentRecords.checkpoint/1` and `insert_checkpoint/4` — public so the batch
  transaction can write its checkpoint without a second storage path.
- `OperationRecords.prepare_batch/2` — all Operations of one legal batch, their
  prepared Executions, their events and the batch checkpoint in one transaction
  (one Agent history advance of `2n`, one lock-version bump); the replay response
  now carries `lock_version`, `accept_seq` and the attempt identity.
- `OperationRecords.accept_result/2` accepts `agent: %{expected_generation,
  accept_seq}` for a batch member (fenced by generation, no version CAS).
- `Records`/`OperationRecords` bulk prep unchanged elsewhere; no new table,
  column or migration: the checkpoint `data` document carries the state,
  `agent.generation` serializes restores.
- `Runtime.Persistence.value/1` now converts a Result's value (and reason)
  recursively to plain JSON data, so a durable receipt (journal + accepted
  Result) can always be digested; the in-memory `%Result{}` handed to the sink is
  unchanged.
- A durable Agent's **model** step is dispatched with `persistence:` too: an
  executor configured for durable work rejects ephemeral admissions, and a turn
  that mixed durable Tool rows with an ephemeral model step could not run.

## Corrections to the earlier claim

The previous version of this file overstated two things:

- It said restore blocks a *missing environment*. `Durable.environment/2` only
  compares a definition's stored `environment` reference with the locator's;
  there is no test that exercises a mismatching environment, so that branch is
  **not** covered by a test. Covered blocked restores are: missing secret
  (`durable_agent_test.exs` blocked-restore test) and missing artifact. A
  mismatching tool profile, an unsupported schema, a missing checkpoint, an
  `unconfirmed_tool_result` and a mismatching `environment` reference are enforced
  in code but have no dedicated assertion; see Remaining gaps.
- It said `await_tool_results` / `results_to_consume` restore to `:paused` and
  that the Server branch returns `{:error, {:unsupported_continuation, ...}}`.
  That was an error *after* the decision commit. The Server now refuses the
  position before writing anything, and a test asserts that no `agent.decision`
  event is written.

## Commands actually run

| Command | Result |
| --- | --- |
| `mix format --check-formatted` | exit 0 |
| `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_agent/test/beamlet/durable_agent_test.exs` | **18 passed, 0 failed** |
| `mix test apps/beamlet_agent/test` | **44 passed** (26 pre-existing + 18 new) |
| `mix test` (whole umbrella) | **308 passed, 0 failed, 42 excluded** (harness 35, actions 28, storage 51+13, runtime 52+6, agent 44, node 68+20, daemon 5+2, cli 18+1, web 7); exit 0 |
| `mix credo` | 26 refactoring + 2 readability advisory findings repo-wide (none added by this round; `mix credo` exits non-zero on advisory findings) |

SQLite only in this slice (engine shipped with `exqlite` 0.42); the PostgreSQL
contract module was not run (`BEAMLET_PG_*` unset, 13 excluded). Every test uses
real SQLite files created through `Beamlet.Storage.Dataset.initialize/2` in an
isolated temp directory and stops both Repos afterwards; no in-memory database is
used.

## Test coverage added (18 tests in `apps/beamlet_agent/test/beamlet/durable_agent_test.exs`)

Commit-level (direct `Durable` API):

- input acceptance commits turn/checkpoint/event before dispatch; a repeated
  command identity replays (`replayed?: true`, one `input.accepted` event) and
  different params under the same identity is `:conflict`;
- the full reply + request identity persist before validation, and a restore at
  `reply_recorded` re-validates the stored reply (continue → `:done`, 0 model
  calls);
- an illegal batch commits zero Operations (no `operation.prepared` event);
- results accepted in reverse order still consume in `ordinal` order (checkpoint
  tool messages `call-1`, `call-2`), consumption replays to the same markers and
  produces exactly two `result.consumed` events; the batch checkpoint carries
  `step: 1` and the turn;
- a source Agent's Operation is not consumable (`:conflict`);
- `await_input`, `await_model_result`, `reply_recorded` and `await_tool_results`
  each restore a `:paused` instance with 0 model calls; continuing
  `await_tool_results` is refused before any write;
- missing secret / missing artifact block the restore with no instance
  registered and 0 model calls;
- an uncertain effect recorded by `Durable.block/2` needs an explicit decision;
- restore rebuilds display annotations (`display.entries` shows the restored user
  message);
- persisted Agent/checkpoint rows contain no display entries, activities,
  annotation ids, subscriber state, PIDs or Refs.

End-to-end through `Agent` + a real `Beamlet.Runtime` + real SQLite files
(`Agent.Integration.Handler`, `ScriptedModel`, a held Tool):

- **durable Tool batch through `Agent.input`**: two Tool calls are prepared with
  attempts, dispatched through `Runtime.submit/2` with `prepared:`, both row
  `accepted_result`s are `ok`/`execution` (never unconfirmed), exactly two
  `result.consumed` events in ordinal order, exactly two model steps and no third
  dispatch, and the finished checkpoint restores with `pending: []`;
- **injected `%Result{status: :uncertain}`**: the turn blocks with
  `:uncertain_external_effect`, no tool message is appended, 0 further model
  calls, 0 further Tool dispatch, and `Agent.continue` resolves the block exactly
  once (one `agent.decision` event, `unresolved_effect` without a resolution);
- **durable Agent without the Runtime section**: blocks with
  `:missing_durable_runtime`, zero `operation.prepared` events, nothing
  dispatched ephemerally;
- **duplicate concurrent restores**: exactly one succeeds, exactly one
  `agent.restored` event, and the survivor still records a decision and finishes
  its turn;
- **restore of a running instance**: `{:error, :already_active}` before the
  generation bump (generation stays 0, no `agent.restored` event) and the running
  instance still commits a new turn;
- **mid-turn restore**: a checkpoint at `await_model_result`/`step: 2` restores
  with `steps: 2` and `continue` advances (one model step, no `:step_limit`);
- **malformed provider reply**: blocks with `:invalid_reply` and the temporary
  GenServer stays alive;
- **stop on an idle durable instance**: no `agent.blocked` event, head
  continuation stays `await_input`.

## Remaining gaps (honest limits)

- PostgreSQL was not run (SQLite only), and no physical power-loss test exists;
  WAL/FULL are configuration claims (same limit as stages A and B).
- Unsupported-schema restore, a mismatching `environment` reference and a
  mismatching tool profile are enforced in code but have no dedicated test.
- The batch **replay** path (`OperationRecords.prepare_batch/2` seeing stored
  rows) is implemented and now returns `lock_version`/attempt identity, but it is
  unreachable in practice because `Durable.prepare_batch/2` mints fresh Operation
  ids per call; no test drives a stored-batch replay.
- Restore while an old live instance of another alias/Id is still running is
  serialized locally by the pre-check plus the generation CAS, not cross-host.
- `continue` resumes `await_input`, `await_model_result`, `reply_recorded` and
  `blocked`. Restoring at `await_tool_results` yields `:paused` and refuses the
  continuation (no re-dispatch of a Tool batch after restore); the pure-data
  completion step (`Durable.consume_results/2`) is implemented and tested.
- Delegation (`await_delegation`) and peer (`await_peer`) continuations are not
  durable; delegation stays an ephemeral feature.
- A durable turn's model step is committed as an unowned Operation row, so model
  calls are durable evidence but are not part of the Agent's checkpoint history.

## Parent acceptance (2026-10-18)

First review returned BLOCK with one P0 and four P1s; the parent ran a dedicated fix
round and then a focused re-check.

Fixed: the durable Tool batch is now bound to the dispatched Operation — the batch
commits the same `%Operation{}` the Server dispatches, stores
`Persistence.description/1` so the executor's digest check passes, `OperationRecords.prepare_batch/2`
commits one prepared attempt per member, and `Runtime.submit/2` accepts `prepared:` and
skips its own `prepare`, so `accepted_result` lands on the prepared rows. An `:uncertain`
result now blocks a durable turn instead of becoming a tool observation. `Agent.restore/3`
checks for an active instance before the generation CAS. `fail/2` keeps the blocked
checkpoint's version and pauses; a failed block write reports
`{:block_write_failed, _}` instead of claiming the fact.

P2s fixed: restored checkpoint carries its `turn_id`; batch checkpoints persist the real
step and clamp on restore; `continue` validates the position before committing; the replay
response carries `lock_version`; reply normalisation is total so a malformed provider reply
reaches `fail(:invalid_reply)`; restore rebuilds display annotations; batch events carry
`turn_id`; an idle stop writes nothing; `stop` with a failed block write reports `:error`;
a reserved accept position beyond the Agent's history sequence is rejected as `:conflict`.

Parent-run gates:

| Command | Result |
| --- | --- |
| `mix format --check-formatted` / `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_agent/test` | **44 passed** |
| `mix test apps/beamlet_runtime/test` | **52 passed, 6 excluded** |
| `mix test apps/beamlet_storage/test` | **51 passed, 13 excluded** |
| `mix test` (umbrella) | **308 passed, 0 failures** |
| `mix credo` | exit 0 (advisory: 26 refactoring, 2 readability) |

Coverage reality: the end-to-end durable Tool batch, the `:uncertain` block, duplicate
restore isolation, blocked-then-continue exactly once, and restore of a mid-turn
checkpoint are covered through public APIs. A mismatching tool profile, unsupported
schema, missing checkpoint, `unconfirmed_tool_result` and a mismatching environment are
enforced in code but untested, and the `{:block_write_failed, _}` branch has no test.
PostgreSQL is not exercised for the new Agent facades.
