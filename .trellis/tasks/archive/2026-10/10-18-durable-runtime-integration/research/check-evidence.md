# B implementation check evidence

Scope: Runtime source/tests, one necessary Storage Transaction correction,
Runtime README, targeted integration paragraphs in operation-runtime spec and
this child's research documents. Existing uncommitted A/design/spec changes are
not attributed to B. Implementer used trellis-check locally; no independent
checker/subagent was spawned. No commit/push/merge/status/archive action.

## Final executed gates

All commands ran from umbrella root on `refactor/durable-rebuild`.

| Gate | Actual outcome | Log |
| --- | --- | --- |
| `BEAMLET_PG_SOCKET_DIR=/tmp/beamlet-storage-a-pg/socket BEAMLET_PG_PORT=55481 mix test apps/beamlet_storage/test apps/beamlet_runtime/test apps/beamlet_actions/test --seed 631927` | Actions **28 passed**, Storage **72 passed**, Runtime **64 passed / 7 distributed excluded** | `/tmp/beamlet-b-all-final.log` |
| `elixir --sname beamlet_durable_b --cookie beamlet_durable_b_cookie --erl '+S 2:2' -S mix test apps/beamlet_runtime/test --only distributed --seed 631927` | **7 passed**, 64 ordinary excluded; actual peer VMs executed | `/tmp/beamlet-b-distributed-final.log` |
| `mix credo --strict --all` | **pass**, 199 files, 2477 modules/functions, no findings | `/tmp/beamlet-b-credo-final.log` |
| `mix format --check-formatted` | **pass** | `/tmp/beamlet-b-format.log` |
| `git diff --check` | **pass** | terminal output |
| `mix compile --warnings-as-errors` | **fails**, exactly the three existing removed Agent calls below | `/tmp/beamlet-b-compile-final.log` |

Total focused test execution: **171 passed** across ordinary tests and named peers.
Storage executed the complete 72-test suite with real SQLite and real PostgreSQL,
including both adapter branches; no adapter was skipped. Used the existing isolated
PostgreSQL18.6 cluster at /tmp/beamlet-storage-a-pg, socket directory of that cluster,
port55481 and no TCP listener. Fixtures create/drop only their own temporary DBs.
The cluster was stopped after final verification; no existing dataset was migrated,
cleared or deleted. Initial start without socket/port options failed before opening
service; explicit isolated options succeeded. Cluster files remain available.

Root compile blockers (assigned to C/D, no shim introduced):

- `apps/beamlet_agent/lib/beamlet/agent/durable.ex:289`: `OperationRecords.prepare_batch/2`.
- `apps/beamlet_agent/lib/beamlet/agent/durable.ex:336`: `AgentRecords.consume_result/2`.
- `apps/beamlet_agent/lib/beamlet/agent/durable.ex:634`: `AgentRecords.fork/2`.

Focused test compilation succeeded with those visible warnings. No warning or
lint suppression, cap/timeout enlargement, assertion deletion or old-format
compatibility layer was used. Runtime's original durable behavioral scenarios were
retained and updated to A's strict API; new scenarios extend them. LSP sometimes
timed out and is not claimed as complete clean coverage. Compiler/test/static
commands are the evidence above.

## Acceptance mapping

**AC1:** new real SQLite Runtime tests prepare a model and tool together through
AgentRecords; reverse-order and simultaneous completions both accept independently.
Agent version and its four committed events remain unchanged by acceptance. Each
Operation has its own two-event stream. A's real two-adapter concurrency/CAS tests
also reran in the 72 Storage tests.

**AC2:** racing submissions of one prepared identity call the Handler once and a
losing claim cannot accept an error against the winner. Subsequent claimed or
accepted submission is refused. Existing restart test kills Gateway while work
runs, observes unknown_after_restart, no Worker reconstruction and no restored
charge, and rejects later terminal rewriting of unknown. Duplicate receipt replay,
conflicting receipt refusal and late evidence remain covered. Gateway journal
unavailability is fail-closed, distinct from not-found. Seven named tests include
remote capacity/partition/delayed admission regressions and the new durable peer.
Evidence reads and duplicate prepared submission do not create work.

**AC3:** sink test reads journal terminal and authority accepted output from inside
the sink callback. Authority-stop fault after Worker admission proves no normal
sink completion and a hidden status Result when acceptance fails. Another test
stops the journal after completion and reads authoritative accepted content with
journal unavailable. Late-return test freezes Gateway, accepts a Coordinator
deadline, then releases Worker; receipt evidence appears without replacing the
accepted deadline or delivering another completion.

**AC4:** named durable peer starts its own real SQLite journal and runs the exact
committed operation; credentials reach the remote Handler unchanged and are absent
from authority/journal rows. Existing local credential validation/forwarding and
complete ordinary envelope cases remain. Added exact-limit / one-byte-over tests
for durable admission (credentials + full identity tuple) and durable completion
(Result + full receipt tuple). Deadline/first-trigger/normal-success-race/unrelated
crash, observed termination, missing journal/failed terminal write, live admission
refusal/recovery, owner lifecycle and capacity/helper cleanup tests all remain in
the local/named passing suites. Stale Agent generation cannot claim or run work,
and produces no accepted synthetic Result.

## Intermediate corrections and limits

Earlier executions failed on removed legacy attrs, a compile-time old Agent struct
field dependency, test fixture dataset identity, and a remote Repo tied to its RPC
setup caller; these were corrected, not counted as passes. The stopped authority
regression exposed a previously uncaught Ecto lookup RuntimeError and drove the
narrow Transaction correction. An intermediate strict Credo run found nesting,
complexity and alias findings; helper extraction/aliasing fixed them. The initial
named failure is retained in `/tmp/beamlet-b-distributed.log`; corrected final
results use the separate final log. Some iterative local logs were overwritten;
no claim is made that they preserve complete original failure traces.

No full umbrella suite, Dialyzer, Sobelow, release/e2e, physical-host or power-loss
acceptance ran for B. C must integrate model preparation, explicit consumption,
reducer/activation and retiring previously claimed senders. D owns reference
fork/export/host integration. Those are explicit remaining boundaries; B's tests
do not establish a release-ready product or a cross-VM total stop order.
