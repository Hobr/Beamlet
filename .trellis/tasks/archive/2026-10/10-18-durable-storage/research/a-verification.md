# Stage A verification (parent-accepted)

Date: 2026-10-18. Branch `feat/durable-storage`. This file records what the parent session
actually ran after the integration child reported BLOCKED; it supersedes the gap list in
`integration-evidence.md` where the two disagree.

## What changed after the blocked handoff

The integration child concluded that "`Dataset.open/2` on a populated SQLite dataset does not
return inside ExUnit". The independent review found the real cause: a one-line test bug.

```elixir
defp stop_repo(fixture) do
  stop_repo(fixture)      # unbounded self-recursion, hidden by `catch`
catch
  _, _ -> :ok
end
```

That helper was the only code behind the withdrawn close/reopen scenario, so the "hang" was a
non-terminating test helper, not the product path. `dataset_test.exs` already performs
initialize → committed write → `repo.stop()` → `Dataset.open()` and passes. Fixes applied by the
parent:

1. `stop_repo/1` now stops the fixture repo once and tolerates a repeat stop.
2. Restored three scenarios into the shared `ContractSuite`, so they now run on **both**
   adapters: reopen a dataset holding committed facts and read them back; refuse a newer
   `format_version`; refuse an explicit `restored_backup` marker.
3. Removed the dead helpers/`CaptureIO` import and the unreachable `run_raw(:sqlite, ...)`
   clause; the SQLite driver-failure case now goes through `Records.transact/2` (the facade
   every caller uses) instead of only `Transaction.write/2`.
4. `history_page` counted characters (`length()`), not bytes. It now selects the canonical JSON
   text (`CAST(? AS TEXT)`, portable on both adapters) and measures `byte_size/1` in Elixir.
5. Credential-key rejection widened from an exact-name list to exact names plus credential
   segments (`client_secret`, `bearer_token`, `api-key`), while reference-shaped keys
   (`secret_ref`, `credential_id`, `api_key_name`) remain storable and `max_tokens` is not
   rejected. README wording now describes it as a heuristic, not a secret scanner.
6. Deterministic statement failures inside a write are no longer reported as
   `storage_outcome_unknown`: SQLite constraint/datatype messages and PostgreSQL
   integrity/data-exception codes map to `:conflict`/`:invalid_data`. Connection loss, `:exit`
   and unclassified driver errors stay outcome-unknown.
7. The PostgreSQL contract module is tagged `:postgres_db` and excluded by default with a
   printed notice; setting `BEAMLET_PG_SOCKET_DIR` opts in, and a missing cluster then fails
   loudly rather than skipping.
8. `write_consume/2` no longer ends a `with` with a bare assignment (Credo finding).

## Gate evidence (parent-run)

Isolated cluster: nix `postgresql-18.6`, Unix socket `/tmp/beamlet-pg-run/sock`, port 5439,
`listen_addresses=''`, `fsync=on`, `synchronous_commit=on`, `--auth=trust`; SQLite engine 3.53.4.

| Command | Result |
| --- | --- |
| `mix format --check-formatted` | exit 0 |
| `mix compile --warnings-as-errors` | exit 0 |
| `BEAMLET_BACKEND_BUILD=1 mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_storage/test` (no PostgreSQL) | **51 passed, 13 excluded**, exclusion printed |
| `BEAMLET_PG_SOCKET_DIR=… BEAMLET_PG_PORT=5439 mix test apps/beamlet_storage/test` | **64 passed** (dual adapter, 0 failures) |
| same, with `BEAMLET_BACKEND_BUILD=1` | **64 passed** |
| `mix test` (whole umbrella) | **281 passed, 0 failures** (42 excluded: pre-existing `:distributed` + 13 `:postgres_db`) |
| `mix credo` (the configured hook command) | exit 0; 14 refactoring + 1 readability advisory findings remain |
| `mix credo --strict` | exit 14 (advisory only; same findings) |
| `mix dialyzer` | **0 errors**, PLT up to date |
| `mix sobelow --root apps/beamlet_storage --private` | exit 0; one low-confidence "SQL injection" note on `dataset.ex:141`, where the statement is a constant chosen by an adapter branch, not interpolated input |

The dual-adapter run grew from 58 to 64 tests exactly because the three restored scenarios now
execute on both adapters (3 × 2). The 13 excluded tests are the PostgreSQL module (10 contract +
3 restored scenarios).

## Accepted state

Stage A implements storage foundations, not durable runtime behaviour:

- authority: 8 business tables + `storage_metadata`; journal: `journal_attempts` +
  `storage_metadata`; plus each Repo's Ecto `schema_migrations`.
- No Application callback, no auto Repo start, no auto migration, no host configuration, no
  Agent/Runtime/Node change, no handler execution and no send/admit path.
- `Busy` handling: Exqlite 0.42's interruptible NIF handler with a configured 2000 ms budget;
  `PRAGMA busy_timeout` reads 0 by design and must not be re-applied.

## Remaining limits (not stage-A blockers, still unproven)

- PostgreSQL was exercised against a throwaway local cluster on a Unix socket, not a managed
  production server, network failure modes, or crash recovery of the database host.
- No power-loss/fsync testing: the FULL/WAL settings are verified as configuration, not as
  physical durability.
- `mix credo` advisory findings (complexity in record facades, the long `__using__` block) are
  recorded, not resolved.
- Downstream stages B–F remain unimplemented; nothing here shows paused recovery, fork, export
  or runtime evidence.
