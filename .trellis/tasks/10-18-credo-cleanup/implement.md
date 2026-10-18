# Execution Plan: Credo cleanup

## Preconditions

- [x] `9c6354d` merge + `dfa90cb` docs are in `dev`; working tree clean.
- [x] Baseline recorded: umbrella 439/49, storage 59/13, distributed 33, durable e2e
      green, `mix credo` 12, `mix credo --strict` 14.
- [x] Findings snapshot in `research/credo-findings.md` (106 items).

## Ordered work

- [ ] `apps/beamlet_storage` production: fix 6 files (operation_records, history,
      executor_journal, agent_records, admission, host, terminal_artifacts) -
      nesting/complexity/with/cond/alias. Add `Beamlet.Storage.*` aliases.
- [ ] `apps/beamlet_runtime` production: executor_gateway, operation_coordinator,
      persistence, runtime.ex - arity/with/nesting/alias.
- [ ] `apps/beamlet_agent` production: durable.ex, trace_export.ex, history.ex,
      server.ex, agent.ex - the largest share of nesting/complexity/alias.
- [ ] `apps/beamlet_storage` tests: split the long `quote` in
      `storage_contract_test.exs` into composed fragments; add `@moduledoc` to
      `contract_fixture.ex`; alias/nesting fixes. Assert generated test names and
      counts are unchanged.
- [ ] `apps/beamlet_agent` + `apps/beamlet_daemon` tests: aliases and structure only.
- [ ] Re-run `mix credo --strict --all`; drive remaining issues to zero without
      suppression.
- [ ] Update `.trellis/spec/backend/quality-guidelines.md` with the rule that the
      merged durable code is Credo-clean and that suppression/exclusion is not the
      remedy.

## Validation

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test --seed 631927
mix test apps/beamlet_storage/test --seed 631927
mix credo
mix credo --strict --all
mix sobelow
mix gettext.extract --check-up-to-date
mix dialyzer
bash scripts/deployment/durable-e2e.sh
git diff --check
git diff -- mix.lock scripts apps/*/mix.exs
```

Named distributed suite (isolated cookie, low schedulers):

```bash
elixir --sname <unique> --cookie <random> -S mix test \
  apps/beamlet_runtime/test/beamlet/distributed_test.exs \
  apps/beamlet_node/test/beamlet/{distributed,cluster_distributed,discovery_distributed,delegation_binding,observation_distributed}_test.exs \
  apps/beamlet_daemon/test/beamlet/bootstrap_distributed_test.exs \
  apps/beamlet_web/test/beamlet_web/{bootstrap,host,management,workbench}_distributed_test.exs \
  --only distributed --seed 631927
```

## Review gates

- Credo clean without config suppression, measured by command exit code.
- Per-suite test counts not lower than baseline; no assertion text removed.
- No public API/schema/migration diff; `mix.lock`/scripts/release config untouched.

## Rollback

`git revert` the refactor commit(s); no data or protocol migration involved.
