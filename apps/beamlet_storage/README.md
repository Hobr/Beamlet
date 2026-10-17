# Storage foundation (stage A component)

This internal library adds no Application callback, Agent/Runtime dependency or
host configuration. It does not activate durable business behavior. The record
transaction facades (`AgentRecords`, `OperationRecords`, `ExecutorJournal`) are
implemented below; do not expose raw Repos to UI code.

## Explicit installation and reopen

Create trusted local directories first. Use real files, not in-memory SQLite, for
durable tests. `initialize` refuses an existing file; `open` refuses a missing or
uninstalled dataset and never runs migrations. Both return `{:ok, repo_pid}` and
leave a linked Repo running. An embedding supervisor may explicitly use
`start: {Beamlet.Storage.Dataset, :open, [repo, options]}` in its child spec.

```elixir
alias Beamlet.Storage.{Dataset, SQLiteAuthorityRepo, ExecutorJournalRepo}
authority = [database: "/absolute/local/authority.db",
  peer_database: "/absolute/local/journal.db", dataset_id: Ecto.UUID.generate()]
journal = [database: authority[:peer_database],
  peer_database: authority[:database], dataset_id: Ecto.UUID.generate()]
{:ok, _} = Dataset.initialize(SQLiteAuthorityRepo, authority)
{:ok, _} = Dataset.initialize(ExecutorJournalRepo, journal)
SQLiteAuthorityRepo.stop()
{:ok, _} = Dataset.open(SQLiteAuthorityRepo, authority)
```

Save the two dataset IDs outside the running VM; authority and executor IDs are
separate stable identities. Never generate new expected IDs for reopen. Paths must
be absolute, local and symlink-free; alias spelling and existing hardlinks are
rejected. Directory ownership must prevent concurrent path replacement. This is
not a filesystem race sandbox, cross-host fencing, or network-filesystem support.
Only one authority adapter is selected per VM through Dataset startup.

Each dataset has one singleton `storage_metadata` installation row: `id=1`,
`dataset_id`, `role` (`authority` or `journal`), `format_version=1`,
`restored_backup=false`. This is **not** an additional business entity. Physical
counts are authority **8 business + 1 installation metadata** tables, journal
**1 attempt + 1 installation metadata** tables, plus each Repo's Ecto-owned
`schema_migrations`. Identity/role mismatch, missing metadata, unsupported format
or migration version, and a true backup marker all refuse reopen. There is no
API that silently repairs identity or clears a backup marker. Operators must mark
known backup restores before use; the marker cannot detect arbitrary rollback.

Installation reserves the SQLite file exclusively, then atomically creates the
metadata table and row, then explicitly runs the role's version-1 Ecto migration.
Business DDL is transactional. Failed/interrupted installation leaves a reserved
file or incomplete installation that cannot reopen; it is never silently retried
as a new dataset. No business rows are admitted in that state. Future upgrades
need an explicitly reviewed migration action; reopen cannot run them for you.
Migration downgrade deliberately refuses destructive rollback.

For PostgreSQL use `PostgresAuthorityRepo` with `database`, `hostname` (or
`socket_dir` + `port`), `username` and trusted connection options supplied directly
(never persisted in records). Provision a dedicated empty database first; Dataset
does not create a server or PostgreSQL database. PostgreSQL uses pool size 4, Read
Committed defaults, ordinary tables, and checks fsync/synchronous_commit on every
connection; a connection that fails the check is refused.

PostgreSQL is executed by the shared contract suite
(`test/beamlet/storage/storage_contract_test.exs`) against an isolated cluster: point
`BEAMLET_PG_SOCKET_DIR` (and `BEAMLET_PG_PORT`, default 5432) at a throwaway
cluster; each test creates and drops its own `beamlet_contract_<n>` database. The
suite asserts the same facts on both adapters. Without those variables the
PostgreSQL module fails loudly instead of reporting a skip as a pass.

## Connection and transaction rules

SQLite has pool size 1, WAL, FULL, FK ON, query timeout 5000 ms, configured busy
budget 2000 ms and deferred default transactions. Every physical connection,
including reconnects, checks WAL/FULL/FK. **Resolved Exqlite 0.42.0 uses a custom
interruptible busy handler, so `PRAGMA busy_timeout` reads 0.** It is checked as 0,
not falsely reported as 2000. `Exqlite.Connection.set_busy_timeout/2` calls
`Exqlite.Sqlite3.set_busy_timeout/2` (NIF) rather than overwriting that handler with
a PRAGMA. Real separate-connection tests verify finite contention failure,
success after lock release, and timeout/connection teardown while still blocked.
These are scheduling-tolerant tests, not hard-real-time or physical power-loss
claims. Do not set PRAGMA busy_timeout and accidentally replace the handler.

`Transaction.write(repo, Ecto.Multi | zero_arity_function)` applies immediate mode
only to SQLite writes. Ordinary Repo reads and read transactions remain deferred.
It does not retry. Driver/connection failures on writes conservatively return
`storage_outcome_unknown`; re-read stable IDs before external work. `Transaction.read/1`
normalizes driver failures to `storage_unavailable`. The record facades wrap
`Transaction.write/2` once, map changesets/constraints into safe domain errors and
enforce CAS/generation, command identity and business transition invariants. Do not
perform network/handler/filesystem effects inside any transaction. A timeout is not
proof of rollback or non-execution.

## Record transactions

`AgentRecords`, `OperationRecords` and `ExecutorJournal` are the only write
entry points; each validates identity, strict JSON schema, stored owner/turn,
version and generation itself instead of trusting the caller. Every mutation is
one `Ecto.Multi`-equivalent transaction: any `{:error, reason}` rolls back the
whole write set.

```elixir
{:ok, map} | {:error, :invalid_data | :limit | :conflict | :stale_generation |
   :schema_unsupported | :artifact_missing | :storage_unavailable |
   :storage_outcome_unknown}
```

- `AgentRecords.create_agent(repo, %{command: %{scope_id, command_id, params}, id, authority_id, alias, definition, generation: 0, forked_from_agent_id, forked_from_checkpoint_id, checkpoint: %{id, data, safe_to_fork: true}, event: %{id, type, payload}})` writes Agent, initial `await_input` checkpoint, first history event (`history_seq = 1`) and the command response together. Replaying the same command identity and params returns the stored response; different params is `conflict`.
- `accept_input(repo, %{command, agent_id, expected_version, expected_generation, turn_id, checkpoint: %{id, data, continuation, safe_to_fork}, event})` starts a new turn: CAS on `lock_version`+`generation`, `history_seq + 1`, checkpoint and event in one transaction. Reusing the head checkpoint's turn is `conflict`; a stale generation is `stale_generation`.
- `consume_result(repo, %{agent_id, expected_version, expected_generation, turn_id, operations: [%{operation_id, consumption_kind}], checkpoint})` verifies the head checkpoint's active turn, Operation owner Agent/turn and non-null accepted Result, then writes one `result.consumed` event per Operation in `ordinal` order plus the next checkpoint. Dedupe is `events(scope_id, dedupe_key)` with `dedupe_key = "consume:<operation_id>:<kind>"`; re-consuming the same batch replays the stored event ids, a partial overlap is `conflict`. A source/forked Agent's Operation is rejected by ownership.
- `fetch(repo, agent_id)` returns `%{"agent" => map, "head_checkpoint" => map | nil}`; `history_page(repo, agent_id, after_seq: 0, limit: 100)` returns `%{"events" => [...], "next_cursor" => seq | nil}` with limit 1..500 and a 4 MiB page budget (`limit` error for one oversized event).
- `OperationRecords.prepare(repo, %{operation: %{id, description, owner_agent_id?, turn_id?, tool_call_id?, ordinal?}, attempt: nil | %{attempt_id, executor_id, executor_boot_id, budget}, agent: nil | %{expected_version, expected_generation}, event})` writes the immutable Operation (description digest computed here), at most one `prepared` Execution and the history event (owned Operations share the Agent stream and require the Agent version). Replaying the same Operation id and description returns the stored response; another description or attempt is `conflict`.
- `claim_dispatch(repo, %{operation_id, attempt_id, expected_version})` CASes `prepared -> send_claimed` and returns only committed data. It never sends anything; an already claimed or stale attempt is `conflict`, so a caller cannot mistake a replay for permission to send twice.
- `record_evidence(repo, %{id, operation_id, attempt_id, executor_id, evidence_id, content, digest?, resolution?})` verifies the attempt/executor identity, computes the content digest and dedupes on `(executor_id, evidence_id)`: same digest replays, different digest is `conflict` and the original row stays.
- `accept_result(repo, %{operation_id, expected_version, result, event, evidence_id?, artifact_ids?, agent?})` CASes `accepted_result IS NULL`; it never overwrites an accepted Result. Identical retries replay; different results are `conflict`. Evidence references must belong to the Operation and artifact references are verified in the same transaction (`artifact_missing`), otherwise nothing is accepted.
- `fetch(repo, operation_id)` returns `%{"operation" => map, "attempt" => map | nil}`.
- `ExecutorJournal.claim_start(repo, %{id, authority_id, operation_id, attempt_id, description_digest, executor_id, executor_boot_id})` is insert-once on `(authority_id, attempt_id)`: a duplicate returns the stored state (including `terminal`/`unknown_after_restart`) and never restarts a worker; changed identity is `conflict`.
- `record_stop(repo, %{authority_id, attempt_id, stop_reason, expected_version})` writes only the first `deadline`/`cancelled` cause; competing triggers return the stored cause unchanged.
- `record_terminal(repo, %{authority_id, attempt_id, expected_version, termination, terminal_result, terminal_artifacts, receipt_id, receipt_digest, receipt})` writes the terminal state, validated attachments and receipt atomically, and only from `start_intent`. `unknown_after_restart` can never become terminal; an identical duplicate replays, different content is `conflict`.
- `acknowledge(repo, %{authority_id, attempt_id, expected_version})` records authority receipt acknowledgement only; it is idempotent and never implies the worker stopped.
- `mark_unknown_after_restart(repo, %{authority_id, executor_id, keep_executor_boot_id})` moves other boots' `start_intent` rows to `unknown_after_restart` and returns `%{"marked" => n}`; nothing ever converts that state into "not executed".
- `fetch(repo, authority_id, attempt_id)` returns the stored journal row; an unknown stable identity is `conflict`.

`conflict` is also the plain-data answer for an unknown stable identity or a state
that does not match the request; it never carries SQL, connection or secret
detail. No facade retries a write transaction, runs unbounded work or performs
network/handler/filesystem effects.

## Data and artifacts

`Codec.encode/2`, `decode/2`, `digest/2`, `hash/1`, `uuid?/1`, `limit/1` implement
strict persisted JSON, sorted-key SHA-256 and canonical UUID checking. Only plain
maps with string keys, proper arrays, valid UTF-8 strings, finite BEAM numbers,
booleans and null are supported. Duplicate JSON keys, live objects, arbitrary
structs, atom/tuple values and unknown schema columns are rejected, as are a fixed
set of credential key names (`credentials`, `api_key`, `token`, `password`,
`secret`, `authorization`, `private_key`, …) and keys with an underscore/dash-separated
credential segment such as `client_secret` or `bearer_token`. This is a heuristic
key check, not a secret scanner: `max_tokens` stays storable, and values inside
ordinary text are never inspected. Decode checks recursion before tree allocation. Traversal bounds
are depth 32 and 100000 nodes (keys included), with byte accounting before whole
JSON construction. JSON size is **not** existing ETF wire size. No text/binary
secret scanner is claimed; callers still own content policies and volume/backup
permissions. Codec does not normalize numeric types or Unicode strings.

Schemas live in `Beamlet.Storage.Schema.*`, with `changeset(record, attrs)`.
The parameterized `JSON` Ecto type validates canonical encoding on cast/dump/load,
including field-specific operation/command/result/checkpoint limits. Fixed column
names, UUIDs, versions, scalar ranges and enums are validated; record facades must
still validate each definition/description/result/event payload vocabulary and
references, cross-row ownership, content digests and transition immutability.
Provenance IDs do not become ancestor-loading dependencies. `tool_call_id` is a
bounded provider string, not required to be a UUID.

`Artifacts.changeset/1`, `put/2`, `fetch/2`, `verify_references/2` handle authority
binary content with SHA-256, media type and exact raw byte size (max 16 MiB).
`put` and reference validation require an existing transaction. Use them from
`Ecto.Multi.run`; content and referencing rows commit/roll back together.
`fetch` verifies content integrity; absent data returns `artifact_missing`.
There is no GC or external object store. Referencing JSON fields are not SQL FKs;
the record facade must call reference validation in its transaction.

Journal `terminal_artifacts` is a nullable JSON column with a **24 MiB encoded**
limit and a basic version-1 container check: `%{"version" => 1, "items" => %{}}`.
`Beamlet.Storage.TerminalArtifacts` owns the full attachment protocol:
`encode/1` requires the explicit container (empty items allowed), at most 64
canonical UUID keys mapped to exactly `digest`, `media_type`, `size_bytes`,
`content_base64`, strict canonical base64, per-item decoded <= **16 MiB** and
aggregate decoded per attempt <= **16 MiB**, encoded container <= **24 MiB**,
and verifies digest/size_bytes against the decoded bytes. `content/2` returns the
decoded bytes and `artifact_missing` for an unknown id. `ExecutorJournal`
additionally caps the four stored terminal fields at a **32 MiB** logical
transaction total and treats a duplicate terminal with different receipt,
result or attachment content as `conflict`. The journal cannot resolve authority
artifact rows; authority reference integrity is enforced by
`OperationRecords.accept_result/2` via `Artifacts.verify_references/2` in the
authority transaction. Artifacts never bypass existing legal Result/wire limits.
Authority attachment transfer is a different database transaction, not cross-DB
atomicity.

## Read-only history queries

`Beamlet.Storage.History` answers history questions from committed facts only; it
never starts an Agent, coordinator or Runtime retention window. Pages are keyset
paginated as one bounded statement each, with no enclosing read transaction. Event
and checkpoint pages are bounded by rows plus a byte budget, the turn and operation
views by rows only (`:limit` 1..500, `:max_bytes` 4096..4 MiB). A page never splits a record: a
record larger than the byte budget is returned alone with `over_budget: true` and
stays bounded by its own codec limit.

- `event_page(repo, scope_id, after_seq:, through_seq:, limit:, max_bytes:, type:, types:, turn_id:, operation_id:, origin:)` returns `%{"events", "next_cursor", "over_budget", "through_seq"}` with `origin` = `performed` | `inherited` per entry (an entry whose `source_agent_id` names another Agent is inherited, never this scope's work).
- `event(repo, scope_id, seq)`, `checkpoint_at(repo, agent_id, seq)`, `checkpoint_page(repo, agent_id, after:, through_recorded_at:, limit:, max_bytes:)`.
- `turns(repo, agent_id, after_first_seq:, limit:)`, `operations(repo, agent_id, after_history_seq:, limit:)`, `operation(repo, operation_id)`, `evidence(repo, operation_id)`.

Checkpoints carry no history sequence. `checkpoint_at/3` therefore maps an event
cursor to the newest checkpoint committed at or before that event and returns
`derived_by: "commit_order"`; a checkpoint written in the same transaction as its
event is visible at that sequence. Checkpoints are immutable, so later evidence
never rewrites an earlier `as_of_seq` answer.

## Focused checks

```sh
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix credo
# Requires an isolated cluster: BEAMLET_PG_SOCKET_DIR / BEAMLET_PG_PORT.
# Without it the PostgreSQL contract module fails loudly (no silent skip).
mix test apps/beamlet_storage/test
BEAMLET_BACKEND_BUILD=1 mix compile --warnings-as-errors
BEAMLET_BACKEND_BUILD=1 mix test apps/beamlet_storage/test
```

SQLite-only files can be run without PostgreSQL, for example
`mix test apps/beamlet_storage/test/beamlet/storage/dataset_test.exs`.

Tests create isolated files under the system temporary directory and remove their
own directories. No existing databases or credentials are needed for this SQLite
component suite when only SQLite is under test. The dual-adapter contract suite
additionally needs an isolated PostgreSQL cluster:

```sh
BEAMLET_PG_SOCKET_DIR=/tmp/<cluster>/sock BEAMLET_PG_PORT=5439 \
  mix test apps/beamlet_storage/test
```
