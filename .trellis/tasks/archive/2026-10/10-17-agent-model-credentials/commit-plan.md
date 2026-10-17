# Proposed Work Commits

Status: user approved the exact five work batches and finish-work archive/journal
with "ok" under workflow Phase3.4. Approval recorded before staging or committing.
Branch `feat/agent-model-credentials`, baseline `18137b1` (`flake: update`).
User-owned baseline flake/SBOM, historical archives, dependencies/lock and unrelated
files are excluded. Every current dirty path belongs to this approved task; no
unrecognized paths were found. The following exact paths are allocated once.

These are dependency-ordered contract/migration commits. Full acceptance applies
to the complete stack; intermediate migration commits are not separately claimed
to pass the entire umbrella suite. Source acceptance: `recheck-report.md` READY
(161 ordinary/12 distributed and static/rebuilt release gates). Documentation checks
are recorded in `spec-sync.md`. The initial BLOCKED report remains historical.

## 1. `runtime: carry bounded invocation credentials` (10 paths)

- `apps/beamlet_actions/lib/beamlet/actions.ex`
- `apps/beamlet_actions/lib/beamlet/actions/contracts.ex`
- `apps/beamlet_actions/lib/beamlet/actions/operation.ex`
- `apps/beamlet_actions/test/beamlet/actions_test.exs`
- `apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex`
- `apps/beamlet_runtime/lib/beamlet/runtime/worker.ex`
- `apps/beamlet_runtime/test/beamlet/distributed_test.exs`
- `apps/beamlet_runtime/test/beamlet/review_test.exs`
- `apps/beamlet_runtime/test/beamlet/runtime_test.exs`
- `apps/beamlet_runtime/test/support/fixture.ex`

## 2. `harness: define neutral models and explicit provider invocations` (10 paths)

- `apps/beamlet_harness/lib/beamlet/harness.ex`
- `apps/beamlet_harness/lib/beamlet/harness/arguments.ex`
- `apps/beamlet_harness/lib/beamlet/harness/catalogue.ex`
- `apps/beamlet_harness/lib/beamlet/harness/context.ex`
- `apps/beamlet_harness/lib/beamlet/harness/model.ex`
- `apps/beamlet_harness/lib/beamlet/harness/models/deterministic.ex`
- `apps/beamlet_harness/lib/beamlet/harness/models/open_ai_compatible.ex`
- `apps/beamlet_harness/test/beamlet/harness_test.exs`
- `apps/beamlet_harness/test/beamlet/http_test.exs`
- `apps/beamlet_harness/test/beamlet/model_test.exs`

## 3. `agent: own immutable model bindings and local adapters` (21 paths)

- `apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex`
- `apps/beamlet_agent/lib/beamlet/agent/integration/caller.ex`
- `apps/beamlet_agent/lib/beamlet/agent/integration/handler.ex`
- `apps/beamlet_agent/lib/beamlet/agent/model_binding.ex`
- `apps/beamlet_agent/lib/beamlet/agent/server.ex`
- `apps/beamlet_agent/test/beamlet/agent_test.exs`
- `apps/beamlet_node/lib/beamlet/node.ex`
- `apps/beamlet_node/lib/beamlet/node/provider.ex`
- `apps/beamlet_node/test/beamlet/cli_test.exs`
- `apps/beamlet_node/test/beamlet/concurrent_tools_test.exs`
- `apps/beamlet_node/test/beamlet/delegation_binding_test.exs`
- `apps/beamlet_node/test/beamlet/distributed_test.exs`
- `apps/beamlet_node/test/beamlet/lifecycle_test.exs`
- `apps/beamlet_node/test/beamlet/model_binding_test.exs`
- `apps/beamlet_node/test/beamlet/node_test.exs`
- `apps/beamlet_node/test/beamlet/release_integration_test.exs`
- `apps/beamlet_node/test/beamlet/review_test.exs`
- `apps/beamlet_node/test/support/alternate_model.ex`
- `apps/beamlet_node/test/support/binding.ex`
- `apps/beamlet_node/test/support/fixtures.ex`
- `apps/beamlet_node/test/support/loop_model.ex`

## 4. `node: migrate deployment to explicit Agent model bindings` (6 paths)

- `README.md`
- `scripts/deployment/README.md`
- `scripts/deployment/check-local.sh`
- `scripts/deployment/check-named-release.py`
- `scripts/deployment/check-release.sh`
- `scripts/deployment/node.example.exs`

## 5. `docs: record model provider contracts and acceptance` (31 paths)

- `.trellis/spec/backend/agent-orchestration.md`
- `.trellis/spec/backend/backend-release.md`
- `.trellis/spec/backend/database-guidelines.md`
- `.trellis/spec/backend/directory-structure.md`
- `.trellis/spec/backend/error-handling.md`
- `.trellis/spec/backend/harness-providers.md`
- `.trellis/spec/backend/index.md`
- `.trellis/spec/backend/operation-runtime.md`
- `.trellis/spec/backend/quality-guidelines.md`
- `.trellis/tasks/10-17-agent-model-credentials/agent-node-handoff.md`
- `.trellis/tasks/10-17-agent-model-credentials/check-report.md`
- `.trellis/tasks/10-17-agent-model-credentials/check.jsonl`
- `.trellis/tasks/10-17-agent-model-credentials/commit-plan.md`
- `.trellis/tasks/10-17-agent-model-credentials/design.md`
- `.trellis/tasks/10-17-agent-model-credentials/diagnostics.md`
- `.trellis/tasks/10-17-agent-model-credentials/handoff.md`
- `.trellis/tasks/10-17-agent-model-credentials/harness-handoff.md`
- `.trellis/tasks/10-17-agent-model-credentials/implement.jsonl`
- `.trellis/tasks/10-17-agent-model-credentials/implement.md`
- `.trellis/tasks/10-17-agent-model-credentials/operation-handoff.md`
- `.trellis/tasks/10-17-agent-model-credentials/ownership.md`
- `.trellis/tasks/10-17-agent-model-credentials/prd.md`
- `.trellis/tasks/10-17-agent-model-credentials/recheck-report.md`
- `.trellis/tasks/10-17-agent-model-credentials/repair-actions.md`
- `.trellis/tasks/10-17-agent-model-credentials/repair-delegation.md`
- `.trellis/tasks/10-17-agent-model-credentials/repair-harness.md`
- `.trellis/tasks/10-17-agent-model-credentials/research/credential-flow.md`
- `.trellis/tasks/10-17-agent-model-credentials/research/provider-abstraction.md`
- `.trellis/tasks/10-17-agent-model-credentials/spec-sync.md`
- `.trellis/tasks/10-17-agent-model-credentials/task.json`
- `.trellis/tasks/10-17-agent-model-credentials/verification.md`

## Unrecognized Paths

None.

## After Work Commits

The same one-shot approval includes the prescribed finish-work bookkeeping, after
all five work commits: archive only this current task to
`.trellis/tasks/archive/2026-10/10-17-agent-model-credentials/` (same task files, task
status completed and active pointer cleared) using `task.py archive`, then update
`.trellis/workspace/hobr/journal-1.md` and `.trellis/workspace/hobr/index.md` using
`add_session.py` with work-commit hashes. These create separate
`chore(task): archive 10-17-agent-model-credentials` and `chore: record journal`
commits. No merge, amend, reset or push. Inspect each staged path set before each
work commit; stop on unexpected state. No additional product changes are planned.
