# Aggregate Runtime distributed gate repair

Scoped repair on `feat/distributed-agent-mvp`, 2026-10-16. This report supersedes
only the Runtime aggregate blocker in verification.md/check-report.md; it does
not accept child4 or change task state. Parent-owned review and physical/live
evidence remain pending.

## Finding and evidence limits

The original `/tmp/child4-distributed-final.log` and `/tmp/child4-distributed.log`
record aggregate failure at the second sequential submission: expected `:ok`,
received `:error`, seed719916. Their assertion did not capture Result.reason.
Two diagnostic-only aggregate reruns here passed (Runtime4 + Node3 each), so
**the exact terminal reason of those historical failures remains unknown**.

A deterministic test-only ordering probe reproduced the same failed success
assertion and captured safe terminal fields and capacity snapshots:

```text
second submission: %{reason: :no_target, status: :error,
  directory: [%{available: %{"cpu" => 0}, ready: true},
              %{available: %{}, ready: false}],
  gateway: %{available: %{"cpu" => 1}, ready: true}}
Result: 0/1 passed, 3 excluded; Failed: 1 test
```

Probe: run the first generic remote-owner operation with the existing held-worker
fixture; observe Directory's occupied report; suspend only the remote NodeEndpoint
(report forwarding); release the worker; receive successful first Result; submit
the second operation immediately while reports remain held. This isolates stale
capacity from owner guarding and proves a missing test synchronization prerequisite.
It does not retroactively prove the uncaptured historical reason. Probe log:
`/tmp/aggregate-runtime-ordering-before.log`.

Actual source ordering inspected (no product edits):

- ExecutorGateway handles worker result by sending `:completed` to coordinator,
  then returning state from `release/2`, which restores claims/removes task accounting.
- NodeEndpoint forwards report requests; Gateway answers with current available
  pools and a gateway-local monotonic lease. Directory separately caches validated,
  nonce-correlated reports; refresh is periodic (20ms in this fixture), expiry100ms.
- Completion does not invalidate or refresh Directory's cached report. Directory
  selects only eligible reports, including all pool claims. A busy cached report
  excludes the sole allowed executor even after actual Gateway capacity is free.
- OperationCoordinator maps selection `:none` to terminal `:error/:no_target`.
  Product behavior matches the accepted no-reservation/no-queue/no-retry contract.

## Repair

Only `apps/beamlet_runtime/test/beamlet/distributed_test.exs` was edited; no support
or product source changes were needed. The first generic remote-owner operation
now uses the existing held-worker fixture to force an occupied Directory report.
Endpoint reports are suspended across completion and actual Gateway release; an
assertion confirms the still-occupied cached report. `try/after` always resumes
Endpoint. This makes the formerly incidental ordering explicit in the existing
remote-execution regression without increasing the distributed test count.

Before the second submission, a bounded barrier observes Gateway readiness, full
CPU capacity and zero tasks, then waits for an eligible Directory report with a
lease strictly newer than a remote monotonic timestamp obtained after release.
Both lease and fence originate on the executor's clock; the separate wait deadline
uses the local clock. This prevents an old idle snapshot from satisfying the
barrier. Polling consists of synchronous state/select observations with a fixed
3s deadline, with no sleeps or submission retries. Each operation is submitted
once. Success, correct remote node, stale-result rejection, guarded remote-owner
rejection, default remote-owner compatibility, no-target and no-fallback assertions
remain. The second success assertion now prints only safe status/reason on failure.
Other distributed tests and their existing cleanup polling were left unchanged.

## Executed commands and logs

Commands ran from repository root with `ERL_FLAGS='+S 2:2'`. Named test VMs use an
isolated public fixture cookie (represented below as `<fixture-cookie>`), no
credentials. Peer VMs also use two schedulers and existing bounded teardown.

| Command (after the environment setting above) | Result / log |
| --- | --- |
| `elixir --sname aggregate_runtime_before --cookie <fixture-cookie> -S mix test --only distributed --seed 719916` | Diagnostic-only unbarriered aggregate: 7 passed (Runtime4, Node3); `/tmp/aggregate-runtime-before.log` |
| `elixir --sname child4_distributed_final --cookie <fixture-cookie> -S mix test --only distributed --seed 719916` | Second diagnostic-only unbarriered aggregate: 7 passed; `/tmp/aggregate-runtime-before-2.log` |
| `elixir --sname aggregate_runtime_ordering --cookie <fixture-cookie> -S mix test apps/beamlet_runtime/test/beamlet/distributed_test.exs:65 --include distributed --seed 719916` | Expected before-repair probe failure: 0/1 passed, 3 excluded, `:error/:no_target`; `/tmp/aggregate-runtime-ordering-before.log` |
| `mix format apps/beamlet_runtime/test/beamlet/distributed_test.exs` | Passed, scoped formatting |
| `elixir --sname child4_distributed_final --cookie <fixture-cookie> -S mix test --only distributed --seed 719916` | Final exact aggregate gate: **7 passed**, Runtime4 + Node3; `/tmp/aggregate-runtime-after-719916.log` |
| `elixir --sname aggregate_runtime_after_alt --cookie <fixture-cookie> -S mix test --only distributed --seed 631927` | Final additional-seed aggregate: **7 passed**, Runtime4 + Node3; `/tmp/aggregate-runtime-after-631927.log` |
| `elixir --sname aggregate_runtime_focused --cookie <fixture-cookie> -S mix test apps/beamlet_runtime/test --include distributed --seed 719916` | **32 passed**, including all4 Runtime distributed; `/tmp/aggregate-runtime-focused.log` |
| `mix format --check-formatted apps/beamlet_runtime/test/beamlet/distributed_test.exs` | Passed; `/tmp/aggregate-runtime-format.log` |
| `mix credo --strict --files-included apps/beamlet_runtime/test/beamlet/distributed_test.exs` | Passed; tool reported checking76 files/599 mods-funs, zero issues (broader than requested file filter); `/tmp/aggregate-runtime-credo.log` |
| `MIX_ENV=test mix compile --warnings-as-errors` | Passed; `/tmp/aggregate-runtime-compile.log` |
| `git diff --check` / `git diff --cached --name-only` | Passed whitespace; index empty |

Aggregate runs exclude 120 nondistributed cases: Harness26, Actions5, Runtime28,
Agent4, Node50, Web7. The excluded-only child applications print their usual
`--only` no-tests notice; actual Runtime4 and Node3 execute. Focused Runtime32
includes the expected gateway-loss log from its fault test; zero test failures.
Only one additional seed was used. No broad release, physical-host, paid/provider
or deployment gates were rerun. No Dialyzer/PLT refresh was needed for this
private test-only change; no complete LSP sweep is attested.

## Scope and residual risks

The Runtime test was already an untracked accepted child deliverable in this dirty
workspace. Baseline status is preserved at `/tmp/aggregate-runtime-before-status.log`;
this worker changed only that file and this new report. No Agents/Harness/Node/CLI/
release/root/spec/state/index writes, staging, commits, spawned agents, external
messages, credential access or deployment occurred. Temporary diagnostic assertions
were replaced by the safe status/reason message above. Existing child4 reports and
all upstream deliverables were preserved.

No remaining blocker found in the bounded test repair. Historical failure reason
is unknown; the deterministic reproduction establishes a compatible concrete cause,
not proof that no other intermittent failures exist. Same-host peer tests establish
local distributed behavior only. Physical B/C on distinct hosts, live-provider
checks and broader independent child4 acceptance remain parent-owned and pending.
