# Storage format 2

`beamlet_storage` is an opt-in Ecto library. Loading it starts no Repo and performs
no migration, network call, Handler invocation or filesystem business effect.
Agent/Runtime integration is delivered separately; the storage APIs below replace
the previous message-checkpoint model without compatibility shims.

## Installation and durability

`Dataset.initialize(repo, opts)` explicitly installs a **new** authority format 2
(migration 2) or executor journal format 1 (migration 1). The only authority
migration is `priv/authority_migrations/2_authority_v2.exs`; old authority datasets
are refused with `schema_unsupported`. No automatic conversion, clearing or repair
exists. `Dataset.open/2` refuses missing files, wrong dataset ID/role, unsupported
format/migration and restored-backup markers. Save dataset IDs outside the VM.

SQLite options require absolute, symlink-free distinct `database` and
`peer_database` paths and a canonical UUID `dataset_id`. SQLite uses WAL,
synchronous FULL, FK ON, pool size 1, immediate writes and the 2000 ms interruptible
Exqlite busy handler (`PRAGMA busy_timeout` reads 0). PostgreSQL takes trusted
connection options and a dedicated, already-provisioned empty database; pool size
4 and after-connect fsync/synchronous_commit guards remain mandatory. Query
calls retain the 5000 ms budget. Only one authority adapter may run in a VM.

Authority tables are agents, events, checkpoints, operations, executions,
execution_evidence, commands and artifacts, plus installation metadata and Ecto's
schema_migrations. The executor has journal_attempts, metadata and migrations.
Use consistent backups, never copy an active SQLite database file alone. A
restored dataset remains blocked until an explicit operator resolution.

## Agent writes

All parameter maps use atom keys at the facade boundary; persisted JSON uses
string keys. Stable identities are canonical UUID strings; `step_id` and
`tool_call_id` are bounded strings. Every command-bearing write hashes **all**
parameters rather than trusting a caller-provided params digest. A repeated
`command_id` within the Agent scope returns the exact committed response;
different parameters conflict. Writes never retry automatically.

A `position` is `%{agent_id: id, lock_version: version, generation: generation}`.
Generation is checked before version. Successful transitions return string-keyed
`agent_id`, `generation`, `lock_version`, `through_seq`, `history_seq` and `events`.
Use the returned version for the next command. `history_seq == through_seq` counts
committed Agent events only; there are no reserved acceptance positions.

- `AgentRecords.create_agent(repo, %{command_id: uuid, id: uuid, authority_id: dataset_id, definition: json, alias: optional_string})` creates an Agent and `agent.created` at seq 1, version/generation 0. No checkpoint is required.
- `accept_input(repo, %{command_id: uuid, position: position, turn_id: uuid, input: %{"text" => text}})` records original input independently in `input.accepted` and advances one position. A turn cannot reuse an existing input identity.
- `prepare_operations(repo, %{command_id: uuid, position: position, turn_id: uuid, operations: members, orchestration: control_json})` commits 1–8 requests, all attempts, and one Agent preparation event per member atomically. Each member is `%{operation: operation, attempt: attempt}`. See below. Only the active input turn and matching Agent owner are legal. IDs and ordinals within a batch must be unique. The response adds `operations`, each holding `operation_id`, `description_digest`, `attempt_id`, `attempt_version: 0`, `lock_version: 0`, `dispatch_state: "prepared"`. Dispatch must claim this same attempt after commit.
- `consume_results(repo, %{command_id: uuid, position: position, turn_id: uuid, accepted_refs: refs, join: control_json})` validates owner, turn, preparation generation and accepted digest before appending `operation.result_consumed`. Each reference is exactly `%{"operation_id" => uuid, "accepted_digest" => sha256, "consumption_kind" => "model_result" | "tool_result" | "evidence_resolution"}`. Event payload is that reference plus `join`; it contains no Result body. Consumption dedupe is Agent+Operation+kind. A new command overlapping prior consumption conflicts; replay the original command for its original response. Reference order is explicit caller order.
- `advance(repo, %{command_id: uuid, position: position, turn_id: uuid_or_nil, type: type, payload: control_json})` records `turn.interrupted`, `agent.continue_decided`, `agent.config_changed` or `context.selected`.
- `restore(repo, %{command_id: uuid, position: position})` CAS-increments generation and version, clears the checkpoint pointer and appends `agent.activated` with interrupted continuation. It does not dispatch, replay, or resolve work.
- `checkpoint(repo, %{command_id: uuid, position: position, id: uuid, through_seq: seq, reducer_version: positive_integer, projection: control_json, continuation: known_continuation, safe_to_fork: boolean})` writes an optional cache at the exact current high water, increments lock_version without allocating an event, and stores projection SHA-256, reducer_version and through_seq. Body-bearing keys (messages, assistant, request, reply, result, output, payload, content, text, arguments, prompt, tools, schema) are rejected recursively. Operation references must belong to the Agent and accepted digests must match.

Operation references and accepted digests in preparation orchestration, consumption
joins and ordinary control events receive the same transaction-local validation as
checkpoints. Nested artifact references are verified at all these entries.

## Operations and execution

An owned operation contains `id`, `owner_agent_id`, `turn_id`, `step_id`, `role`
(`model`, `tool`, `summary`), `ordinal`, optional `tool_call_id`, `description` and
`sources`. Description has `kind`, `protocol_version: 1`, complete logical request
in `payload`, and optional `refs`, `budget`, `claims`, `safety`. Credentials remain
transient and are rejected by the codec. Source metadata and requests are immutable.
`owner_generation` and distinct Agent `prepared_seq` are assigned by Storage;
Operation `history_seq` belongs to its own stream and changes on acceptance.

Sources are an ordered list of up to 128 entries. Input sources are exactly
`%{"type" => "input", "event_id" => uuid, "seq" => seq, "digest" => sha256}`;
the digest covers the original event payload. Accepted output sources are exactly
`%{"type" => "accepted_result", "reference" => accepted_ref}` and require an
existing consumption event. References must be owned or explicitly inherited in
the same dataset. Inherited sources are `inherited_input` (event identity/seq,
source_agent_id, artifact_id, digest) or `inherited_result` (accepted reference,
source_agent_id, description_digest, resolution). Exact entries must already be
in this Agent's validated context.inherited manifest before request preparation.
Inherited references authorize content only, never consumption of source work.
Policy/version/cutoff/transformation metadata can be fixed in description `refs`;
source selection is owned by the request, not copied into Agent events.

An attempt is `%{attempt_id: uuid, executor_id: uuid, executor_boot_id: uuid,
budget: json}`. Exactly one attempt is required for newly prepared work.
`OperationRecords.prepare(repo, %{operation: operation, attempt: attempt})` is
only for independent ownerless Operations with empty sources and no Agent role,
turn, step, ordinal or tool-call metadata; owned work uses the atomic Agent API.

- `claim_dispatch(repo, %{operation_id: uuid, attempt_id: uuid, expected_version: 0})` CASes prepared to send_claimed once. An old owner's generation or an already accepted Result is refused. PostgreSQL holds Operation and Agent row locks through the claim transaction so acceptance/activation cannot invalidate checked facts before commit; SQLite uses its immediate transaction. This call never sends an admit.
- `record_evidence(repo, %{id: uuid, operation_id: uuid, attempt_id: uuid, executor_id: uuid, evidence_id: uuid, content: json, resolution: optional_json})` verifies attempt/executor and dedupes receipt identity; changed content, binding or resolution conflicts. Late evidence may still be recorded after generation changes.
- `accept_result(repo, %{operation_id: uuid, expected_version: version, result: json, evidence_id: optional_uuid, artifact_ids: optional_uuid_list})` is a NULL-to-accepted CAS. It returns `accepted_result`, `accepted_digest`, evidence ID and Operation version/seq. Identical retries replay; conflicting acceptance never overwrites. Acceptance events use **Operation scope**, never Agent version/seq. The authority retains the Result body and all required local artifacts.
- `AgentRecords.command_response(repo, agent_id, command_id)` returns the original committed response by stable command identity after an unknown outcome (`conflict` when absent).
- `fetch(repo, operation_id)` returns `operation` and `attempt`. `AgentRecords.fetch/2` returns the Agent independently of optional checkpoint health. Read the cache using `History.checkpoint_at/3`.

## Same-authority reference fork

`AgentRecords.fork(repo, %{command_id:, position:, id:, through_seq:, timeline:,
inheritance:, resolutions:, risk:, fork_request:})` is the transaction entry used
by `Beamlet.Agent.fork/4`. fork_request holds through_seq, expected_version and the
normalized source confirmation; replay preserves the original response. It checks
source position, timeline membership at the selected cutoff, inherited manifest
and resolution evidence before creating the independent Agent, created/forked/
context.inherited events and any missing shared input artifacts. PostgreSQL holds
a shared source row lock; source rows are not updated. No Operation/Execution,
pending/command/consumption state or message transcript is cloned. The higher
Agent boundary validates complete safe control and fences local senders.

`Inheritance` captures and verifies a flat, bounded content closure. Input artifacts
are canonical original input payloads reused by digest; accepted refs check original
Operation preparation and acceptance digests, without a parent event-log dependency
when replaying the child. Nested artifact content remains authority-local and is
verified. No automatic GC exists. See the Agent README for risk/continuation and
read/export semantics; no legacy checkpoint-copy entry exists.

## History, content and failure contracts

`Events` owns supported event types/version 1 and the control-body exclusion.
`History.event_page/3` and `AgentRecords.history_page/3` are keyset pages with
`after_seq`, fixed `through_seq`, row limit default 100/max 500 and byte budget
max 4 MiB. History also provides event, turns, operations, operation, evidence and
checkpoint pages. Owned Operation pagination uses immutable `prepared_seq`, so
acceptance cannot reorder or skip requests. Turn pagination uses `after_first_seq`
and returns the last complete group's `first_seq` as cursor; interleaved later
facts do not duplicate a turn or skip the next one. `checkpoint_at/3` selects by
`through_seq`, checks JSON/digest, and returns a nil cache for missing/corrupt data;
raw events and request/Result content remain readable independently.

Codec/JSON preserve strict string keys, UTF-8, duplicate-key refusal, sorted-key
SHA-256, finite values, depth 32/node 100000, recursive structured credential-key
refusal and field byte caps. Existing persisted codec caps remain Operation and
command 1 MiB; event/checkpoint/Result 4 MiB. These are JSON storage budgets,
**not permission to enlarge existing Actions/Runtime wire envelopes**.

`Artifacts` retains verified binary content (max 16 MiB) in the authority
transaction. `References` verifies nested `artifact_id`, `artifact_ids` and
`artifact_refs` fields on definitions, requests, accepted Results and checkpoints;
explicit acceptance artifact IDs are also verified. No GC exists.

`ExecutorJournal` remains format 1 with unchanged APIs and semantics: insert-once
start_intent; first stop cause; terminal/receipt/attachments atomic; restart
unknown never restarts or becomes terminal; acknowledgement never proves stopping.
Attachments retain 64 items, 16 MiB decoded total/per item, 24 MiB encoded and
32 MiB terminal transaction budgets. Authority/journal commits are separate.

Safe errors include invalid_data, limit, conflict, stale_generation,
schema_unsupported, artifact_missing, storage_unavailable and
storage_outcome_unknown. Connection failures conservatively mean unknown write
outcome: reread stable command/Operation identity before any external work.
Transactions contain no network, Handler or filesystem business effects.

## Verification

From the umbrella root:

```sh
BEAMLET_PG_SOCKET_DIR=/absolute/isolated/cluster/socket BEAMLET_PG_PORT=55481 \
  mix test apps/beamlet_storage/test
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict --all
```

The shared contract suite executes real SQLite files and fresh PostgreSQL test
databases, including competing claims/control CAS, independent acceptance,
preparation and consumption rollback, owner/turn/digest/generation refusal and
checkpoint-independent reads. PostgreSQL needs a local throwaway cluster; each
fixture creates/drops only its own database. Missing environment is a test failure.
Agent/Runtime callers use these format2 contracts. Storage-only results still do
not imply full umbrella, named-peer or release acceptance; record each gate.
