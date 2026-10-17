# Current seams inspected during planning

Baseline: user-created daemon/CLI skeletons are committed at `0fed1b1`; working tree was clean before task artifact creation. This is source-inspection evidence, not a fresh passing test run.

- `apps/beamlet_node/mix.exs` declares `mod: {Beamlet.Node.Application, []}`; `node/application.ex` reads global `:boot` and starts Node automatically when configured. Library-host split must remove this policy from dependency startup.
- `apps/beamlet_node/lib/beamlet/node.ex` already supplies Supervisor child_spec/start_link and validates all seven nonempty role subsets. Authority and executor add actual infrastructure; interaction-only retains shared Runtime/Routes. Keep the host embedding seam and current capability limits.
- Node and its subordinate trees currently use VM-global registered names. A daemon and CLI auto-starting Node in the same umbrella VM will conflict; opt-in host startup/test isolation needs explicit coverage.
- `apps/beamlet_node/lib/beamlet/node/cli.ex` mixes reusable name validation/connect/control with terminal-specific watch printing. Watch subscribes and acknowledges in one sink, bounds output/events/time and never retries business work.
- `apps/beamlet_node/test/beamlet/cli_test.exs` covers authority allowlisting, malformed watch options, cleanup/event limits, authority loss and live-ref controls. `release_integration_test.exs` also imports the old CLI namespace. Migrate coverage, do not delete it merely because the owner app changes.
- `apps/beamlet_agent/lib/beamlet/agent.ex` exposes explicit-authority creation and live Ref control. Remote creation uses bounded erpc; subsequent control targets Ref.pid with incarnation. No durable lookup exists.
- Root `mix.exs` declares only a beamlet_node release and a five-app backend build selector. Both need host-aware migration while preserving backend-only compile/packaging isolation.
- `config/backend_runtime.exs` requires an absolute trusted BEAMLET_CONFIG. Ordinary prod `config/runtime.exs` unconditionally checks the Web secret; separate release runtime config must preserve Web behavior without requiring it on backend hosts.
- `rel/env.sh.eex` uses long names, shared cookie, fixed service distribution port and ephemeral helper ports. Preserve the named start/RPC/stop fix when adding host-specific entrypoints.
- `scripts/deployment/` owns copied-release closure/named startup checks, local acceptance, example config and runbook. Update their ownership and actual checks for daemon/CLI rather than retaining the old executable as a hidden test dependency.
- Existing deployment evidence explicitly excludes physical-host and paid-provider acceptance; continue to distinguish named local peer automation from those claims.
- The new daemon skeleton has no sibling dependencies; the CLI skeleton already has Owl and ucwidth. Both have empty generated supervision trees.

Relevant specs: backend directory-structure.md, agent-orchestration.md, operation-runtime.md, harness-providers.md, backend-release.md and quality-guidelines.md. No product code has been edited in this planning step.
