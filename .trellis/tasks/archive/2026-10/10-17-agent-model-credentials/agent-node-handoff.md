# Agent / Node component handoff

Completed on feat/agent-model-credentials against approved task contracts and the Harness/Operation handoffs. Edited only Agent/Node source/tests and this handoff. No staging, commits, dependencies, branch/task-state changes, external providers or paid calls. Sibling component changes preserved.

## Exact consumer APIs

Creation: `Beamlet.Agent.start(authority, id: id, model: binding, tools: routes, catalogue: catalogue)` requires exactly one immutable binding:

```elixir
%{provider: "openai-compatible",
  config: %{"base_url" => "https://example.test/v1", "model" => "model-name"},
  credentials: %{"api_key" => "explicit-user-key"},
  placement: %{claims: %{"native" => 1}, allowed_nodes: [executor_node]}}
```

Only provider/config/credentials/placement are binding fields. Credentials/placement may be omitted, defaulting to empty maps at invocation. Placement accepts only environment/allowed_nodes/claims and is validated with Operation.new. Unsupported creation fields (including models), old model routes, unknown provider IDs, ordinary config secrets, invalid common bounds and selected adapter failures reject as invalid_agent_options. `ModelBinding.valid?/1` uses the authority Registry metadata registry, common Harness validation and the adapter's pure validate_invocation callback. Callback errors, exceptions, throws and exits normalize safely. No Agent->Node dependency or portable ID atomization.

Standalone `{Beamlet.Agent.AuthoritySupervisor, model_providers: registry}` accepts the trusted local map; omitted registry uses `Model.default_providers()` (openai-compatible and deterministic). Registry metadata stores this map for the authority lifetime. Binding configuration/credentials remain private Server state. They are never appended to history or snapshot/progress/final fields. Children require explicit creation options; peers remain independent mailbox data.

Node adds `model_providers: %{"portable-id" => TrustedLoadedModule}` (max32), separately from existing monitored `providers: [pid]`. Both required model callbacks must exist. Tools retain local profiles/routes/allowlist and workspace readiness. Old type:model profiles reject. Executor advertises `model.provider:<id>` for each registered module. Combined Tool/model capabilities are bounded at32; Runtime's owning report/registration validator checks combined report bytes including reduced deployment limits before composition succeeds. Neither startup nor readiness invokes models or reads model key environment variables.

`Caller.operation(binding, string_key_neutral_request[, operation_byte_limit])` constructs kind agent.native with payload exactly `%{"type" => "model", "provider" => id, "config" => config, "request" => request}`, the derived capability, binding placement, and credentials ONLY in Operation.credentials. Existing `Caller.operation(tool_route, tool_arguments[, limit])` retains profile/request payload and empty credentials, with no model config. Both retain full serialized Operation limits; OperationOwner still uses guarded public Runtime.submit unchanged.

Handler registration is `{Beamlet.Agent.Integration.Handler, %{profiles: tool_profiles, model_providers: registry}}`. `Handler.run(payload, context)` resolves only installed registry entries, validates exact request shape through Model.validate_request, common invocation through ModelBinding.validate, and selected adapter validation. It builds `%{config: payload["config"], credentials: context.credentials}` without changing settings. Complete callback exceptions normalize to provider_failure. Tool dispatch rejects nonempty Operation credentials, resolves only type:tool profiles, and receives a native Context containing only progress/cancelled? hooks. Runtime Worker provides context.credentials per the previous handoff.

Server uses Model.validate_request/validate_reply/assistant_message; assistant_message uses Model.canonical_call to build canonical call history. Tool observations use call_id. Server/Handler/generic fixtures contain no OpenAI wire parsers/envelopes. Actual HTTP tests alone retain external wire assertions.

## Changed files

Agent:
- lib/beamlet/agent/authority_supervisor.ex
- lib/beamlet/agent/model_binding.ex (new)
- lib/beamlet/agent/integration/caller.ex
- lib/beamlet/agent/integration/handler.ex
- lib/beamlet/agent/server.ex
- test/beamlet/agent_test.exs

Node:
- lib/beamlet/node.ex
- lib/beamlet/node/provider.ex
- test/beamlet/cli_test.exs
- test/beamlet/concurrent_tools_test.exs
- test/beamlet/distributed_test.exs
- test/beamlet/lifecycle_test.exs
- test/beamlet/node_test.exs
- test/beamlet/release_integration_test.exs
- test/beamlet/review_test.exs
- test/beamlet/model_binding_test.exs (new)
- test/support/fixtures.ex
- test/support/loop_model.ex
- test/support/binding.ex (new)
- test/support/alternate_model.ex (new)

Paths above are relative to their respective apps. This handoff is the sole edited task artifact.

## Verification

All commands use ERL_FLAGS='+S 2:2', synthetic credentials/local fixtures only.

| Working directory | Command after ERL_FLAGS | Result | Log |
| --- | --- | --- | --- |
| root | mix format 'apps/beamlet_{agent,node}/{lib,test}/**/*.{ex,exs}' | passed | /tmp/agent-node-format.log |
| root | mix format --check-formatted 'apps/beamlet_{agent,node}/{lib,test}/**/*.{ex,exs}' | passed | /tmp/agent-node-format-check.log |
| apps/beamlet_agent | mix compile --warnings-as-errors | passed | /tmp/agent-compile.log |
| apps/beamlet_node | mix compile --warnings-as-errors | passed | /tmp/node-compile.log |
| apps/beamlet_agent | mix test --seed 631927 | 4 passed | /tmp/agent-tests-final.log |
| apps/beamlet_node | mix test --seed 631927 | 57 passed,3 distributed excluded | /tmp/agent-node-tests-final.log |
| apps/beamlet_node | elixir --sname agent_node_credentials_tests --cookie agent_node_isolated_631927 -S mix test --only distributed --seed 631927 | 3 passed,57 ordinary excluded | /tmp/agent-node-distributed-final.log |
| root | git diff --check | passed | /tmp/agent-node-diff-check.log |
| root | git diff --cached --name-only | empty | tool output |

64 actual final test executions:4 Agent,57 ordinary Node,3 distributed Node. Parallel owning-app commands briefly waited on the shared Mix build lock; both completed. Existing Registry/gateway deliberate-kill diagnostics and a delegation owner-loss task diagnostic are expected lifecycle-test output. Edited-file Elixir diagnostics reported clean where surfaced; no full LSP coverage claimed.

New alternative adapter has config dialect, nested session/bearer authentication, and an internal tuple response representation converted directly to neutral calls/text without an OpenAI converter. Two Agents share one executor, each observes its own config/key on every step and later turn (three invocations per binding). Tests assert immutable binding state, ordered canonical call IDs, absence of synthetic secrets/config from normal snapshots/progress/history/inbox and Tool arguments/settings/Context, explicit child binding, no implicit child binding, and independent peers. Other tests cover unknown provider/fields, callback exception normalization, missing required callbacks, registry32/combined capability32/reduced report-byte bounds, Handler revalidation and model-only credentials. Existing lifecycle/admission/progress/stop/owner retirement/invalid sibling/reversed Tool completion assertions remain intact.

Actual three-VM real HTTP acceptance supplies explicit creation config/key with no executor RELEASE_FIXTURE_KEY environment value. Fixture asserts Authorization header and absence of the key from JSON body. Model -> executor workspace Tool -> model, same Agent later turn, wrong workspace/no fallback, held HTTP stop and executor loss/no retry all execute. New capacity barriers observe gateway zero tasks then a newer eligible Directory report using a fence taken on the executor clock before sequential model submissions. No business retry added. Test peers explicitly connect to the trusted parent node before observer delivery; observer ownership is asserted locally. Only a node-name string enters test model config; adapter matches existing connected node atoms and sends to a fixed registered test observer. Tool observer PID remains executor-local Tool settings.

## Development failures repaired

Initial migration run had29 ordinary failures: automated fixture extraction accidentally included invalid-registry negative cases in setup, and old no-target fixtures used unknown provider IDs now rejected at creation. Setup registries were repaired; no-target cases now use a known registered adapter plus an unavailable environment, retaining no-fallback/no_target assertions. Final ordinary suite passes.

First named run had2 failures from duplicate model_providers options in the executor fixture. After removing duplicates, model events were absent because converting a textual PID on another VM changed its identity. A global-name experiment lacked synchronization, then node-name observer lookup lacked the parent connection under stdio peers. Final implementation explicitly connects peers to the trusted parent and asserts ownership of the fixed registered observer. No PID/process encoding remains in model config, no atomization, no retries or relaxed assertions. The intermediate encoded-PID experiment was removed. Standalone interaction authority setup explicitly installs its test registry.

Early logs were reused before the parent's preserve-failure-log steering arrived; original failure excerpts remain in the session tool transcript, but separate complete raw initial failure logs are unavailable. /tmp/agent-node-distributed-before-observer-refinement.log is an intermediate successful run before the final observer refinement; it must not be described as failure evidence. Final-success logs now use distinct *-final.log paths. No unresolved component failure remains.

## Remaining integration gates / limits

Integration/main lane must migrate current README/deployment examples/scripts and executable specs to these APIs; run full umbrella/release/static/Web gates and independent review. Harness/Actions/Runtime suites were not rerun, per assignment; their owning handoffs remain evidence. No copied release, Credo, Dialyzer, whole-repository LSP, physical-host or live/paid provider result is claimed here. Matching-build rollout remains necessary. Plaintext transient authority/worker/message copies and malicious provider echo remain outside generated-projection absence guarantees. No product-scope contradiction or sibling-seam blocker found.
