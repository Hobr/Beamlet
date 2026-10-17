# Independent Runtime deadline repair review

**Repair review: PASS, no remaining production blocker found.** The observed P1 baseline misclassification is corrected by the reviewed increment. This is not whole-task acceptance: parent must explicitly disposition DA5, synchronize specs under DA6, and return to observation for its acceptance review. No source/test repair was necessary during this review.

Reviewed the complete changes to `apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex`, `operation_coordinator.ex`, and the untracked `apps/beamlet_runtime/test/beamlet/deadline_classification_test.exs`. Loaded all check.jsonl references, PRD/design/implementation plan, `.agents/skills/trellis-check/SKILL.md`, implementation handoff, preserved causal scripts/logs, starting inventory/diff and relevant neighboring code/tests. Task-path dispatch takes precedence over the inherited no-task breadcrumb; no task-pointer change was made.

## Prioritized findings and actions

1. **No remaining P1 production finding in the repair.** Gateway lines74–81/175–195 record the first local trigger and only classify actual matching shutdown or requested-kill DOWN as stopped (lines127–143). Coordinator lines87–100 preserves that valid classification. The baseline P1 can be closed on this evidence, rather than on aggregate green suites alone.
2. **P2, historical risk and explicit parent disposition: composition timeout remains unexplained.** `apps/beamlet_runtime/test/beamlet/composition_test.exs:31` once received no success within its unchanged100ms assertion. The preserved failure has an empty mailbox and no outcome/timing trace. It does not establish a remaining production defect, a baseline defect, a known flake, or a cause related to short executor budgets. See DA5 recommendation below.
3. **Required parent follow-up, DA6: spec matrix is stale.** `.trellis/spec/backend/operation-runtime.md`, section4, still combines observed stops as cancelled. Split deadline-origin `deadline/worker_stopped` from explicit-cancel `cancelled/worker_stopped`, retain the two unconfirmed combinations, document first-trigger ownership, immutable accepted terminals, and the local-exit limitation. Align error-handling references and quality regression lessons. Shared specs were deliberately not edited by this reviewer.

No source/test staging, commits, branch/archive/task-pointer changes, dependencies/configuration changes, or task requirements/design edits were performed by this reviewer. Only this external report and temporary diagnostic files were written. The index was empty at the independent scope comparison; a final read-only check later found task/source/test paths staged by concurrent activity outside this reviewer. No staged state was altered.

## Source and contract reasoning

- `executor_gateway.ex:181`: `stop_worker/3` matches only a running entry with `stop_source: nil`. The atomics exchange, shutdown request and escalation timer execute in the Gateway callback; source is stored before the callback returns. Later triggers retain it. The cancellation atomics reference is private to Gateway and read-only through Worker context; a repository search found no other writer, so a genuine observed stop cannot acquire a nil source through another valid producer.
- `executor_gateway.ex:175`: `observed_stop?/2` is exactly the former causal predicate: cancellation observed and shutdown, or killed with `kill_requested`. Unrelated crash and an unrequested kill stay `error/worker_lost`. The final helper extraction preserves this expression. This remains the approved local causal evidence; it cannot establish external provider cancellation or uniquely attribute indistinguishable external signals.
- `executor_gateway.ex:78/84`: deadline/kill include the worker PID and match the current running task. Wrong PID, missing attempt and terminal atom tombstone are ignored. Deadline no longer queues a second ordinary-cancel message, which is necessary to preserve first-trigger ownership at the callback handling the deadline.
- `executor_gateway.ex:99/127/322`: normal Task result and worker DOWN are alternative completion paths. Task sends its result before exiting; Erlang's same-worker signal order preserves result-before-normal-DOWN delivery. Result normalization/size checks stay intact, and release demonitor-flushes the task, removes task/owner accounting and stores a tombstone. Only a still-inventoried monitor/result can release capacity. Late timers/completions cannot release twice.
- `operation_coordinator.ex:87/246`: attempt, operation ID, execution ID, source, result validity, Gateway/incarnation and matching handle checks remain unchanged. Removing the blanket stopping/reason rewrite preserves Gateway deadline even while explicit cancel is pending. A valid pre-terminal success still wins; valid error and malformed/oversize normalization still produce errors. In particular, a handler-supplied error reason `worker_stopped` alone is not Gateway DOWN evidence and is no longer blindly converted to cancelled. The independent adversarial probe confirms this intentional consequence of removing the blanket rewrite.
- Coordinator result-nil clauses and retained state still enforce one accepted terminal. Its deadline without exit proof is `deadline/termination_unconfirmed`; explicit cancel timeout is `uncertain/cancel_unconfirmed`. Later genuine Gateway shutdown cannot replace either accepted result.
- Admission, lease-age budget reduction, selection, pool charging/release, retention, owner/provider/endpoint loss, one attempt and no retry are unchanged. Existing provider loss kills tasks and readiness drops; owner loss uses ordinary cancellation; infrastructure uncertainty stays Coordinator-owned. No global order across owners or VMs is introduced.

## Regression quality and DA1–DA6 matrix

| Criterion | Independent conclusion | Evidence and limits |
| --- | --- | --- |
| DA1 | Supported; observed defect corrected | New test lines43–58 obtains a genuine Directory report, ages its issuing lease700ms under expiry3000/refresh10000, submits1400ms work and asserts actual remaining budget0..800ms, actual shutdown DOWN and execution-source deadline/worker_stopped. No admission service is blocked. Original red log fails specifically error versus deadline after the preceding DOWN assertion; initial green1, matrix9 and independent focused25 pass. Original red was inspected, not rerun in this review. |
| DA2 | Supported | New unconfirmed cases keep Gateway suspended only after actual worker admission and assert worker still alive at Coordinator acceptance. Resume yields actual shutdown. Existing explicit cancellation plus new kill cases establish confirmed cancelled; both first-source crash cases remain worker_lost. Independent error/malformed/oversize checks exercise normal completion normalization during cancel. |
| DA3 | Supported with scope stated | Six matrix cases cover both first-source orders against kill, unrelated crash and success. Gateway suspension starts after admission; deadline-first is enqueued before public cancel, cancel-first uses Endpoint forwarding fence before enqueueing deadline. This is a local fixture: public cancel sends cleanup before replying, Endpoint state call drains the locally enqueued forward, and Gateway state read after resume verifies the actual stored first source. This establishes local queue ordering, not distributed global time. Matrix deadline triggers are injected genuine timer-message shapes; DA1 separately exercises the actual scheduled execution timer. All cases replay late timer/cancel/completion/admission, check unchanged terminal, zero tasks, restored cpu and no new worker/result. Existing lifecycle/review gates cover owner/provider/Gateway/scope loss and identity rejection. Independent wrong-PID probe passed. |
| DA4 | Supported by independent checks plus inspected gates | Independent focused25 and additional5 pass, final independent format/compile/whitespace pass. Prior neighbor155, umbrella230 and complete replacement named27 logs/exit0 inspected. Final strict Credo and existing-PLT Dialyzer clean after predicate extraction. See commands/counts below. |
| DA5 | Investigation evidence sufficient for explicit parent disposition; not silently accepted | Prior focused2 and one bounded traced2 current pass. Trace contains actual admit/admitted/completed(ok)/sink success under unchanged100ms assertion. Historical event order/outcome remains unknown. Recommend retain as documented historical risk, with no evidenced remaining production defect requiring rejection of this repair. Parent must explicitly accept or retain the risk before whole-task acceptance. |
| DA6 | Pending parent | Independent implementation review passes. Shared-spec synchronization and observation acceptance return remain required; no automatic observation/Web-parent acceptance. |

The test timings use substantial separation and actual state/message fences, but are not hard real-time guarantees under arbitrary VM starvation. The new file remains untracked and must be preserved in the parent's eventual authorized commit. It contains nine cases; temporary adversarial probes did not alter it.

## Independent checks run in this review

All commands ran from `/mnt/data/Project/Beamlet`; logs and exit artifacts are under `/tmp/runtime-deadline-independent/`.

| Exact command | Actual result |
| --- | --- |
| `mix test apps/beamlet_runtime/test/beamlet/deadline_classification_test.exs apps/beamlet_runtime/test/beamlet/runtime_test.exs --seed 631927` | exit0, **25 passed, no selected exclusions**; `focused.log/.exit`. Includes all9 new cases and existing16 Runtime cases. |
| `MIX_ENV=test mix run /tmp/runtime-deadline-independent/adversarial.exs` (initial harness) | exit2, **0/5 passed**; all five fail setup because this reviewer's temporary module rename missed the handler reference. `adversarial.log/.exit` retained. No admitted worker and no product defect established. |
| Same command after correcting only the temporary handler reference | exit0, **5 passed, no exclusions**; `adversarial-corrected.log/.exit`. Cancel racing safe error, handler-supplied worker_stopped error, malformed result and oversize result, plus wrong-PID deadline/kill against a live worker. Each checks terminal/capacity/no redispatch. |
| `mix format --check-formatted` | exit0; `format.log/.exit`. |
| `mix compile --warnings-as-errors` | exit0; `compile.log/.exit`. |
| `git diff --check` | exit0; `whitespace.log/.exit`. |
| Python comparison of `git diff --binary` against `/tmp/runtime-deadline-start/dirty.diff`, excluding only the two repair production paths; starting inventory path-presence check; `git diff --cached --name-only` | passed: unrelated tracked diff byte-identical; every starting inventory path exists; no staged files. Presence comparison alone does not hash historical untracked contents; this reviewer made no source/test writes. |

Focused and adversarial commands ran detached under a180s outer bound with separate per-command logs/exits; corrected probe and final static commands ran detached under120s. No long blocking tool call hid their completion. Initial diagnostic fixture failure is retained and explained, not counted as a product regression or hidden by green results. No repeated composition test-until-green was performed.

## Prior evidence inspected, not independently rerun

These results are implementer/earlier-review evidence, not executions by this reviewer. No source change was made here that warrants repeating all-green broad gates.

| Exact command | Inspected evidence |
| --- | --- |
| `mix test apps/beamlet_runtime/test/beamlet/deadline_classification_test.exs --seed 631927` | `/tmp/runtime-deadline-red.log`: original code exit2,0/1 pass, error vs deadline with actual shutdown assertion already satisfied. Initial green1 and expanded matrix9 logs retained. |
| `mix test apps/beamlet_runtime/test apps/beamlet_agent/test apps/beamlet_node/test apps/beamlet_cli/test --seed 631927` | `neighbors.log/.exit`: exit0, **155 passed,27 distributed excluded**: Runtime43/6 excluded, Agent26, Node68/20 excluded, CLI18/1 excluded. |
| `mix test` | `umbrella.log/.exit`: exit0, seed932522, **230 passed,29 distributed excluded**: Harness35, Actions28, Runtime43/6 excluded, Agent26, Node68/20 excluded, Daemon5/2 excluded, CLI18/1 excluded, Web7. |
| `elixir --sname deadline_classification_gate --cookie <private-test-cookie> -S mix test apps/beamlet_runtime/test apps/beamlet_node/test apps/beamlet_cli/test --only distributed --seed 631927` | Initial combined outer60s tool call interrupted; partial Runtime6 and partial Node output, no complete gate exit. **Not passing evidence.** Original `distributed.log` preserved. |
| `elixir --sname deadline_classification_gate_final --cookie <private-test-cookie> -S mix test apps/beamlet_runtime/test apps/beamlet_node/test apps/beamlet_cli/test --only distributed --seed 631927` | Approved bounded replacement, `distributed-final.log/.exit`: exit0, **27 actually passed,129 ordinary excluded**: Runtime6/43 excluded, Node20/68 excluded, CLI1/18 excluded. Handoff records240s bound and empty epmd before/after. No cookie reproduced. Same-host automation only; Daemon's2 distributed cases remain outside this requested gate. |
| `mix credo --strict` | Initial exit8 complexity finding retained; final `credo-final.log/.exit` exit0,116 files/986 mods-functions/69 checks, no issues after exact predicate extraction. |
| `mix dialyzer` | `dialyzer-final.log/.exit` exit0, **existing PLT up to date**, no rebuild/refresh,0 errors/0 skipped/0 unnecessary skips. |
| `mix format --check-formatted`; `mix compile --warnings-as-errors` | Prior final logs exit0; independently repeated above. |
| `mix test apps/beamlet_runtime/test/beamlet/deadline_classification_test.exs apps/beamlet_runtime/test/beamlet/runtime_test.exs --seed 631927` | Prior `focused-final.log/.exit` exit0,25 passed after helper extraction; independently repeated above. |
| `mix test apps/beamlet_runtime/test/beamlet/composition_test.exs --seed 631927 --trace` | Earlier independent `research/composition-focused.log`:2 passed unchanged assertions; current positive evidence only. |
| `MIX_ENV=test mix run /tmp/runtime-composition-trace.exs` | Script, log and exit inspected: exit0,2 passed; unchanged test required, actual lifecycle messages and successful execution/sink Result captured. Does not recover original failure order. |

Broad/named gates precede only the unchanged-predicate extraction into `observed_stop?/2`. Final focused25 and format/compile/strict Credo/Dialyzer follow extraction; independent focused25/adversarial5/static checks use final source. Active LSP is unavailable on this tool surface; no cache or timeout is represented as clean evidence. No paid-provider, physical-host, release-build or deployment validation is claimed.

## DA5 disposition recommendation and observation readiness

DA5/D5 explicitly requires recording evidence and unknowns and forbids treating nonreproduction as root-cause resolution. The traced composition run is sufficient for its bounded current investigation purpose: it proves actual admission, successful execution and delivery, retaining the original assertion. It cannot reconstruct the historical100ms gap, prove baseline status, or explain it as scheduling or deadline behavior. Trace output across processes is not itself a globally sorted timeline; correlated messages and their successful Result establish the current journey.

**Recommendation:** parent may close the demonstrated deadline P1 and explicitly retain composition as an unresolved historical risk rather than an evidenced remaining production blocker. There is no affirmative evidence from this bounded investigation of another production defect requiring blocking acceptance of the repair. This is a reasoned recommendation, not an automatic waiver or claim the composition issue is fixed. If parent retains it as blocking, DA5 remains pending; if accepted as residual risk, record the unknown cause and require correlated outcome/timing evidence on recurrence before any broader change. No assertion weakening, timeout increase, retry or additional repeated runs are justified by the current evidence.

The repair is ready for parent spec synchronization and a return to observation to disposition its prior blockers. Whole repair/observation/Web acceptance remains the parent's decision after DA5/DA6 work. Worker_stopped proves only local worker exit, never provider cancellation, rollback, absence of effects or cessation of billing. Matching trusted Gateway versions remain necessary for corrected provenance.

```acceptance-report
{
  "criteriaSatisfied": [{"id":"criterion-1","status":"satisfied","evidence":"Independent review report includes prioritized findings, source reasoning, DA1–DA6 matrix, independently executed and inspected evidence, exact counts/exclusions and explicit residual risks; whole-task acceptance deferred to parent DA5/DA6."}],
  "changedFiles": ["/home/kanade/.pi/agent/sessions/--mnt-data-Project-Beamlet--/subagent-artifacts/outputs/81025498-f60d-4be5-bd04-3fa1c16d7348/.trellis/tasks/10-17-runtime-deadline-classification/research/independent-check.md"],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {"command":"mix test apps/beamlet_runtime/test/beamlet/deadline_classification_test.exs apps/beamlet_runtime/test/beamlet/runtime_test.exs --seed 631927","result":"passed","summary":"25 passed, no selected exclusions"},
    {"command":"MIX_ENV=test mix run /tmp/runtime-deadline-independent/adversarial.exs (initial temporary fixture)","result":"failed","summary":"0/5 passed; reviewer handler rename missed setup reference, no product defect; original log retained"},
    {"command":"MIX_ENV=test mix run /tmp/runtime-deadline-independent/adversarial.exs (corrected temporary fixture)","result":"passed","summary":"5 passed; normalized completion/cancel races and wrong-PID timers"},
    {"command":"mix format --check-formatted","result":"passed","summary":"Final source formatted"},
    {"command":"mix compile --warnings-as-errors","result":"passed","summary":"Final compile exit0"},
    {"command":"git diff --check","result":"passed","summary":"No whitespace errors"},
    {"command":"Python starting diff/inventory comparison and git diff --cached --name-only","result":"passed","summary":"Unrelated tracked diff byte-identical and original paths present at comparison; index empty then, concurrent staging observed on final read"}
  ],
  "validationOutput": ["Independent25 focused plus5 adversarial passed", "Inspected prior155 neighboring/27 excluded,230 umbrella/29 excluded,27 named/129 excluded", "Inspected final strict Credo and existing-PLT Dialyzer clean", "Original actual-DOWN red proves repaired baseline defect"],
  "residualRisks": ["Historical composition100ms failure has unknown cause; parent explicit DA5 disposition pending", "DA6 spec sync and observation acceptance return pending", "Active LSP unavailable; same-host distributed tests do not prove physical hosts", "Worker exit does not prove external cancellation or rollback; extreme scheduler delays remain possible"],
  "noStagedFiles": false,
  "diffSummary": "No repository source/test edits by reviewer; external report and temporary diagnostic fixtures only",
  "reviewFindings": ["No remaining production blocker in reviewed repair", "Historical composition risk requires explicit parent disposition", "Shared Runtime matrix and quality/error references require parent synchronization"],
  "manualNotes": "The demonstrated baseline P1 is corrected. DA1–DA4 supported; DA5 needs explicit parent disposition and DA6 remains pending. Observation changes preserved; no task state, spec, commit or configuration edits. Temporary harness failure and successful correction are separately retained. Final read observed concurrent staging after the earlier empty-index scope check; reviewer performed no staging and notified parent."
}
```
