# State and Persistence

Dataset format3 foundation/domain contracts live in the Storage/Runtime app
READMEs and [Event-reduced Agent](./agent-durable.md). Agent checkpoints contain
control/references, never messages/assistant. Original input is committed before
requests; acceptance digests are checked even for pending outputs. Reference fork
and format2 offline trace export are implemented; see the Agent README. No old
transcript API, automatic migration or compatibility fallback exists. Independent
product acceptance remains separate from implementation-stage evidence.

## Current Scope: Ephemeral and Opt-in Durable Modes

Beamlet implements opt-in Ecto storage through `apps/beamlet_storage` and the
server host's `storage:` configuration. Without durable wiring, the process-state
boundaries below remain ephemeral.
Runtime owns ephemeral process state: Directory snapshots, coordinator terminal
retention, and gateway admission accounting/tombstones. None survives infrastructure
restart. Node composes configured roles (empty by default). Agent retains bounded
context/turn/subscriber/peer state and one immutable model binding in private Server
memory. Binding config/credentials are explicit creation inputs; model Operations
carry transient invocation copies. Registry metadata stores trusted local adapter
registrations, not user bindings/keys. No credential persistence, recovery or
secure-erasure guarantee exists. Resources retains infrastructure PID inventories
until DOWN, with VM-local restart fencing and no business replay state. Without the
opt-in durable host wiring below, there is no Agent/Operation history beyond this
ephemeral state. Agent's bounded live-context display and subscriptions
can omit or truncate content; their annotation IDs are incarnation-local. Node and
Runtime observations are non-atomic advisory reads. Node services `ready` means
required local registrations exist, not database writability or confirmed worker
termination. None is a persistence or recovery fact source. See [Agent and Node](./agent-orchestration.md). See [Operation Runtime](./operation-runtime.md).

Runtime refs address live coordinators; status is unavailable after expiry or
shared infrastructure loss. Do not turn retained Results/tombstones into replay or
durable deduplication promises.

## Scenario: explicit format3 installation and domain composition

### 1. Scope / Trigger

Use for dataset/schema, transaction, content or host changes. Foundation is
`Beamlet.Storage`; Actions persistence is `Beamlet.Actions.Storage`; Agent
persistence is `Beamlet.Agent.Storage`. Foundation knows neither domain.
Read [Storage README](../../../apps/beamlet_storage/README.md) and
[Agent Storage README](../../../apps/beamlet_agent_storage/README.md).

### 2. Signatures

```elixir
Installation.validate(%{profile: "actions-authority", format_version: 3,
  components: [Installation.foundation_component(), Profiles.authority_component()],
  migrations: [Installation.foundation_migration(), Profiles.authority_migration()]})
# :ok | {:error, :invalid_data}; Profiles = Beamlet.Actions.Storage.Profiles
Dataset.initialize(repo, descriptor: descriptor, dataset_id: uuid, database: path,
  peer_database: other_path) # {:ok, linked_pid} | {:error, reason}
Dataset.open(repo, opts)   # same successful return; caller owns Repo shutdown
Dataset.verify(repo, opts) # :ok | {:error, reason}; no installation
Transaction.write(repo, fun_or_multi)
Transaction.participate(repo, fun) # requires existing transaction on this Repo
Codec.encode(value, max_bytes) # {:ok, canonical_json} | {:error, :invalid_data | :limit}
Codec.decode(bytes, max_bytes)
Codec.digest(value, max_bytes) # {:ok, lowercase_sha256_hex} | {:error, reason}
Host.start_link(datasets: [%{key: :resource, repo: repo, options: opts}])
Host.handles(host)
Host.status(host)
Admission.start_link([repo: repo, resources: [{other_repo, other_opts}]] ++ opts)
Admission.status(gate) # fresh verification and rollback write probes
Admission.consult(gate) # honors recorded failures
Beamlet.Node.Storage.configuration(roles, storage)
Beamlet.Node.Storage.datasets(roles, storage)
Beamlet.Node.Storage.runtime() # {:ok, %{authority_repo:, journal_repo:, executor_id:, executor_boot_id:}}
Beamlet.Node.Storage.Operator.initialize(roles, storage)
# {:ok, %{authority: :installed | nil, journal: :installed | nil}} | {:error, reason}
```

### 3. Contracts

Descriptors are trusted compiled code, never module names selected from disk/network.
Exact keys are `profile`, `format_version: 3`, ordered `components` and `migrations`.
Components have exact `name`/positive `version`; migrations have exact positive
`id`/`component`/compiled Ecto migration `module`. Foundation is first/version1/ID1;
component names and migration modules are unique, IDs unique and strictly ordered,
and every component has migrations. Invalid descriptors refuse before file creation
or Repo startup. Installed migration implementations must remain immutable; the
manifest binds module identities, not source hashes.

| Profile constructor | Profile | Ordered components (all version1) | Ordered migration IDs/modules |
| --- | --- | --- | --- |
| Actions `Profiles.authority/0` | `actions-authority` | foundation, actions-authority | 1 Storage.Migrations.FoundationV1; 100 Actions.Storage.Migrations.AuthorityV1 |
| Actions `Profiles.journal/0` | `actions-journal` | foundation, actions-journal | 1 FoundationV1; 200 Actions.Storage.Migrations.JournalV1 |
| Agent `Profiles.authority/0` | `agent-authority` | foundation, actions-authority, agent | 1 FoundationV1; 100 AuthorityV1; 300 Agent.Storage.Migrations.AgentV1 |

Module identities above have prefix `Beamlet.`. Foundation installs only `artifacts`,
`storage_metadata` and Ecto `schema_migrations`. Metadata singleton ID1 records
`dataset_id`, `profile`, `format_version`, `restored_backup`, exact JSON `manifest`
and `installed`. Manifest includes ordered component name/version and migration
id/component/module strings. Initialization writes installed=false, runs the complete
list, then marks installed=true. Open/verify require that marker and the exact ordered
IDs from `schema_migrations`; partial installs never become usable.

Actions authority owns `operations`, `executions`, `execution_evidence`,
`operation_events`, `dispatch_scopes`; journal owns `journal_attempts`. Agent owns
`agents`, `agent_events`, `commands`, `checkpoints`, `agent_operations` and the
read-only `agent_operation_projections` view. Agent associations hold owner/turn/
step/role/tool-call/ordinal/generation/prepared_seq/ordered sources; neutral Operations
hold none of these fields or Agent FKs. Foundation artifacts have no domain FK.

Define Repos with `use Beamlet.Storage.Repo, adapter: :sqlite | :postgres` or use
explicit neutral/domain instances; never infer a profile from a Repo name.
Dataset UUID must be canonical. SQLite requires absolute distinct `database` and
`peer_database`, detects path aliases, checks format read-only before writable
startup, and uses pool1/WAL/FULL/FK, immediate writes, 2000ms Exqlite busy handler
(`PRAGMA busy_timeout` reads0). PG uses pool4, a provisioned empty database and
explicit connection options, checking fsync/synchronous_commit. PG refusal uses
read-only queries. No new multi-authority-instance promise is implied.

`Transaction.write/2` owns the one commit/rollback. Participants require the same
Repo's already-open transaction, validate domain inputs and neither commit nor
perform external effects; caller must roll back any returned error. Agent composes
Actions participants, associations, Agent events and command response atomically.
See [Agent durability](./agent-durable.md) and [Runtime](./operation-runtime.md)
for lock order, dispatch and acceptance contracts. Product callers receive facades,
not raw Repo/SQL. No automatic write/effect retry follows an unknown outcome.

Foundation Codec takes positive numeric byte bounds (default4194304), not domain
kind atoms. Canonical sorted UTF-8 JSON preserves integer/float spelling and SHA-256
bytes; duplicate keys, invalid UTF-8, live data, structs and structured credential
fields refuse, with depth32/node100000 budgets. Strings are not a secret scanner.
Foundation JSON requires `max_bytes:`; domain codecs/JSON own kind policies.
Artifacts stay digest-deduplicated, bounded to16MiB and verified by References.

Generic Host opens only explicit descriptors, retains refused reasons, owns only
successfully opened Repos and never automatically reopens. Generic Admission probes
its primary resource and every `resources: [{repo, opts}]` dependency; failure turns
admission off until a fresh successful probe. Repo registration/Node ready is no
writability evidence. Node.Storage explicitly selects Agent authority and Actions
journal for configured roles, supplies fresh boot identity and starts the default
Admission gate covering both resources. Optional trusted server `storage:` retains
adapter/database/dataset_id/journal/executor_id and PG connection fields; SQLite
journal keys are database/dataset_id/peer_database as applicable. `runtime/1` grants
no admission itself. Absent storage and interaction-only Node composition start no
Repo/gate. Loading libraries starts nothing.

Explicit `mix beamlet.storage.migrate` belongs to Node, calling Node.Storage.Operator.
Operator stops only Repos acquired by successful initialization; existing owners
survive conflict. Boot/open/verify never initialize, migrate, convert or repair.
Old authority2/journal1 safely refuse without writes; there are no old facades or
automatic conversions. Use fresh paths; rollback uses old code with its untouched
old dataset. Consistent SQLite `.backup`/`VACUUM INTO` or PG dump/basebackup only;
restored_backup is an explicit operator marker, not automatic rollback detection.

### 4. Validation & Error Matrix

| Condition | Required observation |
| --- | --- |
| Invalid descriptor/config/UUID | `:invalid_data` before installation |
| SQLite same/aliased peer path | `:path_alias` |
| Missing open/file/metadata table | `:dataset_missing`; no creation |
| Installed target on initialize | `:dataset_exists`; no overwrite |
| Already registered same Repo | `:conflict` before file access |
| Wrong dataset identity/profile | `:dataset_mismatch` |
| Old/new format, incomplete/changed component manifest or migration list | `:schema_unsupported`; no writes |
| Backup marker | `:restored_backup` |
| Participant outside transaction | `:transaction_required` |
| Deterministic unique / check, FK or invalid type violation | `:conflict` / `:invalid_data`; rollback |
| Read driver failure/stopped Repo | `:storage_unavailable`, never absence |
| Unclassified write/connection failure | `:storage_outcome_unknown`; reconcile stable IDs |
| Codec malformed data / bounds exceeded | `:invalid_data` / `:limit` |
| Invalid Node storage block | `:invalid_storage_configuration` |
| Node storage absent / missing role dataset | `:storage_not_configured` / `:authority_not_configured` / `:journal_not_configured` |

Strict JSON struct-load normalization must apply to reads AND write facades;
see [Error Handling](./error-handling.md#scenario-strict-persisted-json-failure).

### 5. Good/Base/Bad Cases

Good: explicitly initialize Actions-only authority+journal and run a generic
Handler with no Agent tables/config. Base: loading all persistence libraries starts
no Repo. Bad: open an old dataset hoping to install missing components, silently
interpret read failure as no row, or stop an existing host Repo after init conflict.

### 6. Tests Required

Foundation `foundation_test.exs`, codec and fresh-VM tests assert descriptor failure
before creation, exact metadata/completion/IDs, old2/old1 byte/schema/business-content
preservation, read-only refusal and numeric bounds. Actions owning contracts assert
exact Agent-free schemas, prepare/claim/evidence/accept/reopen and journal restart
semantics. Agent dataset/domain suites retain installation, connections, contention,
rollback and projection assertions on SQLite and actual PG. Node host tests cover
both-resource admission, stopped journal, owned shutdown and interaction-only mode.
Use private PG via BEAMLET_PG_SOCKET_DIR/BEAMLET_PG_PORT/BEAMLET_PG_USER; never count
excluded adapters as passed. Exact final counts and reviewed assertion transfer are
in the [independent review](../../tasks/archive/2026-10/10-18-storage-action-decoupling/research/independent-review.md).

### 7. Wrong vs Correct

Wrong: foundation selects Agent migrations or domain byte limits from a Repo/kind;
perform Agent prepare and Actions prepare in separate commits.
Correct: composition supplies a complete trusted descriptor; domain codecs supply
numeric bounds and same-Repo participants share a single outer rollback boundary.

## Architecture and Delivery Contract

The [Agent / Operation design](../../../docs/architecture/agent-operation-persistence.md)
is implemented through the format3 foundation/domain Storage and Runtime and event-reduced Agent path.
Agent owns original input/decisions/control, Operation owns the fixed logical request; Agent associations own ordered
sources, and accepted Result owns output. Replay performs no effects; caches
are optional and currently revalidate their history prefix. There is no Branch,
transcript-copy fork, graph authority table or source-parent history recursion.

Same-dataset fork creates independent paused control plus a flat validated reference
manifest; original input content is shared through immutable digest-deduplicated
artifacts, and inherited Operations remain source-owned. Source facts are retained;
no GC is implemented. Full history and reference content remain sufficient without
checkpoint, live Agent, provider or executor. Missing/damaged content blocks.
History/export fix high waters, preserve source provenance and never count inherited
usage as new execution. Redaction explicitly prevents restoration claims.

Durable writes remain business transitions, not snapshots/subscriptions. First stop
trigger and actual termination are separate evidence; cancel/deadline never rewrite
accepted Results. Admission is checked independently of Repo/Node registration.
Real adapter, process-window, named-peer and release results belong in the [independent review](../../tasks/archive/2026-10/10-18-storage-action-decoupling/research/independent-review.md), not inferred from archived Stage A–F's old representation. No physical
host, power-cut, paid provider or external exactly-once guarantee is claimed.

## Existing State Boundaries

`apps/beamlet_app_web/lib/beamlet_web/endpoint.ex` configures a cookie session:

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
persistence service (`apps/beamlet_app_web/lib/beamlet_web/router.ex`).

Other current state is boundary-local: the router assigns a fresh CSP nonce per
request, and `apps/beamlet_app_web/lib/beamlet_web/components/layouts/root.html.heex`
stores a theme preference in browser `localStorage`. Neither is Agent storage.
`config/runtime.exs` supplies production `SECRET_KEY_BASE` from the environment;
`config/dev.exs` and `config/test.exs` have local-only defaults.

## Misleading Scaffolding to Check

`apps/beamlet_app_web/test/support/conn_case.ex` mentions SQL sandboxing in its
generated module documentation, but its actual setup only returns
`{:ok, conn: Phoenix.ConnTest.build_conn()}`. No SQL sandbox is configured.
`apps/beamlet_app_web/lib/beamlet_web/components/core_components.ex` accepts
`Phoenix.HTML.FormField` and translates error tuples; that UI helper is not proof
of Ecto changesets or persisted models. Web `priv/` contains static and translation resources, not database migrations.

When changing state behavior, trace its real owner first and specify lifetime,
visibility, and failure behavior in the task. Do not add database setup or
sandbox calls to existing connection tests on the strength of generated comments.
