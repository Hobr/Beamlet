# Storage foundation (dataset format 3)

`beamlet_storage` is a callback-free, opt-in library for explicit Ecto resource
ownership, transactions, canonical JSON, shared content and dataset installation.
Loading or starting it starts no Repo and installs no domain tables.

`Dataset.initialize(repo, opts)` installs only a fresh dataset.
`Dataset.open(repo, opts)` and `Dataset.verify(repo, opts)` never migrate, repair or
create missing files. Options require a trusted `descriptor`, canonical UUID
`dataset_id`, and `database`; SQLite also requires an absolute distinct
`peer_database`. Define a Repo with `use Beamlet.Storage.Repo, adapter: :sqlite`
(or `:postgres`), or use the neutral `SQLiteRepo` / `PostgresRepo` instances.
Successful initialize/open returns `{:ok, linked_pid}`; the caller owns stopping it.

Descriptors contain `profile`, `format_version: 3`, ordered `components` and
ordered `migrations`. Start compositions with `Installation.foundation_component/0`
and `foundation_migration/0` (ID1). Foundation installs only shared `artifacts`,
installation metadata and Ecto migration bookkeeping. Each descriptor must list
all components and migrations explicitly. Exact persisted identities, versions,
module names, order and completion status are checked. Old authority2/journal1,
extra/missing/newer components, wrong migration lists and incomplete installs are
refused. There is no importer or compatibility facade. Existing datasets are
never overwritten. Keep published migration modules immutable.

SQLite retains WAL/FULL/FK, immediate writes, deferred reads and interruptible
busy handling. PostgreSQL uses explicit connection options and a provisioned empty
database; connection checks require fsync and synchronous_commit. Driver write
failures conservatively return `:storage_outcome_unknown`; callers reconcile stable
identities without automatically retrying effects. Stopped Repos return unavailable,
never absence. Backups must be consistent; `restored_backup` blocks admission.

`Transaction.write/2` owns the commit/rollback. `Transaction.participate/2` requires
an existing transaction and makes no nested commit; callers roll back returned
participant errors. `Artifacts.put/2` and reference verification run inside that
transaction. Shared artifact content is bounded to 16MiB. `Codec.encode/decode/digest`
accept neutral positive byte bounds (default 4MiB), preserving sorted UTF-8 JSON
and SHA-256 bytes, strict duplicate-key and malformed-input rejection, depth32
and node100000 budgets. Domain codecs supply their own bounds. `JSON` takes an
explicit `max_bytes:` parameter.

`Host.start_link(datasets: [%{key: atom, repo: module, options: opts}])` opens only
provided descriptors, owns only successfully opened Repos and stops them on
shutdown. `handles/1` returns ready handles; `status/1` freshly probes resources.
Failed opens retain safe reasons and never automatically reopen. `Admission` is a
generic explicit gate: `repo:` plus dataset options, optional `{repo, opts}`
`resources:` for jointly required resources, and an initial refusal `reason:`.
`status/1` probes real writes with rollback; `consult/1` honors recorded failures.
Embedders explicitly start their gate; an absent gate means no host admission policy.

Actions owns Operation/attempt/evidence/results, dispatch scopes and journal in
`beamlet_actions_storage`. Agent owns orchestration, sources, events, checkpoints,
commands and inheritance in `beamlet_agent_storage`. Their profiles are explicit;
Actions-only callers need no Agent or Node dependency. Product composition and
`mix beamlet.storage.migrate` live in `Beamlet.Node.Storage` and its `Operator`.
See the [deployment guide](../../scripts/deployment/README.md). Dataset format3
and Agent trace export format2 are separate protocols.
