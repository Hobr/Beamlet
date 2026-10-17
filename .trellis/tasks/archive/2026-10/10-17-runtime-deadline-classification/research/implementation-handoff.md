# Runtime deadline implementation handoff

Implementation is ready for independent review; this is not whole-child acceptance. DA5 historical composition root cause remains unknown, DA6 independent review/spec synchronization belongs to the parent. No commit, staging, branch, archive, task-pointer, dependency/configuration, shared-spec, Agent, Node or Web changes were made by this agent.

## Changed files and ownership

- `apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex`: each admitted entry stores `stop_source: nil`. A private stop helper records the first trigger processed by this Gateway (`:deadline` or `:cancelled`), requests shutdown once and retains existing kill escalation. Execution deadline now invokes that helper directly, removing the intervening ordinary cancel self-message. Observed shutdown or Gateway-requested kill uses that source with `worker_stopped`; unrelated DOWN remains `error/worker_lost`. `observed_stop?/2` extracts the existing causal predicate to satisfy strict Credo.
- `apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex`: remove the blanket stopping/worker_stopped rewrite. Existing identity validation and first-terminal acceptance now preserve the Gateway's valid deadline classification even when explicit cancellation is also pending.
- `apps/beamlet_runtime/test/beamlet/deadline_classification_test.exs`: nine focused cases and a test-local synchronized handler; no existing success assertion changed.

Gateway owns local first-trigger provenance and worker monitor/capacity retirement. Coordinator owns operation deadline, cancellation-unconfirmed timeout, identity validation and immutable outward terminal acceptance. Worker/Result/protocol fields and enums are unchanged. Admission, conservative lease-age reduction, scheduling, capacity, retention, provider/owner/infrastructure loss, escalation and single dispatch/no retry remain unchanged.

Starting inventory and full binary tracked diff: `/tmp/runtime-deadline-start/inventory.txt`, `/tmp/runtime-deadline-start/dirty.diff`. Final automated comparison found the existing tracked dirty diff byte-identical after excluding these two newly edited production files; every original inventory entry remains. Only the three paths above were added to the starting Git status. Staging is empty. Existing observation source and untracked files were preserved.

## Causal red/green evidence

The regression was written and run before production edits. It obtains a genuine Directory-selected report, waits until its issuing lease is at least700ms old, then actually submits a1400ms operation. Refresh10000ms and expiry3000ms keep the genuine report valid while preventing refresh from erasing the controlled age. No admission service is suspended. The handler reports its real remaining execution budget; assertion requires0 < remaining <800ms. Actual worker DOWN with reason `shutdown` is asserted before classification. The terminal must be `deadline/worker_stopped`, source `execution`, distinguishing this from Coordinator's later timer.

- `mix test apps/beamlet_runtime/test/beamlet/deadline_classification_test.exs --seed 631927`: original code exited2,0/1 passed. `/tmp/runtime-deadline-red.log` records `left: :error`, `right: :deadline`; the preceding actual DOWN/shutdown assertion passed. It also records a harmless unused-default test warning, subsequently eliminated by the matrix's use of default arguments.
- Same command after initial fix exited0,1 passed: `/tmp/runtime-deadline-green-initial.log`.
- Expanded same command exited0,9 passed: `/tmp/runtime-deadline-matrix.log`.
- Final focused command below exited0,25 passed, after the predicate-only Credo extraction.

The controlled original regression proves actual admission and shutdown, not a Coordinator timeout with no worker. No baseline re-analysis or lucky50ms repetition was needed. Earlier durable candidate/baseline research and original failure logs were read and retained unchanged in the task research directory.

## Race/cleanup evidence

| Scenario | Evidence |
| --- | --- |
| Genuine aged execution budget expires | actual shutdown DOWN, execution-origin deadline/worker_stopped |
| Deadline first, explicit cancel second | Gateway suspended only after actual admission; deadline enqueued before Coordinator cancel; Endpoint fence drains forwarding before Gateway resumes; first source remains deadline |
| Explicit cancel first, deadline second | same forwarding fence establishes local Gateway mailbox order; first source remains cancelled |
| Each first-source order, kill escalation | trapping worker, actual killed DOWN, status follows first source, worker_stopped |
| Each first-source order, unrelated crash | handler exits unrelated_crash after stop request; actual DOWN, error/worker_lost |
| Each first-source order, racing success | handler released after stop request; actual normal DOWN, successful result remains successful |
| Coordinator deadline without observed exit | Gateway suspended after admission; live worker asserted when Coordinator deadline/termination_unconfirmed accepted; resume then actual shutdown DOWN |
| Cancel without observed exit | same fixture, explicit cancel then cancel_timeout; uncertain/cancel_unconfirmed retained after actual later DOWN |
| Late/duplicate messages | every new case sends late execution_deadline/kill/cancel to terminal tombstone, duplicate admission and matching completion, Coordinator deadline/cancel_timeout; result unchanged, no second worker/result, exactly restored cpu capacity and zero tasks |
| Existing owner/infrastructure behavior | unchanged Runtime lifecycle tests and neighboring/full/named gates cover owner/coordinator/provider/gateway/scope loss, shutdown cancellation, successful immutable retention, progress and identity/admission behavior |

Terminal entries are atoms, not running-entry maps. Stop/deadline/kill handlers use map patterns and ignore terminal/missing entries. Tests use an explicit bounded Gateway-terminal fence where test DOWN and Gateway DOWN delivery can race; they do not dereference running fields after retirement. Worker exit proves only process retirement, not provider cancellation, rollback, absence of effects or billing cessation. Cross-VM global trigger ordering is not promised.

## Validation and preserved failures

All commands ran at repository root with the existing Elixir/Mix toolchain. Logs and corresponding `.exit` files use `/tmp/runtime-deadline-<name>.*` unless noted. No cookie is saved in logs or report. Named command cookies were generated in memory and passed as process arguments.

| Exact command | Exit / actual counts / evidence |
| --- | --- |
| `mix test apps/beamlet_runtime/test apps/beamlet_agent/test apps/beamlet_node/test apps/beamlet_cli/test --seed 631927` |0;155 passed,27 distributed excluded: Runtime43/6 excluded, Agent26, Node68/20 excluded, CLI18/1 excluded. `neighbors.log/.exit` |
| `mix test` |0; seed932522;230 passed,29 distributed excluded: Harness35, Actions28, Runtime43/6 excluded, Agent26, Node68/20 excluded, Daemon5/2 excluded, CLI18/1 excluded, Web7. `umbrella.log/.exit` |
| `elixir --sname deadline_classification_gate --cookie <private-test-cookie> -S mix test apps/beamlet_runtime/test apps/beamlet_node/test apps/beamlet_cli/test --only distributed --seed 631927` |INCOMPLETE: combined outer tool call timed out at60s after umbrella plus part of named gate; Runtime6 passed/43 excluded observed, Node partial, no whole-gate exit. `distributed.log` preserved. Not a passing gate and not a test assertion failure. |
| `elixir --sname deadline_classification_gate_final --cookie <private-test-cookie> -S mix test apps/beamlet_runtime/test apps/beamlet_node/test apps/beamlet_cli/test --only distributed --seed 631927` |0;27 actually passed,129 ordinary excluded: Runtime6/43 excluded, Node20/68 excluded, CLI1/18 excluded. `distributed-final.log/.exit`. Supervisor explicitly approved one same-command detached replacement after timeout; epmd empty before replacement and after completion.240s bound, polled under60s. Same-host peers only. |
| `mix format --check-formatted` |0 initially and after predicate extraction; `format.log/.exit`, `format-final.log/.exit` |
| `mix compile --warnings-as-errors` |0 initially and finally; `compile.log/.exit`, `compile-final.log/.exit` |
| `mix credo --strict` |initial exit8, Gateway DOWN handler complexity10/max9; `credo.log/.exit` preserved. Extracted unchanged causal predicate into private helper; final exit0,116 files/986 mods-functions/69 checks, no issues; `credo-final.log/.exit` |
| `mix dialyzer` |0 initially and finally; existing PLT up to date, no rebuild/refresh;0 errors,0 skipped,0 unnecessary skips. `dialyzer.log/.exit`, `dialyzer-final.log/.exit` |
| `mix test apps/beamlet_runtime/test/beamlet/deadline_classification_test.exs apps/beamlet_runtime/test/beamlet/runtime_test.exs --seed 631927` |0;25 passed, no selected exclusions; `focused-final.log/.exit` after predicate extraction. Broad gates ran before that behavior-preserving extraction and were not gratuitously repeated. |
| `git diff --check` |0 final; existing tracked diff preserved and staging empty verified |
| active LSP changed-source check |not run: no callable LSP interface exposed to this subagent. No cached/empty diagnostic claim; unavailable/inconclusive. |

Deliberate unrelated crash fixtures emit expected OTP Task error reports in test logs; these are asserted process outcomes, not unexpected suite failures. Ordinary umbrella excludes29 distributed tests; the requested named Runtime/Node/CLI gate executes27, while two Daemon distributed tests are outside that named gate and remain excluded. No paid provider or physical-host validation is claimed. No product logging was added.

## Bounded composition investigation and disposition

Read the preserved original100ms receive failure and prior independent-check evidence. Separately ran exactly one bounded traced composition execution:

`MIX_ENV=test mix run /tmp/runtime-composition-trace.exs`

Exit0,2 passed, seed631927: shared-only13.9ms, standalone execution13.6ms. `/tmp/runtime-composition-trace.log` and `/tmp/runtime-composition-trace.exit` preserve actual monotonic-timestamp send/receive lifecycle messages: admit, admitted, completed with successful execution Result, and successful sink beamlet_operation result. The standalone existing test file was required unchanged, preserving its ordinary100ms success assertion. The script is test-only and traces message shapes; no production instrumentation, timeout extension, relaxed success or retry was introduced. Neighboring/full ordinary suites also passed the unchanged composition tests.

This establishes current successful lifecycle behavior only. It does not reconstruct the original empty-mailbox event ordering, prove baseline status, establish scheduling-delay causality, or explain the historical100ms failure using the short-budget defect. Recommendation: parent retain DA5 as an explicit unresolved historical investigation/disposition item during independent review; do not declare root cause fixed or silently accept the whole child. If future reproduction provides another production cause, review scope before changing it. No additional cause was found in this bounded run.

## Residual risks and parent actions

- Historical composition root cause remains unknown; parent must explicitly disposition DA5. DA6 independent check/spec synchronization and return to observation are pending.
- Active LSP evidence unavailable in this tool surface. Existing-PLT Dialyzer and warning-fatal compile passed, but do not substitute for an active LSP claim.
- Broad suites and named gate precede only the behavior-preserving predicate extraction; final focused25 plus all static gates passed after it.
- Deterministic timing separation is generous and synchronized but remains subject to extreme VM scheduling delay; tests do not promise hard real-time behavior. Matrix uses actual admitted workers and mailbox fences, with no retries.
- Matching trusted peers should run matching Gateway versions; old Gateways cannot supply corrected provenance. No mixed-version guarantee or external-side-effect cancellation guarantee.

Parent owns independent trellis-check, shared-spec updates and acceptance decisions. This implementation did not close or mark the task accepted.
