# Directory Structure

## Implemented Boundaries

Root `mix.exs` sets `apps_path: "apps"`. There is no root `lib/`, `test/`, or
`priv/`; application code and tests live under each child app (for example,
`apps/beamlet_web/`). All six child manifests share root build, dependency,
lockfile, and configuration paths.

| Application | Implemented source today |
| --- | --- |
| `beamlet_actions` | `Beamlet.Actions` data validation; Operation, Execution, Result, live refs and Handler under `lib/beamlet/actions/` |
| `beamlet_agent` | Explicit-authority facade; Server/Ref/AuthoritySupervisor, lifecycle/Resources, delegation and integration adapters |
| `beamlet_harness` | Native Model/Tool/Context/Environment, catalogue/schema validation, OpenAICompatible and WorkspaceRead under `lib/beamlet/harness/` |
| `beamlet_runtime` | `Beamlet.Runtime` submit/status/cancel/ack facade; opt-in supervision, discovery, admission and lifecycle under `lib/beamlet/runtime/` |
| `beamlet_node` | Validated role composition, Routes/Provider/Runtime; Application starts configured `:boot` roles |
| `beamlet_web` | Phoenix endpoint, router, page/error renderers, components, telemetry |

Runtime declares `{:beamlet_actions, in_umbrella: true}` and OTP `:crypto`.
Harness declares exact Req 0.7.5 and direct Jason; it has no sibling dependencies.
Actions declares no siblings. Agent declares Actions/Runtime/Harness; Node declares
Actions/Runtime/Harness/Agent. Neither core closure includes Phoenix. Actions, Agent,
Harness and Runtime have no Application callback. Node and Web declare callbacks in their own `mix.exs`.
Root dependencies are development/analysis tools, not child runtime dependencies;
root `mix.exs` explicitly documents this distinction. Put app dependencies in the
owning child manifest, not only at the umbrella root.

`architecture.md` defines intended responsibilities and dependency arrows. The
generic Actions/Runtime and native Harness/provider boundaries are implemented;
Agent loops, product Node role composition, CLI and backend release are implemented;
cross-physical-host acceptance was removed by the user; physical execution is untested. See [Backend CLI and Release](./backend-release.md). See [Agent and Node](./agent-orchestration.md). See
[Operation Runtime](./operation-runtime.md) and [Native Harness](./harness-providers.md)
for actual APIs. Do not infer other callable APIs from the architecture.

## OTP Ownership

`apps/beamlet_node/lib/beamlet/node/application.ex` calls
`Supervisor.start_link/2` with configured `:beamlet_node, :boot` children (empty by default) and the name
`Beamlet.Node.Supervisor`. Web uses the same `:one_for_one` strategy and returns
the supervisor result directly. Its actual children, in
`apps/beamlet_web/lib/beamlet_web/application.ex`, are:

```elixir
children = [
  Beamlet.Web.Telemetry,
  {Phoenix.PubSub, name: Beamlet.Web.PubSub},
  Endpoint
]
```

`Endpoint` is an alias for `Beamlet.Web.Endpoint`; `config_change/3` forwards
changes there. Telemetry owns a poller supervisor
(`apps/beamlet_web/lib/beamlet_web/telemetry.ex`). These are the current product
process boundaries. Runtime separately exposes opt-in SharedSupervisor and
ExecutionSupervisor trees; see [Operation Runtime](./operation-runtime.md). Node
composes them by declared roles, starts executor Provider first, and adds the
coupled authority Registry/Resources/Delegations/Agents tree only for authority.

## Phoenix Placement and Request Flow

- `apps/beamlet_web/lib/beamlet_web/endpoint.ex`: static serving, `/live` socket,
  development plugs, request IDs/telemetry, parsers, session, then router.
- `apps/beamlet_web/lib/beamlet_web/router.ex`: browser and API pipelines; only
  product route is browser `GET /` → `PageController.home/2`. The API pipeline
  has no routes. `/dev/dashboard` is gated by compile-time `:dev_routes`, enabled
  in `config/dev.exs`.
- `apps/beamlet_web/lib/beamlet_web/controllers/page_controller.ex`: renders
  `:home`; `controllers/page_html.ex` uses `Beamlet.Web, :html` and
  `embed_templates "page_html/*"` for adjacent HEEx files.
- `apps/beamlet_web/lib/beamlet_web/components/layouts.ex` similarly embeds
  `layouts/*`; reusable HEEx components live in `components/core_components.ex`.
- `apps/beamlet_web/lib/beamlet_web.ex` supplies `use Beamlet.Web, :controller`,
  `:html`, and verified routes (`~p`). Its module documentation requires quoted
  setup to stay focused on imports/uses/aliases; put additional functions in
  modules that are imported there, not inside those quoted expressions.

Preserve the local namespace: web modules are `Beamlet.Web.*`, although their
folder is `lib/beamlet_web/`. Non-web examples use `Beamlet.Agent` and
`Beamlet.Node.Application` under `lib/beamlet/`. Tests mirror those directories:
`apps/beamlet_agent/test/beamlet/agent_test.exs` and
`apps/beamlet_web/test/beamlet_web/controllers/page_controller_test.exs`.
Web test-only helpers live in `apps/beamlet_web/test/support/`; the web manifest
adds that directory to `elixirc_paths(:test)`.

## Configuration and Resources

- Shared `config/config.exs` imports environment config last. Endpoint runtime
  secrets belong to `config/runtime.exs`; development and test settings live in
  `config/dev.exs` and `config/test.exs`.
- Backend build uses `BEAMLET_BACKEND_BUILD=1`, isolated `_build/backend`,
  `config/backend_runtime.exs` and trusted absolute `BEAMLET_CONFIG`. Deployment
  assets/checks live in `rel/` and `scripts/deployment/`.
- Web source assets are in `apps/beamlet_web/assets/`; esbuild/Tailwind output
  targets `apps/beamlet_web/priv/static/assets/` (`config/config.exs`). Static
  source resources also include `priv/static/images/logo.svg` and `robots.txt`.
- Gettext backend: `apps/beamlet_web/lib/beamlet_web/gettext.ex`; catalogues:
  `apps/beamlet_web/priv/gettext/errors.pot` and
  `apps/beamlet_web/priv/gettext/en/LC_MESSAGES/errors.po`.

Pitfalls: extending a nonexistent root service layer, treating generated stubs as
domain implementations, adding a root-only runtime dependency, or editing built
assets instead of their source. There is no established services/utils hierarchy
beyond the modules above; choose new domain structure through the task design.
