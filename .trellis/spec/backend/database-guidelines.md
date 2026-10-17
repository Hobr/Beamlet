# State and Persistence

## Current Scope: No Database Layer

Beamlet has no implemented database, ORM, Repo, schemas, migrations, queries, or
transactions. None of `apps/*/mix.exs` declares Ecto or a database adapter, and
`mix.lock` has no resolved Ecto package entry. LiveDashboard's lock metadata lists
optional Ecto integrations, but those are not selected as resolved packages.
Runtime owns ephemeral process state: Directory snapshots, coordinator terminal
retention, and gateway admission accounting/tombstones. None survives infrastructure
restart. Node composes configured roles (empty by default). Agent retains bounded
context/turn/subscriber/peer state and one immutable model binding in private Server
memory. Binding config/credentials are explicit creation inputs; model Operations
carry transient invocation copies. Registry metadata stores trusted local adapter
registrations, not user bindings/keys. No credential persistence, recovery or
secure-erasure guarantee exists. Resources retains infrastructure PID inventories
until DOWN, with VM-local restart fencing and no business replay state. There is no
durable Agent/Operation history. Agent's bounded live-context display and subscriptions
can omit or truncate content; their annotation IDs are incarnation-local. Node and
Runtime observations are non-atomic advisory reads. Node services `ready` means
required local registrations exist, not database writability or confirmed worker
termination. None is a persistence or recovery fact source. See [Agent and Node](./agent-orchestration.md). See [Operation Runtime](./operation-runtime.md).

Runtime refs address live coordinators; status is unavailable after expiry or
shared infrastructure loss. Do not turn retained Results/tombstones into replay or
durable deduplication promises.

## Implemented Storage Foundation (Stage A Only)

`apps/beamlet_storage` is a real, tested Ecto library for the persistence contract;
it is **not** wired into Agent/Runtime/Node and no durable business recovery runs.
Read `apps/beamlet_storage/README.md` before changing it. Established facts:

- Authority tables: `agents`, `checkpoints`, `events`, `operations`, `executions`,
  `execution_evidence`, `commands`, `artifacts`, plus the singleton
  `storage_metadata` installation row and Ecto's `schema_migrations`. The executor
  journal database has `journal_attempts` + `storage_metadata`.
- Migrations are explicit and versioned: `Dataset.initialize/2` runs
  `priv/authority_migrations/1_authority_v1.exs` or
  `priv/journal_migrations/1_journal_v1.exs`; `Dataset.open/2` never migrates and
  refuses a missing dataset, identity/role mismatch, backup marker, or newer
  `format_version`/migration version. Downgrade raises by design.
- Write entries are `Beamlet.Storage.{AgentRecords, OperationRecords,
  ExecutorJournal}` only; each is one transaction (`Transaction.write/2`) with CAS
  on `lock_version`, unique constraints as the concurrency fact, command identity
  replay and no automatic retry. Do not expose Repos or raw SQL upward.
- SQLite runs pool size 1, WAL, `synchronous=FULL`, `foreign_keys=ON`, immediate
  write transactions, and a 2000 ms Exqlite busy handler; `PRAGMA busy_timeout`
  reads 0 by design. PostgreSQL runs pool size 4 with `after_connect` checks of
  `synchronous_commit`/`fsync`.
- Contract tests: `apps/beamlet_storage/test/beamlet/storage/storage_contract_test.exs`
  runs one shared assertion set on real SQLite files and on a real PostgreSQL
  dataset (`test/support/contract_fixture.ex`); SQLite-only suites cover the
  executor journal, codec and installation. Never report a skipped adapter as
  passing.

## Implemented Durable Host Wiring (Stage F)

`Beamlet.Storage.Host` is the only host wiring. `Beamlet.Daemon.configuration/1`
accepts an optional trusted `storage:` block (`:adapter` `:sqlite` default or
`:postgres`, `:database`, `:dataset_id`, `:journal` `[:database, :dataset_id,
:peer_database]`, `:executor_id`); it opens only the datasets the configured roles
need, mints one `executor_boot_id` per boot and exposes the durable wiring through
`Host.runtime/1`. Absent `storage:` means no Repo and no database. Loading the
library and the interaction-only/CLI hosts start nothing.

`Beamlet.Storage.Admission` is durable admission, distinct from Node/Repo
readiness: every `status/1` call re-runs `Dataset.verify/2` plus a real
rolled-back write probe, `Failure/2` turns it off after a failed durable write, and
the durable submit (`Beamlet.Runtime.submit/2` with `persistence:`) and accept
(`OperationCoordinator`) paths refuse with `:unavailable` / `:durable_unavailable`
while it is off. Never report admission from a cached observation or from `ready`.

Migration stays an explicit operator action (`mix beamlet.storage.migrate` or
`Beamlet.Storage.Operator.initialize/2` inside a release). Boot, Agents and
`Dataset.open/2` never migrate, create or repair a dataset: missing, newer-format,
identity-mismatched and `restored_backup` datasets are refused. Consistent database
backups only (SQLite `.backup`/`VACUUM INTO`, `pg_dump`/`pg_basebackup`); a
restored dataset pauses admission until an operator resolves the marker.

## Proposed Next Architecture (Not Implemented)

The documentation-only [Agent / Operation persistence proposal](../../../docs/architecture/agent-operation-persistence.md)
extends the archived distributed architecture with Ecto, authority-owned SQLite or
PostgreSQL, an executor-local SQLite evidence journal, paused recovery, history,
trace export, and rewind by copying a safe checkpoint's effective context into a
new Agent. The user accepted its core direction and the removal of standalone
branches. These decisions remain design material, not a checked-in storage
convention. The [mechanism study](../../../docs/architecture/research/durable-agent-mechanisms.md)
compares pinned pi durable source with LangGraph, Agents SDK and Temporal, and
limits durable primitives to history records and checkpoints. Fork returns a new
Agent identity with materialized context and provenance; it does not introduce
branch tables, active-branch switching or recursive parent-history loading. Consult its [delivery and acceptance plan](../../../docs/architecture/persistence-delivery.md)
when scoping future implementation. Stage A storage exists (above); stages B–F
(durable Agent/Runtime behaviour, fork/rewind, export, recovery, release tooling)
remain design material and are not implemented.

The proposal remains compatible with the display/observation and stop-provenance
changes through `a078aa3`. Future durable writes must occur at business transitions,
not by recording display snapshots or subscriptions. Preserve the first observed
stop trigger and actual terminal outcome in execution evidence; cancellation
requests must not rewrite deadline or successful Results. Enforce durable admission
in authority transactions and executor journal writes even when Node/Repo processes
remain registered. See proposal sections 3.3, 6 and 11 for the full contract; these
requirements add no Display/Observation table or new durable primitive.

## Existing State Boundaries

`apps/beamlet_web/lib/beamlet_web/endpoint.ex` configures a cookie session:

```elixir
@session_options [
  store: :cookie,
  key: "_beamlet_web_key",
  signing_salt: "HwX5hC6W",
  same_site: "Lax"
]
```

The endpoint passes these options to both LiveView socket transports and
`Plug.Session`. As the source comment states, the session is **signed, not
encrypted**: clients can read its contents. Keep sensitive server-only data out
of it. The browser pipeline fetches the session; this is not a server-side
persistence service (`apps/beamlet_web/lib/beamlet_web/router.ex`).

Other current state is boundary-local: the router assigns a fresh CSP nonce per
request, and `apps/beamlet_web/lib/beamlet_web/components/layouts/root.html.heex`
stores a theme preference in browser `localStorage`. Neither is Agent storage.
`config/runtime.exs` supplies production `SECRET_KEY_BASE` from the environment;
`config/dev.exs` and `config/test.exs` have local-only defaults.

## Misleading Scaffolding to Check

`apps/beamlet_web/test/support/conn_case.ex` mentions SQL sandboxing in its
generated module documentation, but its actual setup only returns
`{:ok, conn: Phoenix.ConnTest.build_conn()}`. No SQL sandbox is configured.
`apps/beamlet_web/lib/beamlet_web/components/core_components.ex` accepts
`Phoenix.HTML.FormField` and translates error tuples; that UI helper is not proof
of Ecto changesets or persisted models. `priv/` currently contains static and
translation resources, not database migrations.

When changing state behavior, trace its real owner first and specify lifetime,
visibility, and failure behavior in the task. Do not add database setup or
sandbox calls to existing connection tests on the strength of generated comments.
