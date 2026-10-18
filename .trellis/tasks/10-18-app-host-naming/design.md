# Design: explicit host application names

## Architecture and ownership

This is a coordinated application-identity migration, not a change to role composition. Keep one task because source names, shared configuration, release assembly and all copied checks must agree before the result is usable.

| Concern | Server target | Web target |
| --- | --- | --- |
| App root | apps/beamlet_app_server | apps/beamlet_app_web |
| OTP application | :beamlet_app_server | :beamlet_app_web |
| Module prefix | Beamlet.Server | Beamlet.Web |
| Application callback | Beamlet.Server.Application | Beamlet.Web.Application |
| Native Release | beamlet_server | beamlet_web |
| Config namespace | :beamlet_app_server | :beamlet_app_web |

Server directly composes Node, optional Storage.Host and temporary Bootstrap. Web retains Host, Telemetry, PubSub and Endpoint; enabled Host retains its existing rest_for_one subtree. Node has no Application callback and no dependency on either host. No new abstraction or shared host framework is introduced.

Server source paths move from `lib/beamlet/daemon*` to `lib/beamlet/server*`; its test modules/files use Server names where they represented the old host. Web retains `lib/beamlet_web`, `test/beamlet_web` and Beamlet.Web.* modules under the new application root, matching its namespace convention.

## Configuration and startup flow

Root Mix project declares:

```elixir
default_release: :beamlet_server,
releases: [
  beamlet_server: [applications: [beamlet_app_server: :permanent]],
  beamlet_web: [applications: [beamlet_app_web: :permanent]],
  beamlet_cli: [
    applications: [beamlet_cli: :permanent],
    steps: [:assemble, &cli_entrypoint/1, :tar]
  ]
]
```

Preserve the existing CLI entrypoint step implementation.

1. Mix bundles the shared config/runtime.exs through its default mechanism.
2. RELEASE_NAME `beamlet_server` enables :beamlet_app_server. `beamlet_web` enables :beamlet_app_web Host and Endpoint. `beamlet_cli` retains current behavior.
3. Server/CLI production release paths bypass Web secret requirements; production Web and source-run Web retain the secret check.
4. OTP starts the selected callback, validates host configuration and explicitly composes the existing trees. Ordinary source/dependency loading keeps Node opt-in.

Update Application.get_env/put_env, compile_env, Phoenix otp_app, Plug.Static source, Gettext otp_app, router compile flags, app resource lookups, distribution fixture app lists and test environment save/restore keys together. Rename Server's host-specific error identifiers/messages (for example invalid_daemon_configuration → invalid_server_configuration) and supervisor registrations with its namespace; do not change shared library errors.

Do not confuse identifiers:

- `beamlet_web` stays the Release name; runtime discrimination must not switch it to beamlet_app_web.
- esbuild/tailwind `beamlet_web` profile labels can remain; update their working directories and asset/reload references to the new app root.
- Web cookie `_beamlet_web_key`, salts, public routes, CSS classes and module-oriented `lib/beamlet_web` paths remain stable. These are not compatibility aliases.
- Node names supplied through native RELEASE_NODE and allowlists remain operator choices.

## Release and tooling migration

Update the backend-only apps list to :beamlet_app_server; continue excluding the Web app from that build. Keep Server closure free of CLI/Web/Phoenix and presentation-only i18n/Gettext/Expo; CLI may retain its legitimate i18n closure and must exclude Server/Web. Web must exclude Server/CLI.

Update Sobelow root, config resource paths, deployment commands, `.rel` names, copied artifact paths, release launchers and injected configuration/module strings in the shell/Python checks. Preserve fixture lifecycle, error propagation and multi-service cleanup. Move daemon.example.exs to server.example.exs and update references; it remains an example, not a restored config discovery mechanism.

Use native start/daemon/remote/rpc/pid/stop with no wrapper. Recommend foreground start under systemd/containers. Add a bounded smoke probe of native Unix daemon launch → readiness via RPC/pid → stop → actual exit on a copied Server artifact, with unique node identity/private cookie and cleanup on failure. No heart policy, reconnect service or OS provisioning is introduced.

## Compatibility and migration contract

User explicitly chose immediate removal. There are no old app aliases, config-key fallback, Beamlet.Daemon forwarding modules, old Release entries or old app directories. Do not reject every occurrence of the text `beamlet_web`: determine whether it denotes a removed OTP app or the retained Release/profile/module path.

Migration instructions list app directory, application atom, module prefix, Server executable and example filename mappings. Rebuild fresh artifacts rather than overlaying an old lib directory. Deployment owners must update their config namespaces and service commands. This task does not deploy externally or infer recovery of live Agents.

Update current backend specs and app/deployment docs; keep historical task/journal evidence, historical paths used as evidence anchors and tracked historical SBoM snapshots. Current SBoM generation remains directed to _build/bom.cdx.json by repository policy.

## Validation and risks

- Stale .beam/.app files can hide module deletion. Verify clean generated build destinations and copied release closures, including absence of old identities/modules and rejection of the old Server Release build name.
- Phoenix compiles otp_app and paths; compile plus actual copied HTTP/CSS/JS checks catch incomplete moves that unit tests may miss.
- Gettext ownership follows the app identity even when source subdirectories keep their existing names. Use existing catalogue tests and extraction drift gate; regenerate through Mix when necessary, never hand-edit generated references.
- Distributed helpers exclude named cases by default. Count actual executions on a named VM and keep private cookies out of logs.
- Artifact layout, default Release and namespace changes are intentional breaking changes; storage formats, Agent protocol and browser session parameters remain unchanged.

## Rollout / rollback

Ship the complete new artifacts and matching configuration. Roll back with the prior complete artifact plus its prior configuration/service command. Do not mix identities between releases or overlay old output. No dataset migration is part of this task; native restart does not restore ephemeral Agent state.
