# Independent observation review

**Whole-child acceptance: BLOCKED.** The observation implementation has supporting evidence for OA1–OA5, with no remaining observation-specific production defect found in this review. A proved baseline Runtime deadline classification defect remains a full-gate blocker, and the historical composition failure remains unexplained. A successful later suite does not waive either item. Supervisor explicitly directed no Runtime lifecycle repair here and no whole-child acceptance.

Reviewed baseline: `e7f59d187014d79eea4a63b2450980b77c4630f2`. Read every check.jsonl reference, child PRD/design/implementation plan, parent design §4 and execution gates, both stage handoffs, and `.agents/skills/trellis-check/SKILL.md`. Inspected all seven tracked source diffs and all eight untracked source/test files. No commit, staging, branch, archive, task-pointer, config/dependency, shared-spec or task-document changes. Only the Node observation test described below was edited. Existing source and original logs were preserved.

## Findings in priority order

### P1 — baseline deadline expiry can become `error/worker_stopped`; acceptance blocker

Locations:

- `apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex:193`: remaining execution budget is reduced by report lease age (helper at line215); timer installed at line243.
- Same file, line91: execution deadline feeds ordinary cancellation.
- Same file, line145: worker DOWN generates status `:error`, with `:worker_stopped` for a cancellation-observed shutdown.
- `apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex:35`: independent full-operation deadline timer.
- Same file, line94: valid completion is accepted before that timer; only explicit `s.stopping` changes worker_stopped to cancelled. The subsequent deadline cannot replace an accepted result.
- Existing regression: `apps/beamlet_runtime/test/beamlet/runtime_test.exs:87`, assertion91.

User-visible consequence: a held operation whose executor budget expires can return a generic execution error before the coordinator deadline, although the worker actually stopped. Terminal classification depends on timer ordering/report age. Consumers cannot reliably interpret this as deadline expiry. This is real business behavior, not simply an assertion timeout.

Bounded causal experiment, with no observation calls and no production edits:

1. `/tmp/independent-observation/deadline_trace.exs` starts Runtime with the existing hold handler, budget50ms, expiry100ms, refresh1000ms and a controlled20ms wait after eligibility. The slower refresh makes one valid, aged report deterministic rather than waiting for a lucky scheduler order. Other relevant timer settings match the original regression (cancel20ms, retention300ms).
2. BEAM receive/send traces cover Gateway and newly spawned Coordinator, with monotonic timestamps. Candidate trace selected a lease approximately27ms old and passed23ms to Worker. Gateway received execution_deadline, cancelled, received worker DOWN/shutdown, sent completed(error/worker_stopped), and Coordinator accepted it roughly25ms before its own deadline.
3. A second isolated VM loaded **the exact baseline Runtime facade and complete Directory/NodeEndpoint source** using `git show e7f59d1:<path>` and `Code.compile_string/2`. These are the only Runtime source files changed by this child. Gateway/Coordinator are unchanged from HEAD. Baseline reproduced error/worker_stopped too (worker budget22ms). Nothing was written to source or beam files by this transient compilation.

Commands:

```
MIX_ENV=test mix run /tmp/independent-observation/deadline_trace.exs
OBS_BASELINE=1 MIX_ENV=test mix run /tmp/independent-observation/deadline_trace.exs
```

Authoritative controlled logs: `/tmp/independent-observation/deadline-candidate-controlled.log`, `/tmp/independent-observation/deadline-baseline-controlled.log`. Both commands exited0, but their result is **defect reproduced**, not a successful correctness assertion. Script-only module-redefinition/unused-variable warnings are visible; they are not warning-fatal product compile evidence.

Earlier exploratory logs `/tmp/independent-observation/deadline-{candidate,baseline}.log` suspended NodeEndpoint. That also blocked admission, produced coordinator deadline with no worker, and therefore did not test the competing executor timer. They were retained and superseded by the controlled method above; no retry-until-green loop was used.

Preserved original failures: `/tmp/node-observation-regression-first.log` and `/tmp/node-observation-runtime-deadline-diagnostic.log` (the latter executed1, failed1, excluded15). They show error/worker_stopped plus actual worker shutdown, but contain no event trace. The controlled reproduction proves the mechanism and its existence at baseline; it cannot reconstruct the exact original event ordering.

**Disposition:** supervisor instructed no out-of-scope repair and no waiver. Minimal proposed separate repair scope: Gateway cancellation provenance and Coordinator terminal classification, with focused Runtime tests. Retain lease-age reduction and single-terminal/one-attempt semantics. Add a deterministic valid-aged-report case proving worker DOWN and the agreed deadline classification before the Coordinator timer; separately preserve explicit cancellation, unrelated worker crashes, racing success, escalation and late-completion rejection. Product decision is needed on deadline status/reason when termination is already observed. Do not merely accept `:error` in the existing test or remove the conservative lease policy. Risks include changing cancelled/error/deadline precedence and falsely claiming upstream cancellation.

### P2 — historical Runtime composition failure remains unexplained

`/tmp/agent-display-regression-final.log`: `RuntimeCompositionTest`, composition_test.exs:23/assertion31, no success result after100ms and empty mailbox. It supplies no terminal outcome or timing trace. The eligibility barrier checks Directory selection, not eventual execution completion. The source has an ordinary100ms assert_receive and a default60s operation budget; the proved short-budget defect above does not itself explain this failure.

One bounded current reproduction:

```
mix test apps/beamlet_runtime/test/beamlet/composition_test.exs --seed 631927 --trace
```

`/tmp/independent-observation/composition-focused.log`:2 passed; standalone execution case16.3ms, shared-only20.7ms. Full umbrella also passed these tests. This is current positive evidence only. Original root cause is unknown; neither baseline status nor scheduling-delay causality is proved. No timeout/assertion weakening, business retry or lifecycle edit was made. Remains a residual acceptance investigation item for parent disposition.

### P2 — misleading aggregate reserve test fixed locally

`apps/beamlet_node/test/beamlet/observation_test.exs:101` originally reduced30 times into the same failure key `:c`; map replacement exercised only one later failure. It did not substantiate the stated many-failure reserve coverage.

Changed this fixture to30 distinct existing atom targets and assert exactly31 failures (oversize `:b` plus30 timeouts), one retained node and full serialized reply <=1MiB. No production code changed. Final focused suite8 passed; format, warning-fatal compile, strict umbrella Credo and diff whitespace rechecks passed.

This remains a pure reducer pressure test with a synthetic payload, not32 real connected peers or maximum-length target names. Runtime's byte-overflow fixture likewise deliberately injects oversized private state; it demonstrates defensive output rejection rather than report-validator acceptance. These limits on what tests prove are explicit.

## Contract review and OA matrix

| Criterion | Observation-specific conclusion | Evidence and limits |
| --- | --- | --- |
| OA1 | Supported | DisplayTest real two-turn model/two-tool flow checks immutable invocation and complete neutral requests, stable source entry references/turns, reverse tool completion with canonical order, actual child Ref/turn and delegation continuation. Metadata option is optional and strictly whitelisted. Server annotations contain only id/turn references aligned to source messages, without a second transcript. Metadata describes trusted caller IDs; it is not independent verification of preset provenance. |
| OA2 | Supported | Projection tests cover8191/8192/8193-byte text, multibyte split widths,32 entries/16 activities,131072-byte display target and1048000-byte envelope pressure. Final/progress and full model history remain intact; compact marker or complete display omission replaces prior display under pressure. Synthetic24-activity fixture stresses the projector beyond normal tool-batch8. |
| OA3 | Supported | Runtime source computes max(0, local-now minus local receipt) and fresh at age<=expiry. Missing live member reports are not_reported/unknown; stale retained reports are distinct. Safe projection exposes only validated report labels/readiness/available quantities; no totals or utilization. Local Node tests cover all seven actual role trees, absent Node, authority/executor availability and controlled restart. Named stage gate exercises actual authority/executor peers. Readiness is registration presence, not responsiveness or health. |
| OA4 | Observation-specific evidence supported; full regression acceptance blocked | Same envelope/Ref/sequence, sink identity ack,16 credits, coalescing, sink DOWN, stale turn/ref and identity-island tests; suspended local Agent and local/remote Directory reads. Runtime count/byte tests and worker/coordinator counts support zero dispatch. Named resource fixture observes8 requests over10 delayed peers and one5s receive budget; caller-loss fixture observes helper DOWN before code-server resume. Existing Runtime deadline failure remains blocking independently of these read paths. |
| OA5 | Supported | Default snapshot retains exactly seven fields and CLI defaults; strict metadata rejects raw config/credentials/root/module fields, malformed/improper lists and excessive bytes. Real display fixture uses private config/credential/root markers absent from generated observations. Directory uses explicit safe keys, Routes adds only roles; no dependencies/config or new query service. Existing CLI and discovery regressions passed. Content may itself echo secrets; no secret-erasure guarantee. |

No remaining observation-specific production blocker identified. These rows describe reviewed evidence; they do **not** mark the child accepted.

Additional source/lifecycle review:

- Display activity requires actual current-turn owner/pending/result, excluding prepared sibling calls; terminal cleanup removes activities. Child identities come from successful child input/subscription, not helper placement. Coverage is live_context, with unknown executor placement and explicit omissions.
- Runtime observations bound reports256 and full serialized reply1,000,000 bytes. Node validates proper/distinct target lists<=32 with no atomization, includes nonode local VM, snapshots connected remotes at entry, uses8 workers/shared5s budget, measures the full1MiB outer result and reserves failure space. Already-issued OTP calls may reconnect after precheck and delayed remote entries receive their own finite relative budget. These documented transport limitations agree with existing discovery contracts.
- Owner reads consume remaining source deadline; linked disposable task isolation and correlated OTP replies avoid caller mailbox pollution. Deadline cleanup monitors actual worker DOWN. No model/tool submission, provider execution, scheduling mutation, new endpoint, authority-island dependency, persistence or raw-state projection was introduced.
- Node roles come from startup-only Routes metadata. Same Node supervisor identity is checked across role/runtime reads. Service registrations are eventual/non-atomic; a suspended service can still be registered ready with runtime timeout. No atomic tree-health claim is supported.
- Executor restart fixture at observation_test.exs:46 deliberately removes NodeEndpoint before terminating ExecutionSupervisor, avoiding gateway-loss-triggered SharedSupervisor one_for_all teardown. This is a valid controlled service-unavailability/restart test. It does **not** independently prove the natural coupled crash transition. Existing Runtime/Node gateway/provider-loss tests supply complementary lifecycle regression coverage. The fixture's scope must stay explicit.

## Actual validation

All commands ran at repository root. New logs are under `/tmp/independent-observation/`; existing failure logs were not overwritten. Exit status files accompany the main gates.

| Command | Result / log |
| --- | --- |
| `mix test` | exit0; seed144391; **221 passed,29 distributed excluded**. Harness35, Actions28, Runtime34/excluded6, Agent26, Node68/excluded20, Daemon5/excluded2, CLI18/excluded1, Web7. `umbrella.log`. Ran before the one test-only fixture fix. |
| `mix credo --strict` | exit0;115 source files,975 mods/functions,69 checks, no issues; `credo.log`. |
| `mix dialyzer` | exit0; existing PLT current; **no PLT refresh/rebuild**, analysis0 errors,0 skipped,0 unnecessary skips; `dialyzer.log`. |
| `mix sobelow` | exit0, scan complete, no findings; root alias scans existing Web. `sobelow.log`. |
| `mix test apps/beamlet_node/test/beamlet/observation_test.exs --seed 631927` | exit0, **8 passed**, no excluded selected tests; `node-focused-final.log`, after test fix. |
| `mix format --check-formatted` | exit0 after fix; `format-final.log`. |
| `mix compile --warnings-as-errors` | exit0 after fix; `compile-final.log`. |
| `mix credo --strict` | exit0 after fix;115 files/975 mods-functions/69 checks, no issues; `credo-final.log`. |
| `git diff --check` | exit0. |
| `git diff --cached --name-only` | empty; no staged files. |
| Composition focused command above | exit0,2 passed; historical cause still unresolved. |
| Controlled candidate/baseline diagnostics above | exit0 scripts, both reproduce semantic defect; not passing business correctness tests. |

Previous actual named gate independently inspected, not rerun without cause:

```
elixir --sname observation_stage_b_gate --cookie <private-test-cookie> -S mix test apps/beamlet_runtime/test apps/beamlet_node/test apps/beamlet_cli/test --only distributed --seed 631927
```

`/tmp/node-observation-distributed-final.log`: **27 executed/passed** (Runtime6, Node20 including4 observation tests, CLI1);118 ordinary excluded at that execution point (Runtime32, Node68, CLI18). Later Runtime gained2 ordinary tests, explaining current34. Distributed production/test source unchanged by this review; the local fixture fix does not affect that gate. Named same-host peers establish transport automation, not physical deployment. The umbrella's29 excluded distributed tests also include2 Daemon tests outside the recorded27-app named gate; no claim they were executed here.

Stage handoffs record scoped source LSP diagnostics and prior146 ordinary passes; this review's full existing-PLT Dialyzer supplies broader static evidence. No LSP cache/timeout is treated as proof. No alternate model/provider/CLI workaround was used.

## Parent follow-up and remaining gates

1. Resolve baseline deadline defect and historical composition uncertainty explicitly before whole-child acceptance. Supervisor owns business semantics/scope and any separate repair authorization.
2. Sync implemented backend specs for opt-in display/schema/omission, safe metadata, report age, readiness and finite read/aggregation limitations after acceptance. Shared specs were intentionally preserved by this reviewer.
3. Preserve the new untracked implementation/test files in the eventual parent commit. No task closure or commit occurred.
4. Later Web integration owns host/preset resolution, escaped rendering, handle/Ref identity, create/input uncertainty, browser interaction, security, disconnect/restart journeys and parent integration gates. Asset build/deploy and Web release packaging are inapplicable to this core-only child. Backend deployment smoke is conditional on release/config/manifest changes; none occurred. Full repository pre-commit (including benchmark/SBoM) was not run; no commit requested. No paid-provider or physical-host claim.

```acceptance-report
{
  "criteriaSatisfied": [{"id":"criterion-1","status":"satisfied","evidence":"Complete independent result, prioritized causal findings, OA1–OA5 evidence, exact checks/counts and residual risks recorded; whole-child acceptance explicitly blocked."}],
  "changedFiles": ["apps/beamlet_node/test/beamlet/observation_test.exs"],
  "testsAddedOrUpdated": ["apps/beamlet_node/test/beamlet/observation_test.exs"],
  "commandsRun": [
    {"command":"mix test","result":"passed","summary":"221 passed,29 distributed excluded; seed144391"},
    {"command":"mix credo --strict","result":"passed","summary":"115 files,69 checks, no issues; final recheck also passed"},
    {"command":"mix dialyzer","result":"passed","summary":"Existing PLT current;0 errors,0 skipped; no refresh"},
    {"command":"mix sobelow","result":"passed","summary":"Web scan complete, no findings"},
    {"command":"mix test apps/beamlet_node/test/beamlet/observation_test.exs --seed 631927","result":"passed","summary":"8 passed after reserve fixture correction"},
    {"command":"mix format --check-formatted","result":"passed","summary":"Final formatting clean"},
    {"command":"mix compile --warnings-as-errors","result":"passed","summary":"Final product compile clean"},
    {"command":"mix test apps/beamlet_runtime/test/beamlet/composition_test.exs --seed 631927 --trace","result":"passed","summary":"2 passed; original failure cause unresolved"},
    {"command":"MIX_ENV=test mix run /tmp/independent-observation/deadline_trace.exs (candidate and OBS_BASELINE=1)","result":"failed","summary":"Scripts exit0 but reproduce incorrect error/worker_stopped before coordinator deadline on both candidate and baseline"},
    {"command":"git diff --check","result":"passed","summary":"No whitespace errors; staging empty"}
  ],
  "validationOutput": ["Observation-specific OA evidence supported; full-child acceptance blocked", "Prior named gate log inspected:27 passed,118 ordinary excluded; not rerun"],
  "residualRisks": ["Proved baseline deadline classification defect remains unrepaired by supervisor decision", "Historical composition100ms failure remains unexplained", "Controlled restart fixture does not itself exercise natural coupled restart", "Same-host named tests do not prove physical deployment; later Web integration remains"],
  "noStagedFiles": true,
  "diffSummary": "Review changed one local aggregation test to use30 distinct failure targets; no production changes",
  "reviewFindings": ["P1 baseline Runtime deadline classification blocker", "P2 historical composition failure unresolved", "P2 weak reserve fixture corrected and focused recheck passed"],
  "manualNotes": "All original failures and new candidate/baseline traces retained. Supervisor prohibited out-of-scope lifecycle repair and waived no failed gate. Task/spec/commit state untouched."
}
```
