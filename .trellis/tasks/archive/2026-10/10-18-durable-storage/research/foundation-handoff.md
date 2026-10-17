# Foundation handoff (parent-verified)

原 foundation 写入者在收尾时被平台超时中断（provider stream aborted + 30min cap），未自行产出 handoff。父会话只读核验其工作树结果，结论如下；这是父会话验收证据，不是子代理自述。

## Gate evidence (parent-run, 2026-10-18)

| Check | Result |
| --- | --- |
| `mix compile --warnings-as-errors` | exit 0 |
| `BEAMLET_BACKEND_BUILD=1 mix compile --warnings-as-errors` | exit 0（Storage 已进入后端白名单） |
| `mix format --check-formatted` | exit 0 |
| `mix test apps/beamlet_storage/test` | 21 passed |
| `BEAMLET_BACKEND_BUILD=1 mix test apps/beamlet_storage/test` | 21 passed |
| SQLite engine reported by test run | 3.53.4 |

Resolved deps (root `mix.lock`, exact pins in `apps/beamlet_storage/mix.exs`): ecto 3.14.0, ecto_sql 3.14.0, ecto_sqlite3 0.25.0, exqlite 0.42.0, postgrex 0.22.4, jason 1.4.5. No overrides; no existing package version rewritten.

## Shape

- `apps/beamlet_storage` has no Application callback (`application/0` only adds `:crypto`); loading it starts no Repo, creates no file, runs no migration.
- Explicit lifecycle: `Beamlet.Storage.Dataset.initialize/2` refuses an existing file; `open/2` refuses missing/uninstalled dataset and never migrates. Paths must be absolute, local, symlink-free, and authority/journal must not alias.
- One singleton `storage_metadata` per database: `id=1`, `dataset_id`, `role` (`authority`|`journal`), `format_version`, `restored_backup`. Reopen fails closed on identity/role mismatch, missing metadata, newer format/migration version, and a true backup marker. Created in `Beamlet.Storage.Migrations`; `Dataset` reads it for open verification.
- Authority DDL: 8 business tables (`agents`, `checkpoints`, `events`, `operations`, `executions`, `execution_evidence`, `commands`, `artifacts`) + `storage_metadata`. Journal DDL: `journal_attempts` + `storage_metadata`. Each Repo also has Ecto's `schema_migrations`.
- `Beamlet.Storage.Codec`: strict sorted-key JSON, depth 32, 100k nodes, per-kind byte limits, structured credential-key rejection, canonical SHA-256. `Beamlet.Storage.JSON` is the Ecto type adapter. `Artifacts` provides in-transaction `put/2` + `verify_references/2` (`{:error, :limit}` vs `:invalid_data` distinguished).
- `Connections` verifies each connection: `journal_mode=wal`, `synchronous=2` (FULL), `foreign_keys=1`. `busy_timeout` PRAGMA reads 0 by design because Exqlite 0.42 installs an interruptible NIF busy handler (`:busy_timeout` option, 2000ms) instead of SQLite's PRAGMA handler; do **not** re-apply `PRAGMA busy_timeout` — it would destroy that handler. Bounded contention, release, and cancellation are covered by real two-connection tests.
- `journal_attempts` already has `terminal_artifacts` (nullable JSON, `kind: :journal_artifacts`, encoded limit 24 MiB) with a version/keys whitelist check in the schema changeset.

## Known gaps left for the next component

- No `AgentRecords` / `OperationRecords` / `ExecutorJournal` transaction facades yet.
- Authority/journal business transactions, CAS, command/receipt idempotence and consumption dedupe are unimplemented.
- PostgreSQL has not been executed at all (no cluster prepared); dual-adapter proof is still outstanding.
- `terminal_artifacts` content codec (digest/size/base64 verification, dangling refs, conflict on duplicate terminal) belongs to the records component.
- Two files (`artifacts.ex`, `connections.ex`, `dataset.ex`) had a last edit applied immediately before the timeout; they compile and pass tests now, but the records writer must treat them as reviewable rather than frozen.
