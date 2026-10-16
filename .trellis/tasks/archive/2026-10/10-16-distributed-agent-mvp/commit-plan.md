# Phase 3.4 Split Commit Plan

The user approved this concrete five-commit replacement batch with "行".
Preserve base HEAD ecd61e6 (user SBOM); no amend or push. Execution verifies each
batch against the exact path list below before committing.

The five commits below assign all 119 delivery paths exactly once, in dependency
order. Each implementation commit includes its owning tests, topic contract and
child evidence. Shared overviews and final parent acceptance follow implementation.
Whole files are assigned to one commit; no partial staging or source rewriting is
needed. These are cumulative commits, with commits 3 and 4 consuming earlier seams.

## 1. runtime: implement distributed operation contracts and execution

Actions contracts and the opt-in distributed Runtime, including public guarded admission, bounded events, cancellation, lifecycle and capacity synchronization regressions.

Exact paths (27):

- `.trellis/spec/backend/operation-runtime.md`
- `.trellis/tasks/10-16-operation-runtime/check-report.md`
- `.trellis/tasks/10-16-operation-runtime/design.md`
- `.trellis/tasks/10-16-operation-runtime/handoff.md`
- `.trellis/tasks/10-16-operation-runtime/implement.md`
- `.trellis/tasks/10-16-operation-runtime/prd.md`
- `.trellis/tasks/10-16-operation-runtime/task.json`
- `.trellis/tasks/10-16-operation-runtime/verification.md`
- `apps/beamlet_actions/lib/beamlet/actions.ex`
- `apps/beamlet_actions/lib/beamlet/actions/contracts.ex`
- `apps/beamlet_actions/lib/beamlet/actions/operation.ex`
- `apps/beamlet_actions/test/beamlet/actions_test.exs`
- `apps/beamlet_runtime/lib/beamlet/runtime.ex`
- `apps/beamlet_runtime/lib/beamlet/runtime/directory.ex`
- `apps/beamlet_runtime/lib/beamlet/runtime/execution_supervisor.ex`
- `apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex`
- `apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex`
- `apps/beamlet_runtime/lib/beamlet/runtime/report.ex`
- `apps/beamlet_runtime/lib/beamlet/runtime/shared_supervisor.ex`
- `apps/beamlet_runtime/lib/beamlet/runtime/worker.ex`
- `apps/beamlet_runtime/mix.exs`
- `apps/beamlet_runtime/test/beamlet/composition_test.exs`
- `apps/beamlet_runtime/test/beamlet/distributed_test.exs`
- `apps/beamlet_runtime/test/beamlet/review_test.exs`
- `apps/beamlet_runtime/test/beamlet/runtime_test.exs`
- `apps/beamlet_runtime/test/support/fixture.ex`
- `apps/beamlet_runtime/test/test_helper.exs`

## 2. harness: add native model and read-only workspace providers

Native model/Tool contracts, catalogue and history validation, OpenAI-compatible transport, trusted workspace reads, real TCP/TLS tests and the corresponding dependency lock additions.

Exact paths (21):

- `.trellis/spec/backend/harness-providers.md`
- `.trellis/tasks/10-16-harness-providers/check-report.md`
- `.trellis/tasks/10-16-harness-providers/design.md`
- `.trellis/tasks/10-16-harness-providers/handoff.md`
- `.trellis/tasks/10-16-harness-providers/implement.md`
- `.trellis/tasks/10-16-harness-providers/prd.md`
- `.trellis/tasks/10-16-harness-providers/task.json`
- `.trellis/tasks/10-16-harness-providers/verification.md`
- `apps/beamlet_harness/lib/beamlet/harness.ex`
- `apps/beamlet_harness/lib/beamlet/harness/arguments.ex`
- `apps/beamlet_harness/lib/beamlet/harness/catalogue.ex`
- `apps/beamlet_harness/lib/beamlet/harness/context.ex`
- `apps/beamlet_harness/lib/beamlet/harness/models/deterministic.ex`
- `apps/beamlet_harness/lib/beamlet/harness/models/open_ai_compatible.ex`
- `apps/beamlet_harness/lib/beamlet/harness/tools/deterministic.ex`
- `apps/beamlet_harness/lib/beamlet/harness/tools/workspace_read.ex`
- `apps/beamlet_harness/mix.exs`
- `apps/beamlet_harness/test/beamlet/harness_test.exs`
- `apps/beamlet_harness/test/beamlet/http_test.exs`
- `apps/beamlet_harness/test/beamlet/workspace_test.exs`
- `mix.lock`

## 3. agent: add orchestration and node role composition

Explicit authority, asynchronous model/parallel Tool orchestration, bounded subscriptions, delegation/peers, lifecycle ownership and all Node role subsets with their integration regressions.

Exact paths (36):

- `.trellis/spec/backend/agent-orchestration.md`
- `.trellis/tasks/10-16-agent-orchestration/check-report.md`
- `.trellis/tasks/10-16-agent-orchestration/check.jsonl`
- `.trellis/tasks/10-16-agent-orchestration/design.md`
- `.trellis/tasks/10-16-agent-orchestration/handoff.md`
- `.trellis/tasks/10-16-agent-orchestration/implement.jsonl`
- `.trellis/tasks/10-16-agent-orchestration/implement.md`
- `.trellis/tasks/10-16-agent-orchestration/prd.md`
- `.trellis/tasks/10-16-agent-orchestration/task.json`
- `.trellis/tasks/10-16-agent-orchestration/verification.md`
- `apps/beamlet_agent/lib/beamlet/agent.ex`
- `apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex`
- `apps/beamlet_agent/lib/beamlet/agent/delegation.ex`
- `apps/beamlet_agent/lib/beamlet/agent/integration/caller.ex`
- `apps/beamlet_agent/lib/beamlet/agent/integration/handler.ex`
- `apps/beamlet_agent/lib/beamlet/agent/lifecycle.ex`
- `apps/beamlet_agent/lib/beamlet/agent/operation_owner.ex`
- `apps/beamlet_agent/lib/beamlet/agent/ref.ex`
- `apps/beamlet_agent/lib/beamlet/agent/resources.ex`
- `apps/beamlet_agent/lib/beamlet/agent/server.ex`
- `apps/beamlet_agent/mix.exs`
- `apps/beamlet_agent/test/beamlet/agent_test.exs`
- `apps/beamlet_node/lib/beamlet/node.ex`
- `apps/beamlet_node/lib/beamlet/node/application.ex`
- `apps/beamlet_node/lib/beamlet/node/provider.ex`
- `apps/beamlet_node/lib/beamlet/node/routes.ex`
- `apps/beamlet_node/lib/beamlet/node/runtime.ex`
- `apps/beamlet_node/mix.exs`
- `apps/beamlet_node/test/beamlet/concurrent_tools_test.exs`
- `apps/beamlet_node/test/beamlet/distributed_test.exs`
- `apps/beamlet_node/test/beamlet/lifecycle_test.exs`
- `apps/beamlet_node/test/beamlet/node_test.exs`
- `apps/beamlet_node/test/beamlet/review_test.exs`
- `apps/beamlet_node/test/support/fixtures.ex`
- `apps/beamlet_node/test/support/loop_model.ex`
- `apps/beamlet_node/test/test_helper.exs`

## 4. node: add CLI and isolated backend release

Thin CLI, isolated production packaging/runtime configuration, copied named-release control, deployment examples and real HTTP independent-VM acceptance. Root mix.exs belongs here because its complete diff selects/builds the backend release; mix.lock belongs to commit 2.

Exact paths (25):

- `.trellis/spec/backend/backend-release.md`
- `.trellis/tasks/10-16-backend-release/aggregate-runtime-repair.md`
- `.trellis/tasks/10-16-backend-release/check-report.md`
- `.trellis/tasks/10-16-backend-release/check.jsonl`
- `.trellis/tasks/10-16-backend-release/design.md`
- `.trellis/tasks/10-16-backend-release/handoff.md`
- `.trellis/tasks/10-16-backend-release/implement.jsonl`
- `.trellis/tasks/10-16-backend-release/implement.md`
- `.trellis/tasks/10-16-backend-release/physical-acceptance.md`
- `.trellis/tasks/10-16-backend-release/prd.md`
- `.trellis/tasks/10-16-backend-release/task.json`
- `.trellis/tasks/10-16-backend-release/verification.md`
- `README.md`
- `apps/beamlet_node/lib/beamlet/node/cli.ex`
- `apps/beamlet_node/test/beamlet/cli_test.exs`
- `apps/beamlet_node/test/beamlet/release_integration_test.exs`
- `config/backend_runtime.exs`
- `mix.exs`
- `rel/env.sh.eex`
- `scripts/deployment/README.md`
- `scripts/deployment/check-local.sh`
- `scripts/deployment/check-named-release.py`
- `scripts/deployment/check-release.sh`
- `scripts/deployment/http-fixture.py`
- `scripts/deployment/node.example.exs`

## 5. docs: record backend contracts and revised MVP acceptance

Shared backend guidance, parent planning/integration acceptance and this split plan. Records the user's physical-host acceptance removal without claiming physical execution.

Exact paths (10):

- `.trellis/spec/backend/database-guidelines.md`
- `.trellis/spec/backend/directory-structure.md`
- `.trellis/spec/backend/error-handling.md`
- `.trellis/spec/backend/index.md`
- `.trellis/spec/backend/quality-guidelines.md`
- `.trellis/tasks/10-16-distributed-agent-mvp/commit-plan.md`
- `.trellis/tasks/10-16-distributed-agent-mvp/design.md`
- `.trellis/tasks/10-16-distributed-agent-mvp/implement.md`
- `.trellis/tasks/10-16-distributed-agent-mvp/integration-review.md`
- `.trellis/tasks/10-16-distributed-agent-mvp/prd.md`

## Quality evidence and execution checks

Independent final acceptance passed 123 ordinary tests and 7 distributed tests
at each of seeds 719916 and 631927, plus format, warnings-as-errors compile,
strict Credo, existing-PLT Dialyzer, copied named-release closure/RPC/stop and
Web secret/CSP gates. These results describe the final cumulative tree; they do
not claim a fresh test run at every intermediate commit. Source is unchanged
since those gates. Full LSP coverage remains inconclusive; live-provider and
physical-host execution were not performed. The user removed physical-host
acceptance from the required scope.

Before staging, recheck HEAD, the empty index and the exact path inventory.
For each approved batch, stage only its listed paths, verify staged whitespace
and path equality, then commit with the message above. Stop on any unexpected
change or hook failure; do not amend, bypass hooks or push. Check final log and
working-tree status before finish-work. This plan edit needs documentation
whitespace and inventory checks, not a repeated application test run.

## Following work

After all five work commits, use trellis-finish-work to archive this delivery's
four children before the parent, then record the journal with all five work
commit hashes. Archive and journal commits follow the work batch, with no source
commits interleaved. All five tasks belong to this same authorized delivery.

Unrecognized dirty paths: none. Index at planning time: empty.
