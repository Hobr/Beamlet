# Stage E evidence — safe fork and explicit resolution

Date: 2026-10-18. Branch `feat/durable`. Prerequisites committed: stage A
`3aefa85`, stage B `11577fb`, stage C `f7be001`, stage D `22d6159`. Everything
below was run in this worktree; this sub-agent did not commit anything.

## Callable surface

```elixir
# Public Agent facade (agent.ex)
Beamlet.Agent.fork(locator, checkpoint_id, expected_version, command_id)
#   locator = %{repo:, agent_id: source, model:, tools:, catalogue:, environment:,
#               runtime:, source: %{freeze: :frozen | :idle,
#                                    environment: :confirmed_stopped | :unconfirmed}}
#   -> {:ok, %{agent_id:, checkpoint_id:, locator:, source: %{agent_id:, checkpoint_id:},
#              risk: nil | "unconfirmed", copied: %{"messages" => n, "records" => n},
#              version: 0, generation: 0}}
#   -> {:error, :unsafe_checkpoint | :source_not_frozen | :limit | :conflict |
#               :artifact_missing | :invalid_data | :storage_unavailable |
#               :storage_outcome_unknown}

# Existing single decision entry; two new explicit decisions
Beamlet.Agent.continue(ref, expected_version, decisions, command_id)
#   %{"risk" => "accepted"}                                    # release the fork gate
#   %{"resolution" => "confirmed_executed" | "confirmed_failed",
#    "operation_id" => uuid | nil, "evidence" => map | nil}    # adopt/abandon late evidence

# Embedding path without a live Server
Beamlet.Agent.Durable.fork/4        # same arguments/result as Agent.fork/4
Beamlet.Agent.Durable.decide/2      # same decisions, no dispatch
Beamlet.Agent.Durable.accept_input/2  # now refuses while environment.risk == "unconfirmed"

# Storage facades (one transaction each, stage-A taxonomy)
Beamlet.Storage.AgentRecords.fork(repo, attrs)    # new
Beamlet.Storage.AgentRecords.advance(repo, attrs) # + optional :adoption, nil :turn_id
```

New error atoms in `Beamlet.Storage.Records.@errors`: `:unsafe_checkpoint`,
`:source_not_frozen`. No new table, column, migration, Branch entity, scheduler or
background copy job; `agents.forked_from_*` and `events.source_agent_id` /
`source_event_id` (stage A) are reused as provenance only.

## Copy rules (what a fork takes)

| Item | Fork behaviour |
| --- | --- |
| Effective messages (`checkpoint.data.messages`) | Copied verbatim into the new checkpoint; each message is also recorded as one `context.inherited` event (fresh event id, seq 2..n+1, `source_agent_id` + `source_checkpoint_id` markers) |
| Configuration / Tool schema / environment reference (`agents.definition`) | Copied into the new Agent row; artifact references verified inside the transaction (`Artifacts.verify_references/2`) so content is shared by reference |
| Summaries | No compressed-summary message kind exists in the current Agent; the copy materialises every message, so nothing is dropped or rewritten |
| Operation / Execution / evidence rows | Not copied |
| pending / join / order / results / consumption markers | Cleared (`pending`/`order`/`results`/`consumed` are empty in the new checkpoint) |
| command dedupe | New scope: the fork command is stored under the **source** scope; the new Agent scope has zero commands |
| cancellation / delegation / peer state | Not copied (in-memory only in the current implementation) |
| provider session, PID, Ref, monitors, timers | Never persisted |
| continuation | Always `await_input`; the source continuation is never inherited |
| usage | Inherited messages are `origin: "inherited"` and never counted as this Agent's execution |

## Refusal rules

`Agent.fork/4` refuses, writing nothing:

| Condition | Error |
| --- | --- |
| Source instance still registered in the local Registry (live dispatcher) | `:source_not_frozen` |
| Source has in-flight work (head continuation not idle, or any owned Operation with `accepted_result IS NULL`) and `freeze != :frozen` | `:source_not_frozen` |
| Checkpoint not owned by the source, `safe_to_fork = false`, or continuation not `await_input`/`await_model_result`/`completed` | `:unsafe_checkpoint` |
| `pending`/`order`/`results`/`assistant`/`blocked` non-empty in the checkpoint data (unconsumed reply or Tool result, undecided state) | `:unsafe_checkpoint` |
| Incomplete Tool-call/result pairing (orphan Tool message, unanswered call, duplicate call id) | `:unsafe_checkpoint` |
| Copied messages + definition > 1 048 576 bytes, or > 128 messages | `:limit` (never truncated) |
| `expected_version` differs from the stored source `lock_version`, wrong checkpoint owner, or a replayed command with different params | `:conflict` |
| Referenced artifact missing or corrupt | `:artifact_missing` |

Risk is recorded, not enforced at fork time: an `environment: :unconfirmed`
declaration **or** any accepted source Result with status `uncertain`/`deadline`/
`cancelled`/`unknown` (newest 256 owned Operations) sets
`checkpoint.data.environment.risk = "unconfirmed"` on the new Agent.
`Durable.accept_input/2` then returns
`{:error, {:blocked, :environment_risk_unconfirmed}}` until a
`%{"risk" => "accepted"}` decision writes `agent.risk_accepted` and clears the
flag. Omitting `locator.source` means `%{freeze: :idle, environment: :unconfirmed}`:
the quiet default never grants execution. `fork` itself performs and dispatches
nothing, so a read-only copy or export never grants execution.

## Resolution rules (late evidence after an accepted uncertain Result)

- The accepted Result row is never written by a decision: `AgentRecords.advance/2`
  with `:adoption` re-reads the Operation inside the transaction, requires
  `owner_agent_id == agent.id`, a non-null `accepted_result`, and
  `Codec.digest(accepted_result, :result) == acceptance digest`; otherwise
  `:conflict`.
- If the Operation's Tool-call slot is still empty, adoption fills it **once** from
  the stored Result (`role: "tool"`, `call_id`, canonical JSON content with
  `resolution`, `operation_id`, `adopted: true`). If it is already occupied,
  adoption appends exactly one `%{"role" => "user", "content" => "Late evidence
  resolved ..."}` correction instead, so the Tool result slot is never occupied
  twice.
- The evidence map and its SHA-256 digest stay in the `agent.decision` event
  payload (`"evidence"`, `"evidence_digest"`, `"adopted"`, `"resolution"`), so the
  fact is reviewable without overwriting anything.
- The decision advances only the paused context/continuation; the source Agent and
  any forked Agent are untouched by another Agent's evidence.

## Behaviour changes in existing code (and why)

- `Durable.consume_results/2` now writes its `await_model_result` checkpoint with
  `safe_to_fork: true`: every Tool result of the turn is in the context and nothing
  is in flight, so it is a complete boundary. Without this no practical checkpoint
  was forkable. No stage-C/D test asserted the old value.
- `AgentRecords.advance/2` now accepts `turn_id: nil` (a decision taken at
  `await_input` has no active turn) and validates a supplied `:adoption`.
  `accept_input`/`consume_result` remain turn-strict.
- `Durable.accept_input/2`, `record_reply/2`, `prepare_batch/2` and
  `consume_results/2` now carry the checkpoint's `fork`/`environment` keys forward
  (`state_with_provenance/2`). Without it the first new turn of a forked Agent
  would drop both the provenance and the risk flag.
- `Durable.decide/2` accepts the two new decision shapes; a plain
  `%{"resolution" => ...}` keeps its previous behaviour.

## Commands actually run

| Command | Result |
| --- | --- |
| `mix format --check-formatted` | exit 0 |
| `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_agent/test/beamlet/fork_test.exs` | **8 passed, 0 failed** |
| `mix test apps/beamlet_storage/test` | **51 passed, 13 excluded** (PostgreSQL contract module; `BEAMLET_PG_*` unset), SQLite engine 3.53.4 |
| `mix test apps/beamlet_agent/test` | **67 passed, 0 failed** |
| `mix test` (whole umbrella) | **331 passed, 0 failed, 42 excluded** (harness 35, actions 28, storage 51+13, runtime 52+6, agent 67, node 68+20, daemon 5+2, cli 18+1, web 7) |

Every test creates a real authority/journal SQLite pair through
`Beamlet.Storage.Dataset.initialize/2` in an isolated temp directory, stops both
Repos and removes the directory; no in-memory database is used.

## Test coverage added (`apps/beamlet_agent/test/beamlet/fork_test.exs`, 8 tests)

1. Safe checkpoint → new Agent id, `await_input`, byte-identical copied messages,
   four `context.inherited` events with source markers, `agent.forked` event,
   source Agent/checkpoint/event rows unchanged, source keeps moving afterwards
   while the forked context and restore stay identical.
2. Unsafe checkpoint refused twice (stored `safe_to_fork = false`; a checkpoint
   flagged safe but carrying `pending`) with identical Agent/checkpoint/event/
   command/Operation counts before and after and zero forked children.
3. Oversize copy (≈1.04 MB definition + 10 KB message) refused with `:limit` and
   no rows.
4. Same command retried returns the same new locator (one child, one command);
   a different payload under the same command id is `:conflict`.
5. New Agent owns zero Operations and zero commands, has no
   `operation.prepared`/`result.consumed` events, and empty
   `consumed`/`order`/`results`.
6. Inherited entries are `origin: "inherited"` in `Agent.history/3`, provenance
   reports `counted_as_execution: false`, and the stage-D manifest reports
   `inherited_entries: 4`, `performed_entries: 1`,
   `inherited_counted_as_execution: false` with a passing `TraceExport.verify/1`.
7. Unconfirmed risk blocks `accept_input` with
   `{:blocked, :environment_risk_unconfirmed}` without writing, a stale version
   cannot record acceptance, acceptance writes `agent.risk_accepted` with the fork
   source and unblocks the input, and a second acceptance is
   `{:blocked, :no_pending_risk}`.
8. Consumed-uncertain Result + late success evidence: adoption appends exactly one
   correction message, the Tool result slot stays occupied once, the Operation
   `accepted_result`/`lock_version` are unchanged, the checkpoint returns to
   `await_input`, and the decision event carries the evidence and its digest.

## Remaining gaps (honest limits)

- **"Loads without touching the parent" is asserted indirectly.** The test moves
  the source to a later turn and re-restores the fork (identical context,
  definition and markers from the new Agent's own rows) while the parent rows stay
  present. There is no query instrumentation proving zero parent reads; the code
  path only ever reads `agents/checkpoints/commands/events/artifacts` of the new
  Agent plus the shared artifact ids.
- **PostgreSQL was not run** for the new fork/resolution paths (same limit as
  A–D). The queries are portable Ecto (`count`, `not is_nil`, `count` aggregates,
  `order_by/limit`) but no dual-adapter test covers them.
- **Message-level markers are events, not message keys.** The harness model request
  requires exact message shapes (`map_size/1` checks), so adding
  `source_agent_id` to a message would make the forked Agent's next model request
  `invalid_messages`. Provenance therefore lives in the `context.inherited` events
  plus checkpoint `fork`/`environment` metadata; `History.source_markers/1` will
  report no per-message markers for a real fork (stage D reported them only for its
  fixture).
- **Risk scan is bounded**, not exhaustive: the newest 256 accepted Results owned
  by the source are inspected for non-`ok` statuses.
- **Freeze/stop are declarations.** The authority cannot observe a remote
  executor's stop, so `freeze: :frozen` / `environment: :confirmed_stopped` are the
  caller's assertions, recorded verbatim in the fork event; only the local
  Registry check and the DB-visible in-flight check are enforced mechanically.
- **`retry_of` / new-Operation retry is not implemented.** The delivery plan lists
  it for stage E, but it needs a predecessor relation the Operation schema does not
  have, and this stage forbids a migration. The explicit resolution/risk events
  exist, but "accept the risk and start a related new Operation" is currently just
  a normal new input after acceptance, without a durable `retry_of` link.
- Fork stays inside one authority (no cross-dataset copy protocol), per design §9.4.

## Parent acceptance (2026-10-18)

The independent review returned "OK with notes": no blockers, two P1s and several P2s.
The parent fixed them.

P1 — the freeze predicate was tautological in one operand (every checkpoint reaching that
code point was already restricted to an idle continuation) and over-firing in the other (a
NULL `accepted_result` left behind by an abandoned Operation made every later fork fail).
It now requires a frozen source only when the head continuation is still mid-turn or the
head checkpoint's own turn has undecided Operations, so a quiet head forks with
`freeze: :idle` and an abandoned older turn does not freeze anything. `:source_not_frozen`
now has tests for the mid-turn case, and the quiet case asserts the opposite.

P1 — `Durable.consume_results/2` wrote its checkpoint through `state/1` instead of
`state_with_provenance/2`, dropping the `fork` and `environment` annotations, including the
recorded risk acceptance, from the first Tool-consuming checkpoint of a forked Agent. Fixed;
provenance now survives every write path.

P2 fixes: a message-count breach returns `:limit` rather than `:unsafe_checkpoint`; the
bounded risk scan fails closed (once accepted Results exceed the scan bound the fork is
marked `unconfirmed` instead of silently scanning only the newest window); a non-map tool
reference returns `:invalid_data` instead of raising `BadMapError` (fixed in the fork facade
and in the export artifact scan); `advance/2` only accepts a missing `turn_id` when the head
checkpoint is itself turn-less; and the three statements claiming a fork never writes
anything in the source are corrected — the fork writes no source Agent/checkpoint/event
row, but its own command receipt lives in the source's command namespace so a retry returns
the same locator.

Parent-run gates:

| Command | Result |
| --- | --- |
| `mix format --check-formatted` / `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_agent/test/beamlet/fork_test.exs` | **11 passed** (8 implementer + 3 parent) |
| `mix test apps/beamlet_agent/test` | **56 passed** |
| `mix test` (umbrella) | **334 passed, 0 failures** |
| `mix credo` | exit 0 (advisory findings only) |

Remaining gaps, stated rather than implied:
- the local `Registry` refusal branch (`Agent.fork/4` when a live Server is registered) is
  still untested: the suite exercises durable structs, not a running Agent;
- the copy transaction has no fault-injection test at a mid-copy cut point; atomicity rests
  on the single `Records.transact` closure;
- inherited usage is still asserted by a constant (`inherited_counted_as_execution: false`)
  because no usage accounting exists anywhere in the durable contract — the acceptance item
  is vacuous, not demonstrated;
- PostgreSQL is not exercised for the fork/adoption queries;
- `history(view: :context)` reports `source_markers: []` for a real fork because inherited
  messages are linked through the `context.inherited` event index rather than per-message
  keys.
