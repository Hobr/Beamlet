# F2 delegation authority validation repair

F2 is repaired on `feat/agent-model-credentials`, baseline `18137b1`. This writer changed only the three Agent/Node paths below and this new report. The initial `check-report.md`, other reports, sibling source/tests, deployment/spec/task state and archives were not edited. No staging, commits, branches, dependencies, paid/live calls or subagents.

## Validation boundary

`ModelBinding.portable?/1` validates the exact binding fields, portable provider ID syntax, common Harness invocation config/credential types and bounds, and placement fields through the existing `Operation.new/1` validation. It never reads a provider registry or invokes an adapter. Config/credentials retain their complete 16,384-byte JSON caps, depth/type/UTF-8 policies, credential entry/name bounds and recursive root rejection. Placement retains Operation's environment/allowed_nodes/claims and complete serialized ceiling validation.

`ModelBinding.valid?/1` requires that portable validation first, then resolves the selected provider in the creating authority's immutable trusted registry and runs its adapter validation. Unknown providers remain rejected at actual creation. Adapter errors/exceptions/throws/exits still normalize safely. `ModelBinding.validate/2`, used at executor invocation, continues to require both common and selected adapter checks; its safe adapter handling is shared with creation.

Server's private option validator selects full binding validation for actual start/init and portable binding validation for delegation. No creation keyword or public flag can bypass actual adapter validation. The common option checks still enforce id, internal delegator type, option allowlist and Tool route validation. Catalogue validation moved into that common option boundary, so invalid catalogues reject before delegation helpers launch, and redundant separate init catalogue validation was removed. Child spec shape/input limits remain in their existing boundary.

The parent thus accepts syntactically valid unknown provider IDs for transport, while actual target creation decides implementation availability and provider-specific configuration. Target creation failures retain the existing safe, correlated delegation `:authority_unavailable` result; this patch does not introduce another error contract. All remote start and target callback work stays in the existing bounded delegation controllers/workers, outside Server callbacks. Explicit immutable bindings remain required; no inheritance, module forwarding, registry synchronization, retry or replay was added.

Operation construction, captured/current deployment caps, public guarded Runtime admission, controller lifetime and resource ownership algorithms are unchanged. No binding or credentials are removed from whole-envelope accounting.

## Files

- `apps/beamlet_agent/lib/beamlet/agent/model_binding.ex`: separate portable and authority adapter validation; share safe adapter invocation handling.
- `apps/beamlet_agent/lib/beamlet/agent/server.ex`: choose the appropriate private binding validator, include catalogue validation in common creation/delegation option checks.
- `apps/beamlet_node/test/beamlet/delegation_binding_test.exs`: three real independent-authority peer regressions.
- `.trellis/tasks/10-17-agent-model-credentials/repair-delegation.md`: this report.

## Regression evidence

The local parent starts standalone AuthoritySupervisor with its default built-in registry. The independent peer runs authority plus executor with only `%{"child-only" => Deterministic}`. Registries are deliberately different. The first test creates the target-only binding directly, actually submits input and observes `"child complete"`, then delegates the same explicit binding and observes the correlated successful child result. It verifies child cleanup/registry retirement and unchanged parent binding.

The second test covers a parent-only provider, an unknown provider and common-valid but adapter-invalid config. Direct target creation rejects each; delegated requests are accepted locally and each yields a terminal error correlated by the returned turn. Local call tracing observes exactly one delegated `Agent.start/2` dispatch per binding and no local Deterministic validation callback. After helper retirement the target Registry has no child and no further dispatch/waiting event arrives during the bounded observation window. This catches retry/late-dispatch behavior rather than merely checking a terminal status.

The third test sends malformed binding/provider/config/credentials/placement, oversized config/credentials, bad catalogue/Tool routes, unsupported creation options and bad delegator types. Parent process spawn tracing verifies no helper spawn; parent stays idle with empty children/helpers and no target child. Common-invalid values reject before dispatch. Existing complete-envelope and reduced deployment byte-cap tests run in the unchanged Node review suite.

Before source repair, the executable regression produced **1/3 passed, 2 failed**, including a completed direct target input followed by local rejection of the identical delegated binding. Preserved `tests-prefixed.log` proves the original F2 defect. After repair all three pass. No existing test file or assertion was weakened.

## Commands and exact results

All commands ran from repository root unless a directory is named. All Mix/Elixir commands used `ERL_FLAGS='+S 2:2'`; named runs used the synthetic cookie `delegation_synthetic_631927` and peers explicitly use two schedulers. Logs and scratch analysis script live under **`/tmp/beamlet-repair-delegation-631927/`**. Logs were not overwritten.

| Command / scope | Result | Log |
| --- | --- | --- |
| Initial new-test named run | Compilation failed because local `binding/1` conflicted with Kernel import; renamed test helper before meaningful regression run | `tests-before.log` |
| `elixir --sname delegation_prefix_631927 --cookie delegation_synthetic_631927 -S mix test apps/beamlet_node/test/beamlet/delegation_binding_test.exs --only distributed --seed 631927` before production repair | **1/3 passed, 2 failed** at parent rejection; meaningful F2 proof | `tests-prefixed.log` |
| Same focused test after initial repair, node `delegation_after_631927` | **3 passed** | `tests-focused-after.log` |
| Intermediate strengthened trace runs | Three separate 2/3 passing runs: unloaded remote trace pattern, unsupported remote tracer PID, then noninherited Task.Supervisor worker trace | `tests-focused-trace.log`, `tests-focused-trace-final.log`, `tests-focused-local-trace.log` |
| Final strengthened focused test, node `delegation_trace_new_631927` | **3 passed**; local newborn-worker tracing observes actual dispatch without remote tracer assumptions | `tests-focused-new-trace.log` |
| `mix test apps/beamlet_agent/test apps/beamlet_node/test --seed 631927` | **Agent 4 passed; Node 57 passed, 6 distributed excluded** | `tests-ordinary-final3.log` |
| `elixir --sname delegation_final3_631927 --cookie delegation_synthetic_631927 -S mix test apps/beamlet_agent/test apps/beamlet_node/test --only distributed --seed 631927` | **Node 6 passed, 57 ordinary excluded; Agent 0 distributed, 4 excluded** | `tests-distributed-final3.log` |
| `mix format --check-formatted apps/beamlet_agent/lib/beamlet/agent/model_binding.ex apps/beamlet_agent/lib/beamlet/agent/server.ex apps/beamlet_node/test/beamlet/delegation_binding_test.exs` | Passed | `format-final2.log` |
| Agent app `mix compile --warnings-as-errors` | Passed | `compile-agent-app-focused.log` |
| Node app `mix compile --warnings-as-errors` | Passed | `compile-node-focused.log` |
| Initial focused strict Credo | One complexity finding after adding catalogue check; moved catalogue check to keyword guard and removed redundant init check | `credo-final.log` |
| `mix credo --strict 'apps/beamlet_{agent,node}/{lib,test}/**/*.{ex,exs}'` | **33 files, 69 checks, no issues** | `credo-final2.log` |
| Initial focused Dialyzer against existing PLT, Agent/Node BEAMs only | **15 stale Harness missing-export warnings**, analysis input issue | `dialyzer-final.log` |
| `mix run --no-start --no-compile /tmp/beamlet-repair-delegation-631927/dialyzer-agent-node.exs` with current Harness dependency BEAMs included | **28 BEAM modules, 0 warnings**; existing PLT, `check_plt: false`, no refresh | `dialyzer-current-dependency-final.log` |
| `git diff --check` / `git diff --cached --name-only` | Passed / empty | `diff-check-final.log`, `staged-files-final.log` |

Root warning-fatal compile also passed (`compile-final2.log`); this is distinct from the two focused owning-app compiles. Earlier passing ordinary/distributed logs are retained with `final`/`final2` suffixes; `final3` is the final test evidence after the last source refinement. Final total is **67 actual affected test executions: 61 ordinary +6 distributed**. Named Agent's no-test notice is explicitly excluded from that count. Expected deliberate-kill Registry/gateway diagnostics are emitted by the existing lifecycle suites.

## Lifecycle preservation and remaining fresh recheck

Delegation/Lifecycle/Resources/OperationOwner and their existing tests were untouched. The passing ordinary Node suite preserves actual DOWN before resuming suspended admission/infrastructure, parent startup authorization before input, nested child/grandchild cleanup, retained resource slots until DOWN, late child creation rejection, blocked acknowledgement/retirement, stop/parent/authority loss and no replay. Existing named child-authority-disconnect and HTTP held-request/executor-loss regressions also passed. New tests verify retired helpers and no late dispatch after rejected target creation.

No F2 blocker or scope contradiction remains known. Main owns fresh independent recheck and the scheduled once-only integrated umbrella/distributed/release acceptance. Historical F1 Harness35/F3 Actions28 and integration138/9 are not fresh integrated acceptance. With the three new distributed tests, the expected integrated named count becomes **12** (Runtime6 +Node6), replacing historical9. Harness/Actions suites and copied-release gates were not rerun here. Static analysis includes current Harness BEAMs solely to resolve stale dependency information; no sibling mutation or suite was performed. No complete LSP coverage, refreshed PLT, physical-host or live-provider result is claimed. Same-host peer evidence and bounded no-late-event observations retain their ordinary limits.
