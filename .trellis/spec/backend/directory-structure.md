# Directory Structure

## Implemented Boundaries

Root `mix.exs` sets `apps_path: "apps"`. There is no root `lib/`, `test/`, or
`priv/`; application code and tests live under each child app (for example,
`apps/beamlet_web/`). All nine child manifests share root build, dependency,
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
| `beamlet_i18n` | Shared Gettext backend `Beamlet.I18n`, `Beamlet.I18n.Locale` canonicalisation/default, `Beamlet.I18n.Vocabulary` and the `Beamlet.I18n.Catalogue` declaration of shared msgids; `priv/gettext` shared catalogue |
| `beamlet_web` | Phoenix endpoint, router, page/error renderers, components, telemetry; opt-in Host/Bootstrap, immutable Presets, Agents adapter and ephemeral Handles; `Beamlet.Web.Locale` request/LiveView locale resolution |

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
Node has no dependency on either host. Web directly declares Node/Agent/Actions/Harness and test-only Runtime, plus OTP crypto; its adapters have no CLI/daemon dependency. See [Web Host and Presets](./web-host.md).
Web and CLI additionally declare `{:beamlet_i18n, in_umbrella: true}` and CLI
declares `{:gettext, "~> 1.0"}` (Web already had it); both are shared presentational
libraries. Gettext 1.0.2 and Expo were already resolved in the root `mix.lock`, so
these declarations add no new resolution. `beamlet_i18n` is a leaf: it depends only
on Gettext, no core app depends on it, and the daemon's closure must stay free of
`beamlet_i18n`/`gettext`/`expo` (the CLI closure legitimately gains them).
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

## OTP Ownership

An embedding supervisor explicitly starts `{Beamlet.Node, options}` (one per VM).
Dependency startup does not compose roles or read host configuration. CLI defaults to an empty tree; enabled startup starts fixed interaction. Daemon defaults to an empty `:one_for_one` tree;
validated enabled=true explicitly starts Node and a temporary bootstrap task.
Node starts before the task; network work does not block Supervisor.init. Web uses `:one_for_one` and returns the supervisor result directly. Its actual children, in
`apps/beamlet_web/lib/beamlet_web/application.ex`, are:

```elixir
children = [
  {Beamlet.Web.Host, Application.get_env(:beamlet_web, :host, [])},
  Beamlet.Web.Telemetry,
  {Phoenix.PubSub, name: Beamlet.Web.PubSub},
  Endpoint
]
```

`Endpoint` is an alias for `Beamlet.Web.Endpoint`; `config_change/3` forwards
changes there. Telemetry owns a poller supervisor
(`apps/beamlet_web/lib/beamlet_web/telemetry.ex`). Host defaults to an empty tree; explicitly enabled it owns Node, Presets, Handles and temporary Bootstrap in rest_for_one order. Navigation loss cannot restart Node; Node loss clears navigation. These are the current product
process boundaries. Runtime separately exposes opt-in SharedSupervisor and
ExecutionSupervisor trees; see [Operation Runtime](./operation-runtime.md). Node
composes them by declared roles, starts executor Provider first, and adds the
coupled authority Registry/Resources/Delegations/Agents tree only for authority.

## Phoenix Placement and Request Flow

- `apps/beamlet_web/lib/beamlet_web/endpoint.ex`: static serving, `/live` socket,
  development plugs, request IDs/telemetry, parsers, session, then router.
- `apps/beamlet_web/lib/beamlet_web/locale.ex`: `Beamlet.Web.Locale` plug in the
  `:browser` pipeline resolves `?locale=` -> session -> `config :beamlet_web,
  :default_locale`, installs the locale for the request and assigns
  `:locale`/`:locale_options`; WorkbenchLive/ManagementLive use its `on_mount/4`
  and `on_params/3` for the same rule inside the LiveView process.
- `apps/beamlet_web/lib/beamlet_web/router.ex`: browser and API pipelines; LiveView workbench routes `/`, `/agents/new` and `/agents/:handle` use WorkbenchLive; read-only `/admin/nodes`, `/admin/presets` and `/admin/diagnostics` use ManagementLive. The API pipeline has no routes. `/dev/dashboard` is gated by compile-time `:dev_routes`, enabled
  in `config/dev.exs`.
- WorkbenchLive/WorkbenchCommands/OwnedCall under `lib/beamlet_web/live/` own task entry, exact attachment and disposable callers/sinks; ObservationComponents renders escaped current context/activity. See [Web Workbench](./web-workbench.md). ManagementReads/ManagementLive under the same directory expose bounded read-only node/preset/diagnostics views; see [Web Management](./web-management.md).
- `apps/beamlet_web/lib/beamlet_web/controllers/page_controller.ex`: unrouted retained scaffold controller (the `/`
  route now renders WorkbenchLive) still renders `:home`; `controllers/page_html.ex` uses `Beamlet.Web, :html` and
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
- Gettext backends and catalogue ownership (one msgid, one owner):
  `apps/beamlet_i18n/lib/beamlet/i18n.ex` owns the shared status/reason
  vocabulary and locale canonicalisation, with catalogues
  `apps/beamlet_i18n/priv/gettext/{default,errors}.{pot,po}`;
  `apps/beamlet_web/lib/beamlet_web/gettext.ex` owns Web-only copy in
  `apps/beamlet_web/priv/gettext/{default,errors}.{pot,po}`;
  `apps/beamlet_cli/lib/beamlet/cli/gettext.ex` owns CLI-only copy in
  `apps/beamlet_cli/priv/gettext/default.{pot,po}`. Each locale lives under
  `<domain>`'s sibling `en/LC_MESSAGES` and `zh_CN/LC_MESSAGES` directories.
  Shared msgids are declared once in `Beamlet.I18n.Catalogue` and looked up at
  runtime through `Beamlet.I18n.gettext/2` / `Beamlet.I18n.dgettext/3`, so no
  surface imports a second backend macro set. The three msgid sets are mutually
  exclusive and a test in `apps/beamlet_i18n/test` enforces it.

Pitfalls: extending a nonexistent root service layer, treating generated stubs as
domain implementations, adding a root-only runtime dependency, or editing built
assets instead of their source. There is no established services/utils hierarchy
beyond the modules above; choose new domain structure through the task design.
