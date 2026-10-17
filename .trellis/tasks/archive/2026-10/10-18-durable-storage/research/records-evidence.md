# Records component evidence (stage A, records slice)

Scope: concrete persistence transactions for `AgentRecords`, `OperationRecords`
and `ExecutorJournal`, the `TerminalArtifacts` content codec and their contract
tests. No business-process integration, no message sending, no handler execution.
Authority is SQLite only in this evidence; PostgreSQL is not executed and is not
claimed.

## Implemented

New modules under `apps/beamlet_storage/lib/beamlet/storage/`:

| Module | Responsibility |
| --- | --- |
| `records.ex` | Shared validation (identity/UUID, text, digest, enum, strict JSON), CAS helpers, constraint→error mapping, one guarded write transaction, atom-free plain-data conversion. |
| `agent_records.ex` | `create_agent/2`, `accept_input/2`, `consume_result/2`, `fetch/2`, `history_page/3`. |
| `operation_records.ex` | `prepare/2`, `claim_dispatch/2`, `record_evidence/2`, `accept_result/2`, `fetch/2`. |
| `executor_journal.ex` | `claim_start/2`, `record_stop/2`, `record_terminal/2`, `acknowledge/2`, `mark_unknown_after_restart/2`, `fetch/3`. |
| `terminal_artifacts.ex` | Version-1 attachment container: key whitelist, ≤64 canonical UUID keys, strict canonical base64, per-item/aggregate decoded ≤16 MiB, encoded ≤24 MiB, digest+size verification, `content/2` decode. |

Semantics enforced inside one transaction each:

- command `scope_id`+`command_id` stores the request digest and committed response; same identity+params replays the stored response, different params is `conflict` (`create_agent`, `accept_input`);
- `history_seq` and `lock_version` advance by CAS; the event `unique(scope_id, seq)` and `unique(scope_id, dedupe_key)` indexes are the concurrency facts; failures leave no Agent/checkpoint/event/command partial state;
- `consume_result` is exactly-once via `dedupe_key = "consume:<operation_id>:<kind>"` under `events(scope_id, dedupe_key)`, revalidates the Agent's active turn and the Operation owner Agent/turn (source/forked Agent Operations are rejected), and writes context events in `ordinal` order plus the next checkpoint;
- `prepare` writes one immutable description (`kind`, `protocol_version`, `payload`, optional `refs`/`budget`/`claims`/`safety`; credentials rejected structurally by the codec), at most one execution (`unique(operation_id)`) and a history event; `claim_dispatch` CASes `prepared -> send_claimed` and returns committed data only (already claimed is `conflict`, never a send permission);
- `record_evidence` dedupes on `(executor_id, evidence_id)`; same digest replays, different digest is `conflict` and the original row stays; `accept_result` CASes `accepted_result IS NULL`, replays identical retries, resolves evidence/artifact references in-transaction and never overwrites an accepted Result;
- journal `claim_start` is insert-once on `(authority_id, attempt_id)` and only reports stored state; `record_stop` keeps the first cause; `record_terminal` writes state + terminal result + attachments + receipt atomically and only from `start_intent`; `acknowledge` records the authority receipt acknowledgement only; `mark_unknown_after_restart` is the only producer of `unknown_after_restart`, which can never be turned into a terminal fact or "not executed".

Errors are plain atoms: `invalid_data`, `limit`, `conflict`, `stale_generation`,
`schema_unsupported`, `artifact_missing`, `storage_unavailable`,
`storage_outcome_unknown`. `conflict` also means "unknown stable identity or state
does not match the request". No SQL/connection/secret text escapes; write
transactions are not retried.

## Callable interfaces for B/C

```elixir
AgentRecords.create_agent(repo, %{
  command: %{scope_id, command_id, params},
  id, authority_id, alias, definition, generation: 0,
  forked_from_agent_id, forked_from_checkpoint_id,
  checkpoint: %{id, data, safe_to_fork: true},
  event: %{id, type, payload}
})
# => {:ok, %{"agent_id", "checkpoint_id", "command_id", "history_seq" => 1, "lock_version" => 0}}

AgentRecords.accept_input(repo, %{
  command: %{scope_id, command_id, params},
  agent_id, expected_version, expected_generation, turn_id,
  checkpoint: %{id, data, continuation, safe_to_fork},
  event: %{id, type, payload}
})
# => {:ok, %{"agent_id", "checkpoint_id", "turn_id", "command_id", "history_seq", "lock_version"}}

AgentRecords.consume_result(repo, %{
  agent_id, expected_version, expected_generation, turn_id,
  operations: [%{operation_id, consumption_kind}],   # 1..128, kind in tool_result|model_result|evidence_resolution
  checkpoint: %{id, data, continuation, safe_to_fork}
})
# => {:ok, %{"agent_id", "checkpoint_id", "consumed" => [%{"operation_id", "consumption_kind", "event_id", "seq"}], "history_seq", "lock_version"}}

AgentRecords.fetch(repo, agent_id)
# => {:ok, %{"agent" => map, "head_checkpoint" => map | nil}}
AgentRecords.history_page(repo, agent_id, after_seq: 0, limit: 100)
# => {:ok, %{"events" => [map], "next_cursor" => seq | nil}}

OperationRecords.prepare(repo, %{
  operation: %{id, description, owner_agent_id, turn_id, tool_call_id, ordinal},
  attempt: nil | %{attempt_id, executor_id, executor_boot_id, budget},
  agent: nil | %{expected_version, expected_generation},   # required for owned Operations
  event: %{id, type, payload}
})
# => {:ok, %{"operation_id", "description_digest", "history_seq", "lock_version" => 0, "attempt_id" | nil, "dispatch_state" | nil}}

OperationRecords.claim_dispatch(repo, %{operation_id, attempt_id, expected_version})
# => {:ok, %{"operation_id", "attempt_id", "executor_id", "executor_boot_id", "description_digest", "dispatch_state" => "send_claimed", "lock_version"}}

OperationRecords.record_evidence(repo, %{
  id, operation_id, attempt_id, executor_id, evidence_id, content, digest, resolution
})
# => {:ok, %{"id", "operation_id", "attempt_id", "evidence_id", "digest"}}

OperationRecords.accept_result(repo, %{
  operation_id, expected_version, result, event,
  evidence_id, artifact_ids, agent   # agent required for owned Operations
})
# => {:ok, %{"operation_id", "accepted_result", "accepted_evidence_id", "history_seq", "lock_version"}}

OperationRecords.fetch(repo, operation_id)
# => {:ok, %{"operation" => map, "attempt" => map | nil}}

ExecutorJournal.claim_start(repo, %{id, authority_id, operation_id, attempt_id,
  description_digest, executor_id, executor_boot_id})
# => {:ok, %{"record_id", "authority_id", "operation_id", "attempt_id", "state", "stop_reason", "acknowledged", "receipt_id", "lock_version"}}

ExecutorJournal.record_stop(repo, %{authority_id, attempt_id, stop_reason, expected_version})
ExecutorJournal.record_terminal(repo, %{authority_id, attempt_id, expected_version, termination,
  terminal_result, terminal_artifacts, receipt_id, receipt_digest, receipt})
ExecutorJournal.acknowledge(repo, %{authority_id, attempt_id, expected_version})
ExecutorJournal.mark_unknown_after_restart(repo, %{authority_id, executor_id, keep_executor_boot_id})
# => {:ok, %{"marked" => count}}
ExecutorJournal.fetch(repo, authority_id, attempt_id)
# => {:ok, map}
```

Stage-A Operation description envelope (B/C may extend only with a reviewed stage
change): `kind` (string), `protocol_version` (integer ≥1), `payload` (map),
optional `refs`, `budget`, `claims`, `safety`. Event types must match
`segment.segment…` lowercase identifiers.

## Commands actually run (2026-10-18, this checkout)

```sh
cd apps/beamlet_storage && mix test test/beamlet/storage/record_transactions_test.exs
# 18 tests, 18 passed (0 failures) — focused records suite

cd apps/beamlet_storage && mix test test
# 39 tests, 39 passed (includes the foundation codec/dataset/no-load suites)
# Storage SQLite engine: 3.53.4

mix format --check-formatted                                   # exit 0
mix compile --warnings-as-errors                               # exit 0
mix test apps/beamlet_storage/test                             # 39 passed
BEAMLET_BACKEND_BUILD=1 mix compile --warnings-as-errors       # exit 0
BEAMLET_BACKEND_BUILD=1 mix test apps/beamlet_storage/test     # 39 passed
```

Coverage in `record_transactions_test.exs`: command idempotence + param conflict,
atomic rollback (checkpoint collision → no Agent/event rows), accept_input
version/generation/turn/unknown-Agent refusals, ordered concurrent-join
consumption with replay and foreign-owner rejection, history pagination bounds,
prepare replay/conflict/one-attempt, credential/unknown-description rejection,
claim CAS and second-claim refusal, two-connection claim race through
`put_dynamic_repo` on an independent Repo instance (exactly one winner), evidence
dedupe/digest conflict, accepted-Result non-overwrite, artifact reference
integrity, journal insert-once, restart-unknown, stop-cause precedence, terminal
duplicate/digest conflict, ACK idempotence, attachment boundaries (bad base64,
digest, size, non-UUID key, 65 items, 16 MiB aggregate/per-item, 32 MiB stored
budget, binary round trip).

## Not done / risks

- PostgreSQL is not executed anywhere; the dual-adapter contract is integration work.
- SQLite tests use real files and a second Repo connection for CAS competition; they do not prove physical power-loss, cross-host fencing or WAL backup behaviour.
- `events(scope_id, seq)` is the Agent/Operation stream fact; a prepared Operation for an Agent must be allocated through the Agent CAS, which requires the caller to hold the current Agent version.
- `consume_result` writes `result.consumed` events with the Operation's `tool_call_id`/`ordinal`/accepted Result; the Tool message content that B wants in model context still needs its own event if it differs from the accepted Result.
- Consuming a Result whose accepted Result is close to the 4 MiB event limit can exceed the event limit when wrapped; that is an explicit `limit`, never truncation.
- No GC, retention, capacity or WAL checkpoint policy is added here.
