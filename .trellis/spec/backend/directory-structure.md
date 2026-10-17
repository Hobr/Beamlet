# Directory Structure

## Implemented Boundaries

Root `mix.exs` sets `apps_path: "apps"`. There is no root `lib/`, `test/`, or
`priv/`; application code and tests live under each child app (for example,
`apps/beamlet_web/`). All eight child manifests share root build, dependency,
lockfile, and configuration paths.

| Application | Implemented source today |
| --- | --- |
| `beamlet_actions` | `Beamlet.Actions` data validation; Operation, Execution, Result, live refs and Handler under `lib/beamlet/actions/` |
| `beamlet_agent` | Explicit-authority facade; Server/Ref/AuthoritySupervisor, Agent-owned bounded Discovery (local reads/erpc, no query endpoint), lifecycle/Resources, delegation and integration adapters |
| `beamlet_harness` | Native Model/Tool/Context/Environment, catalogue/schema validation, OpenAICompatible and WorkspaceRead under `lib/beamlet/harness/` |
| `beamlet_runtime` | `Beamlet.Runtime` submit/status/cancel/ack facade; opt-in supervision, discovery, admission and lifecycle under `lib/beamlet/runtime/` |
| `beamlet_node` | Explicitly supervised role composition, Routes/Provider/Runtime; shared trusted-name/connect/filter API in `Beamlet.Node.Cluster`, bounded discovery in `Beamlet.Node.Agents`; no Application callback |
| `beamlet_cli` | Opt-in interaction host, terminal Client and bounded Command/Session/Renderer/Runner; foreground release |
| `beamlet_daemon` | Opt-in Application, startup configuration policy and owned one-shot peer bootstrap; authority/executor daemon release |
| `beamlet_web` | Phoenix endpoint, router, page/error renderers, components, telemetry |

Runtime declares `{:beamlet_actions, in_umbrella: true}` and OTP `:crypto`.
Harness declares exact Req 0.7.5 and direct Jason; it has no sibling dependencies.
Actions declares no siblings; dedicated credentials use OTP JSON and generic Runtime
forwarding. Harness.Model owns independent neutral validation/registration; Agent's
ModelBinding separates portable child validation from authority adapter validation.
Agent declares Actions/Runtime/Harness; Node declares
Actions/Runtime/Harness/Agent. Neither core closure includes Phoenix. Actions, Agent,
Harness, Runtime and Node have no Application callback. CLI, daemon and Web declare
callbacks in their own `mix.exs`. CLI directly declares Node/Agent, and test-only
Runtime/Harness/Jason dependencies for its migrated HTTP integration fixture.
Daemon directly declares Node; it calls business APIs only through Node composition.
Node has no dependency on either host.
Root dependencies are development/analysis tools, not child runtime dependencies;
root `mix.exs` explicitly documents this distinction. Put app dependencies in the
owning child manifest, not only at the umbrella root.

`architecture.md` defines intended responsibilities and dependency arrows. The
generic Actions/Runtime and native Harness/provider boundaries are implemented;
Agent loops, product Node role composition and a migrated terminal adapter are implemented;
daemon release/config/scripts now own deployment; CLI standalone release owns foreground stdin;
cross-physical-host acceptance was removed by the user; physical execution is untested. See [Backend CLI and Release](./backend-release.md). See [Agent and Node](./agent-orchestration.md). See
[Operation Runtime](./operation-runtime.md) and [Native Harness](./harness-providers.md)
for actual APIs. Do not infer other callable APIs from the architecture.

## Storage App

`apps/beamlet_storage` is an internal Ecto library owned by stage A of the
[persistence plan](../../../docs/architecture/persistence-delivery.md). It declares
`ecto`, `ecto_sql`, `ecto_sqlite3`, `postgrex` and `jason` directly (no sibling
dependency and no override) and has **no** Application callback: loading it starts
no Repo, creates no database file and runs no migration. Repos are started
explicitly through `Beamlet.Storage.Dataset` by an embedding supervisor or a test.

Layout: `lib/beamlet/storage/*.ex` (Repos, `Dataset`, `Connections`,
`Transaction`, `Codec`/`JSON`, `Migrations`, `Artifacts`, `TerminalArtifacts` and
the record facades `AgentRecords`/`OperationRecords`/`ExecutorJournal`),
`lib/beamlet/storage/schema/` (Ecto schemas), `priv/{authority,journal}_migrations/`,
and `test/beamlet/storage/` plus `test/support/contract_fixture.ex`. The shared
adapter contract suite is `test/beamlet/storage/storage_contract_test.exs`; it needs
an isolated PostgreSQL cluster via `BEAMLET_PG_SOCKET_DIR`/`BEAMLET_PG_PORT` and must
not be reported as passing when that adapter did not run.

## OTP Ownership

An embedding supervisor explicitly starts `{Beamlet.Node, options}` (one per VM).
Dependency startup does not compose roles or read host configuration. CLI defaults to an empty tree; enabled startup starts fixed interaction. Daemon defaults to an empty `:one_for_one` tree;
validated enabled=true explicitly starts Node and a temporary bootstrap task.
Node starts before the task; network work does not block Supervisor.init. Web uses `:one_for_one` and returns the supervisor result directly. Its actual children, in
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
`Beamlet.Node.Cluster` under `lib/beamlet/`. Tests mirror those directories:
`apps/beamlet_agent/test/beamlet/agent_test.exs` and
`apps/beamlet_web/test/beamlet_web/controllers/page_controller_test.exs`.
Web test-only helpers live in `apps/beamlet_web/test/support/`; the web manifest
adds that directory to `elixirc_paths(:test)`.

## Configuration and Resources

- Shared `config/config.exs` imports environment config last. Endpoint runtime
  secrets belong to `config/runtime.exs`; development and test settings live in
  `config/dev.exs` and `config/test.exs`.
- Backend build uses `BEAMLET_BACKEND_BUILD=1`, isolated `_build/backend`,
  `config/daemon_runtime.exs` and trusted absolute `BEAMLET_CONFIG`. Deployment
  assets/checks live in `rel/` and `scripts/deployment/`. A single beamlet_daemon
  artifact supports default authority+executor and both only configurations.
  Node is not a release entrypoint; beamlet_cli uses config/cli_runtime.exs and excludes daemon/Web.
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
