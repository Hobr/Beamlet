# Stage F evidence — durable release operations

Date: 2026-10-18. Branch `feat/durable`. Prerequisites committed: A `3aefa85`,
B `11577fb`, C `f7be001`, D `22d6159`, E `c4b37fd`. This sub-agent committed
nothing; the parent owns the index and the commit.

Scope: durable storage made deployable and operationally honest in the existing
hosts. No new table, schema, migration content, background job, queue, lease,
scheduler, consensus or failover. Ephemeral behaviour, Node readiness semantics
and Runtime/Agent execution rules are unchanged.

## Callable surface

```elixir
# Configuration (trusted operator config, daemon namespace only)
Beamlet.Daemon.configuration/1        # accepts :storage; {:error, :invalid_daemon_configuration}
Beamlet.Storage.Host.configuration/2  # (roles, raw :storage) -> normalized settings
Beamlet.Storage.Host.datasets/2       # (roles, raw :storage) -> dataset options per role

# Host wiring (started only by a host that configures storage)
{Beamlet.Storage.Host, storage: normalized}
Beamlet.Storage.Host.runtime/1        # {:ok, %{authority_repo:, journal_repo:, executor_id:, executor_boot_id:}}
Beamlet.Storage.Host.status/1         # %{admission:, datasets: %{authority:|journal:}, boot_id:}

# Durable admission (distinct from Node/Repo readiness)
Beamlet.Storage.Admission.status/1    # :admitted | {:refused, reason} | :not_configured
Beamlet.Storage.Admission.consult/0   # :ok | {:error, :durable_not_admitted}
Beamlet.Storage.Admission.failure/2   # a failed durable write turns admission off
Beamlet.Storage.Admission.probe/2     # format/migration check + real rolled-back write

# Explicit operator action (never implicit in boot, Agent or open)
Beamlet.Storage.Operator.initialize/2 # (roles, raw :storage) -> %{authority:, journal:}
mix beamlet.storage.migrate --storage /abs/storage.exs --roles authority,executor

# Reused stage-A verification, now public for admission/operators
Beamlet.Storage.Dataset.verify/2      # read-only format/identity/migration check
```

## Configuration keys (daemon release)

`config/config/daemon.example.exs`-style trusted operator file, read through
`BEAMLET_CONFIG`. Omit `storage:` and the host stays ephemeral and starts no
database.

```elixir
config :beamlet_daemon,
  enabled: true,
  node: [roles: [:authority, :executor]],
  storage: [
    adapter: :sqlite,                                  # :sqlite (default) | :postgres
    database: "/var/lib/beamlet/authority.db",          # SQLite file (absolute, local)
    dataset_id: "<authority dataset uuid>",             # operator-owned, stable
    journal: [
      database: "/var/lib/beamlet/journal.db",          # executor-local SQLite file
      dataset_id: "<journal dataset uuid>",
      peer_database: "/var/lib/beamlet/authority.db"    # only required for :postgres
    ],
    executor_id: "<stable executor identity uuid>",     # per deployment, not per boot
    # :postgres only: database: "<db name>", hostname: | socket_dir:, port:, username:, password:
  ]
```

| Key | Required for | Meaning |
| --- | --- | --- |
| `:adapter` | optional | `:sqlite` (default) or `:postgres` authority adapter |
| `:database` | always for SQLite | SQLite authority path, or the PostgreSQL database name |
| `:dataset_id` | authority role | Authority dataset identity; a mismatch refuses open |
| `:journal` | always for SQLite | `:database`, `:dataset_id`, and for PostgreSQL also `:peer_database` |
| `:executor_id` | any storage | Stable durable executor identity of this VM |
| `executor_boot_id` | generated per boot | Not configured; the Host mints one per start |
| `:hostname`/`:socket_dir`/`:port`/`:username`/`:password` | `:postgres` | Trusted connection input, never logged or persisted in records |

Repos start only for the roles that need them. Interaction-only is a Node
library role set and starts nothing, and `roles: [:executor]` opens no authority
dataset and no Agent authority. One caveat comes from the SQLite peer/alias guard:
the two datasets must never alias, so a SQLite block always has to name both the
authority and the journal path even for `roles: [:authority]` (the journal file is
then not opened, only used as the alias check). An authority-only SQLite block with
no `journal:` is refused as an invalid configuration. Loading `beamlet_storage` starts no Repo and no admission process.
The CLI host is fixed interaction-only: its configuration accepts no `storage:`
key (unknown keys are rejected) and its release runs without a database.

## Durable admission vs readiness

- Node `services.* = ready` keeps its meaning: the required local registrations
  exist. It is never used as durable admission.
- `Beamlet.Storage.Admission.status/1` probes on **every** call: it reads
  `storage_metadata` + `schema_migrations` (`Dataset.verify/2`) and then performs a
  real write (`UPDATE storage_metadata SET format_version = format_version WHERE id = 1`)
  inside a transaction that is rolled back. Nothing is committed: lock acquisition
  and the page/WAL write path are exercised, but no commit and therefore no fsync
  happens, so a torn-write/fsync test would still be a separate requirement.
- A configured dataset that was refused at boot keeps that reason, whether it is
  the authority or the journal dataset: a lost journal pauses admission too,
  because durable execution could not record its evidence. Fixing the dataset
  requires an explicit host restart, never a silent repair.
- A refused dataset returns `{:refused, reason}` (`:dataset_missing`,
  `:dataset_mismatch`, `:schema_unsupported`, `:restored_backup`, `:write_failed`,
  `:storage_unavailable`). A cached observation is never reported: the probe runs
  each time, so recovery re-admits without a restart.
- Durable submit (`Beamlet.Runtime.submit/2` with `persistence:`) consults it
  before committing an Operation and returns `{:error, :unavailable}` while off,
  dispatching nothing. The durable accept path (`OperationCoordinator`) consults it
  before `OperationRecords.accept_result/2` and reports `:durable_unavailable`
  instead of committing. A storage failure reported by either path calls
  `Admission.failure/2`, which turns admission off until the next probe succeeds.
- A VM with no started admission process (`:not_configured`) is a library/embedding
  caller that owns its own admission; hosts that configure storage always start it.

## Operator commands

```sh
# 1. Install/migrate once, as an explicit operator action (never at boot).
#    The file holds deployment paths: keep it out of the repository.
mix beamlet.storage.migrate --storage /etc/beamlet/storage.exs --roles authority,executor
#    -> installed %{authority: :installed, journal: :installed}
#    Re-running refuses with {:error, {:authority, :dataset_exists}} — never recreates.
#    Inside a built daemon release, the same action without mix:
#    bin/beamlet_daemon eval 'Beamlet.Storage.Operator.initialize([:authority, :executor], [...])'

# 2. Start the host (release). Startup only opens existing, verified datasets.
BEAMLET_CONFIG=/etc/beamlet/daemon.exs RELEASE_NODE=... RELEASE_COOKIE=... \
  bin/beamlet_daemon start

# 3. Inspect admission and dataset state.
bin/beamlet_daemon eval 'Beamlet.Storage.Host.status()'
#    %{admission: :admitted, datasets: %{authority: :ready, journal: :ready}, boot_id: "..."}
```

## Backup and restore runbook

1. Take a **consistent database backup**, never a copy of a live SQLite file:
   `sqlite3 /var/lib/beamlet/authority.db ".backup '/backup/authority.db'"`
   (or `VACUUM INTO '/backup/authority.db'`) for each dataset; PostgreSQL uses
   `pg_dump -Fc` / `pg_basebackup`. Stop the host for a filesystem snapshot, or use
   the database's own consistent-copy command while it runs.
2. Restore into an **isolated** deployment directory/database first, never over a
   live dataset.
3. Mark a restored dataset explicitly before use:
   `sqlite3 /backup/authority.db "UPDATE storage_metadata SET restored_backup = TRUE WHERE id = 1"`
   (PostgreSQL: `UPDATE storage_metadata SET restored_backup = TRUE WHERE id = 1`).
4. Start the host: it boots, but `Dataset.open/2` refuses `:restored_backup`, so
   `Host.status/1` reports `datasets: %{authority: {:refused, :restored_backup}}`
   and `admission: {:refused, :restored_backup}`. No durable submit or accept is
   admitted; nothing is recreated or silently repaired.
5. An operator reviews the restored facts (lost journal, missing events, an
   uncertain external effect) and resolves them: settle outstanding Operations,
   then clear the marker
   `UPDATE storage_metadata SET restored_backup = FALSE WHERE id = 1` and restart.
   A lost journal alone leaves `unknown_after_restart` attempts; nothing converts
   them into "not executed".
6. Newer format/migration versions and identity mismatches are refused the same
   way and are **not** downgraded or re-initialised; they require a reviewed
   upgrade, not a restart loop.

## Role matrix (tests)

| Role set | Authority Repo | Journal Repo | Admission | Agent authority |
| --- | --- | --- | --- | --- |
| library load / interaction-only | no | no | no | no |
| `[:authority]` + storage | yes | no | admitted | yes |
| `[:executor]` + storage | no | yes | no process | no (`Agent.Registry` nil) |
| `[:authority, :executor]` + storage | yes | yes | admitted | yes |
| no `storage:` | no | no | no | per roles |

## End-to-end verification path

`scripts/deployment/durable-e2e.sh` runs the scenario as **two OS processes**
against the same real files (phase one commits, its host process exits; phase two
is a new process). The same phases also run inside one VM as the ordinary
`Beamlet.Daemon.DurableEndToEndTest` test.

| Step | What it proves |
| --- | --- |
| `mix beamlet.storage.migrate` (Operator) | Installation is an explicit operator action; two datasets, one install, never recreated |
| Host boot + `Host.status()` | Only the configured datasets open; admission is a live probe, not readiness |
| Durable Agent turn with deterministic model + Tool | One durable Operation through Agent **and** Runtime: Operation + prepared attempt committed before dispatch, journal start intent, evidence, accepted Result, consumed result, `reply_recorded` checkpoint |
| Stop the host wiring, new process/reopen | Storage is the authority: the new process re-probes admission and reopens the same dataset identities |
| `Agent.restore/3` | Restored instance is **paused**; zero model calls or Tool dispatches before an explicit operator action |
| `Agent.continue/4` (explicit decision) | The operator continues the paused instance; the stored reply is replayed, not re-requested from the model |
| `Agent.input/3` | A new durable turn runs after restart with the same dataset |
| `Agent.export/3` + `TraceExport.verify/1` | Bounded export of committed facts verifies: event/checkpoint counts and digests |
| `Agent.fork/4` | The safe `await_input` boundary is copied; a `reply_recorded` checkpoint is refused with `:unsafe_checkpoint` because its stored reply is undecided pending state |
| Fork export + verify | The forked Agent's own trace verifies and carries the provenance event |

## Commands actually run and their counts

```sh
mix test                                   # 349 passed, 44 excluded (9 apps; exit 0)
mix test apps/beamlet_daemon/test           # 13 passed, 4 excluded
mix test apps/beamlet_node/test             # 68 passed, 20 excluded
mix test apps/beamlet_storage/test          # 57 passed, 13 excluded
mix test apps/beamlet_runtime/test          # 53 passed, 6 excluded
mix test apps/beamlet_daemon/test/beamlet/durable_host_test.exs \
          apps/beamlet_daemon/test/beamlet/durable_e2e_test.exs   # 8 passed, 2 excluded
mix test apps/beamlet_storage/test/beamlet/storage/host_storage_test.exs   # 6 passed
mix test apps/beamlet_runtime/test/beamlet/durable_admission_test.exs      # 1 passed
mix format --check-formatted                # exit 0 (after formatting the touched files)
MIX_ENV=test mix compile --warnings-as-errors   # exit 0
DURABLE_E2E_DIR=/tmp/beamlet-e2e-run bash scripts/deployment/durable-e2e.sh
                                            # phase 1: 1 passed, 2 excluded
                                            # phase 2: 1 passed, 2 excluded
mix beamlet.storage.migrate --storage /tmp/beamlet-rel/storage.exs \
    --roles authority,executor              # installed %{authority: :installed, journal: :installed}
MIX_ENV=prod BEAMLET_BACKEND_BUILD=1 mix release beamlet_daemon --overwrite  # exit 0
MIX_ENV=prod BEAMLET_BACKEND_BUILD=1 mix release beamlet_cli --overwrite     # exit 0
```

New tests (all over real SQLite files; no in-memory database):

- `apps/beamlet_storage/test/beamlet/storage/host_storage_test.exs` (6): operator
  installs once / refuses recreation, missing dataset refused instead of created,
  newer format + identity mismatch + `restored_backup` refused on open, admission is
  a live probe (refused without a write path, admitted after recovery), a failed
  durable write turns admission off until a fresh probe, restored backup pauses with
  the operator-visible reason.
- `apps/beamlet_runtime/test/beamlet/durable_admission_test.exs` (1): a durable
  submit is refused with `{:error, :unavailable}` and dispatches nothing while
  admission is off; recovery re-admits and the same submit runs.
- `apps/beamlet_daemon/test/beamlet/durable_host_test.exs` (7): role matrix
  (interaction-only no database, library load starts nothing and `ensure_all_started`
  starts no Repo/Admission, authority-only opens authority only, executor-only opens
  journal only and no Agent authority, both open both and expose the wiring),
  storage validation rejects bad adapter/uuid/paths/unknown keys, a missing dataset
  is refused at boot and not recreated, Node readiness stays distinct.
- `apps/beamlet_daemon/test/beamlet/durable_e2e_test.exs` (1 ordinary + 2 phase
  tests): the end-to-end scenario above.

No PostgreSQL run of the host wiring is claimed here: the dual-adapter contract
suite (stage A) runs the storage contract on both adapters, and stage F validates
the PostgreSQL configuration path only structurally. `mix test` stays green without
PostgreSQL by adding the existing `:postgres_db` exclusion to the daemon test
helper alongside `:distributed`; the two-phase e2e tags are excluded unless
`DURABLE_E2E_DIR` is set.

## Release evidence

Release behaviour is recorded in
`.trellis/tasks/10-18-durable-release-operations/research/release-smoke-parent.md`
(parent-run, this host): the packaged daemon release started with `storage:`
configured and the independent probe returned
`#{datasets => #{authority => ready, journal => ready}, boot_id => <<"e788...">>, admission => admitted}`
with a live `Beamlet.Storage.Admission` pid; the CLI release started and exited 0
with no database configured. Both releases build with `BEAMLET_BACKEND_BUILD=1`;
`beamlet_storage`, `ecto`, `ecto_sql`, `exqlite`, `ecto_sqlite3`, `postgrex`,
`db_connection` are inside the daemon release closure. No release build or entry
point behaviour was changed: the daemon release keeps `config/daemon_runtime.exs`,
the CLI release keeps its `Runner.main()` entrypoint step.

## Gaps and limits (not verified, not claimed)

- No physical power-loss, fsync-torn-write or kernel-crash test. The probe and the
  SQLite `synchronous=FULL`/WAL settings are real, but a test cannot prove hardware
  durability.
- No real multi-host deployment, no network-filesystem or shared-volume trial, and
  no cross-host admission coordination: one host owns its datasets, and the
  one authority adapter is selected per VM and there is no cross-host fencing.
- PostgreSQL host wiring (Host/Daemon with `adapter: :postgres`) was validated only
  by configuration tests, not by a live PostgreSQL deployment in this stage.
- Admission gates the authority dataset only. Executor journal failures surface as
  `:durable_unavailable` from journal writes; there is no separate journal admission
  flag, so an executor-only VM has no admission process to report.
- A VM without a started admission process reports `:not_configured` and admits:
  embedded/library callers own their policy. Hosts that configure storage always
  start it.
- `:restored_backup` refuses the dataset at open, so history read-only access needs
  the operator to resolve the marker first; a paused host is up but has no Repo.
- A `reply_recorded` checkpoint is not forkable by design; the scenario forks the
  last `await_input` boundary and asserts the refusal explicitly.
- The two-phase e2e is a process restart on one host, not a machine reboot. Init/VM
  boot ordering, service supervision and volume mount failures are untested.
- `mix credo --strict` is not clean: `apps/beamlet_agent/lib/beamlet/agent/durable.ex`,
  `apps/beamlet_storage/lib/beamlet/storage/operation_records.ex` and
  `executor_journal.ex` were already reported (stage B/C complexity/design notes);
  this stage's files add only `Software Design`/`Readability` suggestions, no
  correctness finding.
- `bin/beamlet_daemon rpc` is unusable in this environment (exits 0, prints
  nothing); probes must use a separate `erl -name ... -setcookie ... -eval
  'rpc:call(...)'` node, as recorded in `release-smoke-parent.md`.
- SQLite engine used: 3.53.4 (`Storage SQLite engine` printed by the suite);
  Exqlite 0.42.0, `journal_mode=wal`, `synchronous=FULL`, `foreign_keys=ON`,
  `PRAGMA busy_timeout` reads 0 by design (custom busy handler), query timeout
  5000 ms.

## Parent acceptance (2026-10-18)

Independent review returned BLOCK on two P1s; the parent fixed them.

P1 — a refused or lost **executor journal** did not pause admission: `Host` discarded the
journal refusal and only fed the authority refusal to `Admission`, and the probe inspected
only the authority repo. `Admission` now refuses while any configured dataset was refused
(a lost journal blocks new durable work, because its evidence could not be recorded), and a
dataset refused at boot stays refused until the host is restarted — never silently repaired.
Test: initialize both datasets, delete the journal file, boot both roles, assert
`admission: {:refused, :dataset_missing}` with the authority dataset still `:ready`.

P1 — the documented per-role key requirements contradicted `Host.datasets/2`: the SQLite
peer/alias guard always needs both paths, so an authority-only block without `journal:` is
refused. The evidence table and paragraph now say so, and the role-scoped claim is limited to
which datasets are actually opened.

P2 fixes: `Admission.failure/2` is now a synchronous call and `consult/0` honours a recorded
failure before probing, so a caller that just lost a write cannot race the next gate check
into an admitted answer (the operator view `status/1` still probes and clears it, which is
now covered by a test that previously passed even without the cast); the probe description
no longer claims fsync (the probe rolls back, so no commit happens); PostgreSQL connection
validation no longer short-circuits on `:password` (host/port/user are still required); and a
`Host.status/1` timeout now reports `:storage_unavailable` instead of `:storage_not_configured`.

Also fixed while verifying: `ContractFixture` named its temporary directory from a per-VM
counter only, so a leftover directory from an interrupted run produced a spurious
`:dataset_exists`. The name now includes wall-clock time.

Parent-run gates:

| Command | Result |
| --- | --- |
| `mix format --check-formatted` / `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_storage/test` | **59 passed, 13 excluded** |
| `mix test apps/beamlet_daemon/test` | **13 passed, 4 excluded** |
| `mix test apps/beamlet_runtime/test` | **53 passed, 6 excluded** |
| `mix test` (umbrella) | **351 passed, 0 failures** |
| daemon release with storage configured (parent smoke, `release-smoke-parent.md`) | `authority => ready, journal => ready, admission => admitted`; admission process alive |
| CLI release without a database (parent smoke) | exit 0 on empty stdin |

Still unproven, stated as such: physical power loss / torn writes (the probe commits nothing),
cross-host deployment, PostgreSQL inside the release, a long soak, the `Mix.Tasks.Beamlet.Storage.Migrate`
task under an automated test (it was run manually), and the "Node ready while admission
refused" pair as an automated test.
