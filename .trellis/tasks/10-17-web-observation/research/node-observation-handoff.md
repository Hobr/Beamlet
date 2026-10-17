# Stage B — Runtime / Node observation handoff

Stage B is implemented and locally verified. This is a stage handoff, **not whole-child acceptance**. Independent trellis-check across Stages A/B and implemented-spec synchronization remain next. No commit/staging/branch/archive/task-pointer/config/dependency/shared-spec or Agent/CLI/Web edits were made by this stage. Existing Agent diffs and untracked files were preserved.

## Ownership and changed files

- `apps/beamlet_runtime/lib/beamlet/runtime.ex`: additive public observation/0 and contract documentation.
- `apps/beamlet_runtime/lib/beamlet/runtime/directory.ex`: owner-side safe report projection and source-local receipt age.
- `apps/beamlet_runtime/lib/beamlet/runtime/observation.ex` (new): disposable finite local owner reads; shared monotonic deadline helpers, no application service.
- `apps/beamlet_runtime/test/beamlet/observation_test.exs` (new): four report safety/freshness/count/byte/no-dispatch tests.
- `apps/beamlet_node/lib/beamlet/node.ex`: additive observation/0 and observe/1, documented contracts; passes only roles as new immutable metadata to Routes.
- `apps/beamlet_node/lib/beamlet/node/routes.ex`: safe roles owner read. No full startup config copy.
- `apps/beamlet_node/lib/beamlet/node/observation.ex` (new): local configured-role/readiness projection, isolated bounded erpc aggregation.
- `apps/beamlet_node/test/beamlet/observation_test.exs` (new): eight local contract/lifecycle/role/pressure tests.
- `apps/beamlet_node/test/beamlet/observation_distributed_test.exs` (new): four actual named-peer observation/lifecycle/resource tests using existing :peer/TestBoot fixture patterns.

Directory remains report owner. Routes owns only immutable role declarations in addition to its existing routes/catalogue. No new query endpoint/supervision tree, provider/model/tool invocation, operation submission, scheduling/admission/lifecycle mutation, automatic retry, persistence or identity-island dependency was introduced. Node uses registered service presence rather than reading private Agent state. Core dependency manifests remain unchanged; Runtime has no Agent/Harness/Web dependency.

## Exact public contracts

### Beamlet.Runtime.observation/0

Returns `{:ok, %{version: 1, source: node_atom, expiry_ms: positive_integer, reports: [report], complete: boolean}}` or `{:error, :timeout | :unavailable | :limit}`.

Directory enumerates current unique pg endpoint members, sorted by endpoint PID, selecting at most256. A missing report entry is exactly `%{node: node_atom, status: :not_reported, age_ms: :unknown}`. A received report entry is exactly `%{node: node_atom, status: :fresh | :stale, age_ms: nonnegative_integer, ready: boolean, execution_ready: boolean, capabilities: [public_label], environments: [public_label], available: %{pool_label => nonnegative_integer}}`. There may be multiple endpoint observations for a node; these are not a role inventory or per-node capacity sum. Empty reports means no observed members; not_reported means a current endpoint lacks a retained validated report. Neither proves death. Missing quantities remain absent/unknown, not zero.

Age is calculated **by Directory on the VM that received the report**, as max(0, current local monotonic milliseconds minus local receipt time). Source is that Directory VM, whereas report.node identifies the reported endpoint VM. Fresh means age <= Directory expiry_ms. The receiver must never subtract clocks across VMs. This is receipt freshness, not producer creation time, network RTT, liveness, reservation or current execution eligibility. Directory already retains stale reports while endpoints remain members, and removes reports on departure/DOWN/refresh membership pruning; scheduling still uses existing fresh/1 unchanged. Projection does not fabricate stale history after removal.

Report cap256; excess membership sets complete=false. Full serialized Runtime `{:ok, map}` <=1,000,000 bytes; overflow returns limit without partial data. Local read budget5000ms. Raw endpoint/gateway/provider PIDs, incarnation references, leases, raw monotonic timestamps, handlers/modules/settings/model configuration/credentials/roots and utilization are omitted. Available quantities come only from the validated report; no total capacity, physical utilization or reservation is inferred.

### Beamlet.Node.observation/0

Returns `{:ok, observation}` or static timeout/unavailable (including bounded Routes metadata failure). The normal exact observation keys are:

```
%{version: 1, node: node_atom, configured: boolean,
  roles: [role_atom] | :unknown,
  services: service_map | :not_configured,
  runtime: {:ok, runtime_observation} | {:error, reason}}
```

If no local Node supervisor exists: configured=false, roles=:unknown, services=:not_configured, runtime={:error, :not_configured}. This describes absence of the Node composition even if independent Runtime processes exist. Otherwise roles preserve the trusted startup declaration, never inferred from reports. All seven role subsets are supported. Interaction is only a declaration; no fictitious interaction worker is created.

Service map has exactly routes/runtime/authority/executor keys with values ready/unavailable/not_configured. Ready means all required registrations are present at the instant checked, **not a responsiveness or external-provider health check**. Runtime requires SharedSupervisor/Directory/NodeEndpoint; authority requires AuthoritySupervisor/Registry/Resources/Agents/Delegations; executor requires Provider/ExecutionSupervisor/ExecutorGateway/Workers; routes requires Routes. Authority readiness is independent of executor reports. Configured service absence is unavailable; absent role is not_configured. A suspended registered service may still be ready while its read reports timeout. Startup/restart races are eventual/non-atomic facts. Node supervisor identity is checked across the metadata/runtime read; replacement yields unavailable.

Node local observation explicitly supports node()==nonode@nohost. It has5000ms budget; Runtime data fits its1,000,000-byte reply limit with bounded Node overhead below1MiB. Nested Routes/Directory calls consume the remaining shared source deadline instead of independently resetting5000ms.

### Beamlet.Node.observe(nodes)

Targets must be a proper list of at most32 distinct trusted atoms, excluding nil/true/false. Invalid types, improper lists, duplicates or excess count return `{:error, :invalid_query}` wholly. No arbitrary string is atomized. Empty target list succeeds complete=true.

Returns `{:ok, %{nodes: %{target_node => observation}, failures: %{target_node => :unavailable | :timeout | :limit}, complete: boolean}}`. Local node() is eligible even when distribution is off. Only remote nodes connected at entry are eligible; initially disconnected targets become unavailable without connection attempts. Standard OTP can reconnect after a successful precheck; no stronger never-reconnect guarantee is made.

At most8 active target workers; queued work shares one5000ms aggregate receive deadline. Each worker receives only the remaining budget. Complete full serialized `{:ok, aggregate}` <=1,048,576 bytes; retain reserves16,384 bytes for all32 possible failure entries before accepting each node. Overflowing node becomes limit without truncating its observation; subsequent failures still fit. A bounded Runtime error may preserve the safe node role/readiness observation **and** add its per-node failure; Runtime count incompleteness sets failure limit. No Node composition is a successful explicit configured=false observation, not a transport failure. complete=true covers the requested target set and full Runtime report coverage, not current health, atomicity or freshness. Stale reports are explicit data and do not themselves mark aggregate incomplete. Unavailable readiness is a service fact, separate from read completeness.

## Transport lifecycle and limitations

Reuses existing Task.async_stream isolation and fixed erpc entry patterns without coupling to Agent.Discovery. Every owner GenServer.call has a finite timeout. Local disposable task chains are linked to their requesting stream; caller loss retires blocked readers. Aggregation has a disposable scheduler with linked per-target workers. Deadline expiration kills/observes worker DOWN; outer isolation bounds scheduler receipt. Task/erpc/GenServer reply correlation isolates late replies. Tests observe actual reader DOWN while Directory remains suspended, before resumption. Remote delayed-code-load tests observe bounded local task-tree retirement before code_server resumes.

`Observation.local_read(budget)` is an internal fixed erpc entry with relative integer budget1..5000ms, validated on the executing VM. Delayed remote execution can start after the aggregate caller has abandoned its response, but every newly issued owner read is still finite and nested reads share that entry's source deadline. No instantaneous remote cancellation, mailbox retraction, hard real-time scheduling guarantee or absolute cross-VM deadline is claimed. Timeout can discard already collected partial data at the outer deadline, conservatively reporting all targets timeout; successful node data is never invented. Reads are eventual/non-atomic; matching library versions and trusted distributed peers remain required. Limits bound returned count/serialized bytes, not hostile-peer memory/RSS or the underlying pg membership inventory.

## Verification evidence

All commands ran at `/mnt/data/Project/Beamlet`, seed631927. Logs are retained in /tmp; original failed logs were not overwritten.

Final ordinary suite:

`mix test apps/beamlet_agent/test apps/beamlet_runtime/test apps/beamlet_node/test apps/beamlet_cli/test --seed 631927`

`/tmp/node-observation-regression-final.log`: **146 passed** (Runtime34, Agent26, Node68, CLI18),27 distributed excluded (6+20+1). Last source edits precede this run. Subsequent test-only change replaced one fully qualified fixture call with an alias for strict Credo; `mix test apps/beamlet_runtime/test/beamlet/observation_test.exs --seed 631927` then passed4 (`/tmp/node-observation-runtime-focused-final.log`). No production changes followed.

Actual named distributed gate:

`elixir --sname observation_stage_b_gate --cookie observation_stage_b_gate_test -S mix test apps/beamlet_runtime/test apps/beamlet_node/test apps/beamlet_cli/test --only distributed --seed 631927`

`/tmp/node-observation-distributed-final.log`: **27 executed/passed** (Runtime6, Node20 including new observation4, CLI1);118 ordinary excluded at execution time (32+68+18). Runtime later gained two ordinary tests, accounting for its final34 above. Same-host named peers are not physical-host acceptance. OTP global overlapping-partition warnings occurred during peer disconnect/teardown; all selected tests executed and passed.

Checks after final edits:

- `mix format --check-formatted`: exit0, `/tmp/node-observation-format-last.log`.
- `mix compile --warnings-as-errors`: exit0, `/tmp/node-observation-compile-last.log`.
- `mix credo apps/beamlet_runtime --strict`: exit0,16 files,171 mods/functions,69 checks/no issues, `/tmp/node-observation-credo-runtime-gate3.log`.
- `mix credo apps/beamlet_node --strict`: exit0,25 files,181 mods/functions,69 checks/no issues, `/tmp/node-observation-credo-node-gate2.log`.
- `python3 /tmp/node-observation-lsp/probe.py`: active didOpen diagnostics received/empty for all six changed source files. Probe disables LSP Dialyzer and has finite initialization/diagnostic timeouts; output/results/transcript/stderr under `/tmp/node-observation-lsp/`. Source unchanged since probe.
- `git diff --check`: passed. `git diff --cached --name-only`: empty. No staged files.

Focused coverage: all seven actual role trees plus absent Node; authority/executor service termination and real restart; report absence/fresh/stale/source-local age; omission of private report fields; report256-count and whole-reply byte pressure; available pools and zero operation/worker dispatch; malformed/duplicate/improper/33 distinct atom targets; aggregate byte reserve; suspended owner abandonment and actual DOWN before resume; finite nested source read; real named authority/executor and disconnected partial failure; remote suspended reader DOWN before resume/late-reply isolation; caller-loss task-tree DOWN before delayed module loading; ten delayed named targets proving8 requests and one5s deadline. Existing identity-discovery/default CLI regressions passed alongside.

## Failed and intermediate evidence / unresolved risks

1. `/tmp/node-observation-regression-first.log` failed existing RuntimeTest deadline assertion at runtime_test.exs:91: expected deadline, observed error/worker_stopped after actual worker shutdown. Focused `mix test apps/beamlet_runtime/test/beamlet/runtime_test.exs:87 --seed 631927` reproduced it (`/tmp/node-observation-runtime-deadline-diagnostic.log`,0/1 passed,15 excluded). Source inspection finds competing gateway execution_deadline and coordinator deadline timers; gateway reduces remaining budget by report lease age and classifies cancellation DOWN as worker_stopped, allowing a plausible earlier execution result. Exact ordering is not traced/proved; this is **unresolved**, not labeled a known flake. No business lifecycle/scheduling changes, retries, or assertion weakening were made. Later second/full final ordinary gates passed the existing test. Supervisor was informed.
2. The same first regression failed the new executor restart fixture because terminating execution also triggers NodeEndpoint gateway-loss and SharedSupervisor one_for_all restart, racing explicit restart_child. Corrected the test to terminate NodeEndpoint first, then execution; assert unavailable, restart execution and endpoint, assert ready. This fixes controlled fixture ownership without weakening service readiness assertions. Subsequent focused/full gates passed.
3. Historical Stage A composition100ms failure remains `/tmp/agent-display-regression-final.log`, root cause unresolved. It did not recur in these full ordinary gates. Do not claim this observation stage diagnosed it or call it a known flake.
4. First strict Credo found aliases/nesting issues (`/tmp/node-observation-credo-runtime-first.log`, `/tmp/node-observation-credo-node-first.log`); corrected with small observation-only helper extraction. A two-positional-app invocation checked0 files (`/tmp/node-observation-credo-first.log`) and is not evidence. Adding the last Runtime tests exposed one additional alias suggestion (`/tmp/node-observation-credo-runtime-gate2.log`); corrected, final gate3 passed. Earlier clean candidates are superseded by final logs.
5. Early focused10 tests passed (`/tmp/node-observation-focused-first.log`, `/tmp/node-observation-focused-second.log`). Early named observation3 passed (`/tmp/node-observation-distributed-first.log`); final named suite includes fourth caller-abandonment test. Second full ordinary gate passed144 (`/tmp/node-observation-regression-second.log`), superseded by final146 after added no-dispatch/count tests.

Independent whole-child trellis-check, shared-spec synchronization, Dialyzer/full-umbrella/release checks remain parent-owned next-stage decisions. No deployment, physical-host, paid-provider or secret-erasure guarantee is made. All source/tests remain uncommitted, and new files must be included by the eventual parent commit. This authoritative external handoff is intended for parent retention-managed copying into the task research directory.
