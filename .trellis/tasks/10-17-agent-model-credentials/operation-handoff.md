# Operation component handoff

Operation lane complete on feat/agent-model-credentials, baseline18137b1. Only Actions/Runtime source/tests and this handoff were changed. Harness edits preserved. No dependencies, staging, commits, branch/task-state edits, live/paid requests or physical-host coverage.

## Exact consumer contracts

`%Beamlet.Actions.Operation{credentials: %{}}` adds an optional dedicated field, default empty. `Operation.new(attrs)` returns `{:ok, operation}` or `{:error, :invalid_operation}`; `Operation.validate/1` returns `:ok` or that same safe error. Malformed credentials never appear in returned errors.

`Beamlet.Actions.credentials?/1` is the owning generic boolean validator. Root must be a plain string-key map with <=32 entries, top-level names 1..128 UTF-8 bytes, depth <=24 (root depth0; map keys/values and list elements increment depth), and complete encoded JSON <=16384 bytes. Uses OTP29 built-in `:json.encode/1` and `IO.iodata_length/1`; no Jason or Harness dependency. Supports valid UTF-8 strings, numbers, true/false/nil, proper lists, nested plain string-key maps. Rejects structs, executable/process/reference/port/tuple values, other atoms, improper lists, invalid UTF-8, and root/workspace_root keys recursively. Nested field names have no additional top-level count/name constraints.

Only credentials bypass ordinary secret-name rejection. Operation validates `Map.delete(Map.from_struct(op), :credentials)` through the unchanged ordinary `Actions.bounded?/2` policy. Payload/metadata/Result/progress policies remain intact. Config remains ordinary payload data; no provider or config parsing was added here.

The authoritative protocol bound remains `:erlang.external_size(full_operation) <= 262144`, including struct overhead and credentials. Public `Runtime.submit/2` and ExecutorGateway retain their existing full Operation external-size checks against current deployment `operation_bytes`; overrides cannot increase protocol ceilings. Exact protocol and reduced1024-byte boundaries have regression tests. JSON credential size and full Operation Erlang size are separate limits, both enforced.

Worker internal MFA is now `Worker.run(module, payload, credentials, settings, gateway, remaining, limits, cancellation)` (arity8), called only by Gateway. Handler API remains `run(payload, context)`. Context has `credentials` unchanged, executor-local `settings`, `remaining_ms`, `progress/1`, `cancelled?/0`. No provider interpretation, registry dependency, secret cache or merging with settings. Existing handlers that ignore credentials continue working with `%{}`. Caller/Agent lane must place only model credentials here; Tool invocations should retain default empty credentials. Handler native invocation construction should use `context.credentials` explicitly and revalidate through Harness/provider APIs.

Generated progress/status/Result/report/error projections were not changed to include credentials. Tests observe credentials through an explicit test-only handler message while asserting normal progress/final result/status/report contain no credential field or synthetic secret. A remote admission-error snapshot also excludes the field. This does not promise protection from malicious handlers/providers echoing text or administrator memory inspection.

## Changed paths

- apps/beamlet_actions/lib/beamlet/actions.ex — dedicated strict JSON credential validator.
- apps/beamlet_actions/lib/beamlet/actions/operation.ex — default field, type and separate validation, unchanged full envelope limit.
- apps/beamlet_actions/lib/beamlet/actions/contracts.ex — document handler context.
- apps/beamlet_actions/test/beamlet/actions_test.exs — four credential/data/boundary tests, ordinary output policy assertions.
- apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex — forward credentials into Worker MFA.
- apps/beamlet_runtime/lib/beamlet/runtime/worker.ex — expose unchanged credentials in local context.
- apps/beamlet_runtime/test/beamlet/runtime_test.exs — local forwarding and output absence.
- apps/beamlet_runtime/test/beamlet/review_test.exs — exact deployment boundary at public and direct gateway admission.
- apps/beamlet_runtime/test/beamlet/distributed_test.exs — actual named remote forwarding/output absence and independent remote gateway deployment boundary.
- apps/beamlet_runtime/test/support/fixture.ex — test-only observing handler and peer-local cap setter (no remote test-module closure dependency).
- .trellis/tasks/10-17-agent-model-credentials/operation-handoff.md — this handoff.

## Final executed verification

All Mix/Elixir commands use `ERL_FLAGS='+S 2:2'`. Final commands and logs:

| Directory | Exact command (after ERL_FLAGS) | Result | Log |
| --- | --- | --- | --- |
| root | `mix format 'apps/beamlet_{actions,runtime}/{lib,test}/**/*.{ex,exs}'` | passed | /tmp/operation-format.log |
| root | `mix format --check-formatted 'apps/beamlet_{actions,runtime}/{lib,test}/**/*.{ex,exs}'` | passed | /tmp/operation-format-check.log |
| apps/beamlet_actions | `mix compile --warnings-as-errors` | passed | /tmp/operation-actions-compile.log |
| apps/beamlet_actions | `mix test --seed 631927` | 9 passed | /tmp/operation-actions-tests.log |
| apps/beamlet_runtime | `mix compile --warnings-as-errors` | passed | /tmp/operation-runtime-compile.log |
| apps/beamlet_runtime | `mix test --seed 631927` | 30 passed,6 distributed excluded | /tmp/operation-runtime-tests.log |
| apps/beamlet_runtime | `elixir --sname operation_credentials_tests --cookie operation_credentials_isolated_631927 -S mix test --only distributed --seed 631927` | 6 passed,30 ordinary excluded | /tmp/operation-runtime-distributed.log |
| root | `git diff --check` | passed | /tmp/operation-diff-check.log |
| root | `git diff --cached --name-only` | empty; no staged files | tool output |

45 actual final test executions:9 Actions,30 ordinary Runtime,6 actual distributed Runtime. Named peer VMs use independent stdio control, isolated synthetic cookie and +S2:2; same-host evidence only. Runtime ordinary log includes expected NodeEndpoint gateway_lost from deliberate kill regression.

Existing guarded/default remote-owner behavior, actual owner DOWN before suspended infrastructure resumes, pool charging/release, cancellation/progress, discovery/capacity barriers, partition cleanup/no replay and single-attempt admission regressions all executed unchanged. No placement or lifecycle implementation was edited.

Development iterations: initial root `mix compile --warnings-as-errors` accidentally selected umbrella and failed on expected unmigrated Agent references to removed OpenAI validate_request/1 and old assistant-shaped reply assumptions; no umbrella test suite was run. Failure is recorded in tool transcript (the compile log filename was subsequently reused for owning-app final success). Isolated owning-app commands above pass. First distributed run executed6 tests with2 fixture failures: remote closure defined in ExUnit module unavailable on peer, and overly broad textual absence assertion matched the test VM name. Fixed through peer support helper and explicit credential-key/secret absence assertions; final6/6 pass. Earlier successful owning-app gates were rerun after final relevant edits. No tests/limits were weakened or compatibility fallback added.

## Remaining work and risks

No unresolved Operation contract contradiction. Agent/Node and integration owners must consume this dedicated field, migrate legacy Harness contracts, attach credentials only to model Operations, preserve empty Tool credentials and complete full binding/registration/output/child-isolation acceptance. Spec/deployment migration, independent review, umbrella gates, release/Web, Credo/Dialyzer and any LSP checks remain with main/integration lanes; none claimed here. Harness checks were not rerun. Matching-build rollout remains necessary; no mixed-version support. Ordinary transient plaintext process/message copies remain per approved design; no secure-erasure, persistence or physical/live-provider claim.
