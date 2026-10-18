# Foundation milestone handoff

Foundation only is implemented on `refactor/storage-action-decoupling`, baseline `a8acffd`. No commits, branch/status changes, domain extraction, Node/Runtime/Server edits or real database changes. This is not full task acceptance or a releasable integration. The authoritative handoff is this file (the dispatch output instruction overrides the earlier research/foundation-handoff.md destination).

## Changed paths

Under `apps/beamlet_storage/`:

- `lib/beamlet/storage/installation.ex` (new): exact trusted descriptor validation and manifest.
- `lib/beamlet/storage/repo.ex` (new): neutral explicitly instantiated Repo declaration macro.
- `lib/beamlet/storage/dataset.ex`: descriptor-required format3 initialize/open/verify, read-only SQLite preflight, generic adapter detection, no domain migration selection.
- `lib/beamlet/storage/migrations.ex`: format3 installation metadata/completion marker and generic artifact migration.
- `lib/beamlet/storage/repos.ex`: adds neutral SQLiteRepo/PostgresRepo; existing old Repo declarations remain for later removal/migration.
- `lib/beamlet/storage/connections.ex`: reusable PostgreSQL configuration, existing SQLite connection safeguards retained.
- `lib/beamlet/storage/host.ex`: generic resource lifecycle and status, removes role/runtime composition.
- `lib/beamlet/storage/admission.ex`: descriptor/options-based verification/probe.
- `lib/beamlet/storage/transaction.ex`: guarded transaction participant; existing transaction/error classification unchanged.
- `test/beamlet/storage/foundation_test.exs` (new): 10 real SQLite foundation contracts.
- `test/beamlet/storage/foundation_postgres_test.exs` (new): 2 isolated PG foundation contracts.
- `test/beamlet/storage/no_load_side_effects_test.exs`: also asserts neutral Repos are absent in a fresh VM.

## Exact new APIs

```elixir
alias Beamlet.Storage.{Dataset, Installation}

# Composition is trusted code owned by the embedding/domain library.
descriptor = %{
  profile: "my-profile",
  format_version: 3,
  components: [Installation.foundation_component()],
  migrations: [Installation.foundation_migration()]
}

Installation.validate(descriptor) # :ok | {:error, :invalid_data}
Installation.manifest(descriptor) # stable JSON string; caller supplies valid descriptor
Installation.foundation_component() # %{name: "foundation", version: 1}
Installation.foundation_migration()
# %{id: 1, component: "foundation", module: Beamlet.Storage.Migrations.FoundationV1}

# A distinct trusted module is the registered instance, no runtime atomization.
defmodule MyDataRepo do
  use Beamlet.Storage.Repo, adapter: :sqlite # or :postgres
end
# Supplied neutral instances: Beamlet.Storage.SQLiteRepo / PostgresRepo.

opts = [descriptor: descriptor, dataset_id: canonical_uuid,
        database: absolute_file, peer_database: isolated_absolute_peer_file]
Dataset.initialize(MyDataRepo, opts) # {:ok, linked_pid} | {:error, safe_reason}
Dataset.open(MyDataRepo, opts)       # same; NEVER initializes/migrates
Dataset.verify(MyDataRepo, opts)     # :ok | {:error, safe_reason}; running Repo only
MyDataRepo.stop()
```

For PostgreSQL, `database` is the existing provisioned database name, `peer_database` is unnecessary; supply normal `socket_dir`/`hostname`, `port`, `username`, `password` options explicitly. Dataset rejects `:url` and `:name`, supports trusted Repo modules with SQLite3/Postgres adapters, and detects an already-running instance before reserving files. Prefer the Repo macro to retain enforced connection settings. No additional multi-authority promise is made.

Descriptor exact map keys are `profile`, `format_version`, `components`, `migrations`; extra/missing keys reject. Components have exactly `%{name: string, version: positive_integer}`. Migrations have exactly `%{id: positive_integer, component: string, module: compiled_migration_module}`. Profile/component strings match `[a-z][a-z0-9_.-]*`, 1..128 bytes. Component names and migration modules are unique. IDs are profile-global, unique, strictly increasing; input order is retained. Every declared component must own at least one migration and every migration must name a declared component. Foundation version1/component and migration1/module above must be first and exact. Remaining migration IDs and the actual Actions authority/Agent authority/journal profiles belong to the next composition owners; foundation defines no domain profile names, defaults, probes or module discovery. Allocate distinct ascending IDs when composing, never renumber/reuse or rename installed migrations. Domain initial component versions are 1 per the approved design.

The persisted manifest JSON has ordered component entries and ordered migration entries. Migration module identity is `Atom.to_string(module)` (for example `Elixir.Beamlet.Storage.Migrations.FoundationV1`); it is never evaluated or converted back to an atom from disk. Module/ID/component/version/ordering changes cause refusal. This is identity validation, not a source-code checksum; installed migration bodies must remain immutable. A golden manifest assertion freezes the foundation bytes.

`storage_metadata` singleton fields, in order: `id`, `dataset_id`, `profile`, `format_version`, `restored_backup`, `manifest`, `installed`. New metadata starts with `installed=FALSE`; only successful completion of all explicit Ecto migrations marks it TRUE. A failed/partial install is never admitted or resumed by open. `schema_migrations` must equal the entire descriptor ID list. Foundation migration1 creates only `artifacts` and its digest unique index, with no domain FK. `Migrations.install_metadata(repo,id,descriptor)` and `Migrations.install(repo,descriptor)` are internal installation primitives invoked by Dataset.initialize, not business entry points.

SQLite uses readonly raw preflight before starting a writable Repo. Old authority2/journal1 metadata rejects on format before requesting new metadata columns. Missing file is never created by open. Identity/profile mismatch => `:dataset_mismatch`; components/manifest/migration/incomplete/unsupported format => `:schema_unsupported`; backup marker => `:restored_backup`; malformed trusted config => `:invalid_data`. Missing metadata is `:dataset_missing`; read connection failures are `:storage_unavailable`, not absence. Initialization refuses an existing SQLite file or a PostgreSQL schema containing any base tables; it never overwrites, repairs or migrates an old install. Some installation exceptions are safely returned as `:storage_unavailable`; callers must not automatically retry a failed installation.

```elixir
# Generic resource lifecycle; NO runtime/Agent configuration returned.
Beamlet.Storage.Host.start_link(name: MyHost,
  datasets: [%{key: :main, repo: MyDataRepo, options: opts}])
Beamlet.Storage.Host.handles(MyHost) # {:ok, %{main: MyDataRepo}} for opened resources
Beamlet.Storage.Host.status(MyHost) # %{main: :admitted | {:error, safe_reason}}
# A failed open remains refused, without automatic reopen. Stop/restart explicitly.
# Host owns successfully opened Repos, stops them on orderly shutdown, observes exits.

Beamlet.Storage.Admission.probe(MyDataRepo, opts) # :admitted | {:error, reason}
Beamlet.Storage.Admission.start_link([name: MyAdmission, repo: MyDataRepo] ++ opts)
Beamlet.Storage.Admission.status(MyAdmission) # :admitted | {:refused, reason} | :not_configured
Beamlet.Storage.Admission.consult(MyAdmission) # :ok | {:error, :durable_not_admitted}
Beamlet.Storage.Admission.failure(:storage_outcome_unknown, MyAdmission)
# status freshly verifies + executes a rolled-back real write; recorded failure
# keeps consult refused until a successful fresh status probe. Optional :reason
# retains an initial refusal. Host uses direct probes, does not start a global gate.
```

Higher-layer composition must explicitly start/connect the Admission gate(s) required by its callers, and translate Host handles into its own domain wiring. Host accepts unique atom keys/unique Repo modules; missing/bad datasets never trigger initialization. `Host.configuration/2`, `Host.datasets/2`, `Host.runtime/1` no longer exist.

`Transaction.write(repo, fun_or_multi)` retains `{ :ok, value }`, `{:error, reason}` and Ecto.Multi result shapes; SQLite writes remain immediate, ordinary reads deferred. Existing constraint classification and conservative `:storage_outcome_unknown` on driver/connection failures remain; no retries. `Transaction.read(fun)` remains the safe read boundary. New `Transaction.participate(repo, zero_arity_fun)` runs only inside `repo.in_transaction?()`, otherwise `{:error, :transaction_required}`. It makes no nested transaction and passes the result through. Domain participants must validate inputs and avoid commit/external effects. The outer facade must rollback on errors or use Ecto.Multi; a returned error tuple alone does not roll back. `repo.rollback(reason)` aborts the whole joined transaction. Existing `Artifacts.put/2`, `fetch/2`, `verify_references/2` and digest bytes are unchanged; writes/reference validation require a caller-owned transaction.

## Actual validation

Prerequisites inspected: Nix present, direct toolchain Elixir1.20.4/OTP29 matches flake requirements; dependencies available. PostgreSQL18.6 binaries present in Nix store. Created a private `mktemp` cluster under `/tmp/beamlet-foundation-pg.*`, Unix socket only (`-h ''`), port55487, trust confined to that test cluster. Each PG test created/dropped only its own unique database. Cluster stopped cleanly; initialization/server logs retained. No existing database used.

- Combined focused command, seed631927, with `BEAMLET_PG_SOCKET_DIR`, `BEAMLET_PG_PORT=55487`, `BEAMLET_PG_USER=kanade`: `mix test apps/beamlet_storage/test/beamlet/storage/{foundation_test,foundation_postgres_test,codec_test,no_load_side_effects_test}.exs --seed 631927` => **17 passed, zero excluded** (10 SQLite foundation, 2 PG foundation, 4 codec, 1 fresh-VM no-load). Log `/tmp/beamlet-foundation-combined-final.log`.
- After additional test-only golden manifest/module-swap/stopped-Repo assertions: SQLite+codec+no-load command => **15 passed**, `/tmp/beamlet-foundation-sqlite-final.log`. PG source/test unchanged since the successful combined run. This final command selected no PG tests; it is not counted as a PG pass.
- Real SQLite tests: descriptor pre-write refusal; exact neutral table ownership; WAL/FULL/FK/interruptible busy handler settings; old2/old1 byte-preserving rejection with business table content in the unchanged bytes; identity/profile/components/manifest/module identity/migration IDs/backup/incomplete refusals; explicit composition with a test-owned migration; failed installation remains incomplete; raw Repo start does not migrate; alias/hardlink/symlink refusal; content rollback/reopen; immediate versus deferred transaction locks; actual busy contention => unknown outcome and later successful explicit write; generic Host missing/reopen/lifecycle and fresh Admission failure/probe semantics.
- PG tests: new install/open/verify, exact neutral tables, fsync/synchronous_commit=on, rollback participant/admission, identity/manifest/backup refusal, existing install refusal, and old authority2 schema/business preservation. These are focused foundation PG tests, not the old-domain full adapter contract.
- Strict Credo on touched foundation source => no issues, `/tmp/beamlet-foundation-credo-final.log`.
- Format check on all touched/new Elixir files => pass, `/tmp/beamlet-foundation-format-final.log`. `git diff --check` => pass; no staged files.
- `mix compile` => exits successfully with known legacy caller warnings. `mix compile --warnings-as-errors` => fails at retained `Operator` -> removed `Host.datasets/2`; regular compilation also reports `Beamlet.Server` -> removed `Host.configuration/2`. `/tmp/beamlet-foundation-compile-normal.log`, `/tmp/beamlet-foundation-compile-final.log`. Foundation sources do compile during the passing focused tests.
- Initial test failures were fixture teardown racing linked Repo exit, WAL baseline before explicit checkpoint, and a test setup that accidentally aliased its peer before reaching the expected active-instance conflict. Fixed fixture/tests; earlier logs retained separately. Initial strict Credo findings fixed by helpers/aliases, no suppression.
- Tool-side LSP feedback was mixed (some clean results, some unavailable/pending); complete active LSP coverage is inconclusive. No Dialyzer/full umbrella/release/distributed acceptance claimed for this milestone.

## Remaining ownership / residual risks

Integration is intentionally incomplete. Retained `Storage.Operator` still implements old role composition and must move to Node with the Mix task; its Host.datasets call is broken now. Server configuration and all old Host runtime/status/settings callers need the approved Node composition. No shim/default descriptor was added to make them compile cleanly. Old Dataset/host/domain tests and `test/support/contract_fixture.ex` still use descriptorless API and old fixed schema assumptions; they require owner migration and were not reported passing or weakened. The new foundation fixtures are self-contained and depend on no domain library.

All old business modules remain untouched for subsequent owners: `AgentRecords`, `OperationRecords`, `ExecutorJournal`, `Events`, `History`, `Inheritance`, `References`, `Records`, `TerminalArtifacts`, their domain schemas, old authority/journal migrations, legacy Operator/Mix task and old Repo names. Codec still has domain kind names/limits (`operation`, `command`, `event`, `checkpoint`, `result`, `journal_artifacts`), JSON still defaults to `:event`, and RecordChangeset/Artifacts/Schema.Artifact remain shared. Later owners must move domain policy and extract generic parameterized codec/helper behavior without changing canonical bytes. Full AC1 decoupling is not claimed while those modules remain.

Three actual domain profile compositions, domain migrations/tables, cross-domain atomicity/fences, Runtime/Agent migration, Node admission wiring, release closure/docs/spec updates and full validation remain. No concurrent whole-task check, old-domain PG contract, power-cut or physical multi-host evidence. Nothing was committed or staged. Parent can now hand source ownership to the next lane.
