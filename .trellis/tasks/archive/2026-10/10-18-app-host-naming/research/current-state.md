# Current state and migration inventory

Baseline: dev at `13824da`; latest runtime implementation is `6041b20`.
Research is read-only; no product implementation has started.

## Confirmed code contracts

- Root `mix.exs`: Release entries currently `beamlet_daemon`, `beamlet_web`, `beamlet_cli`; no default_release. Backend-only app list includes daemon and excludes Web; Sobelow alias embeds the Web directory.
- `config/runtime.exs`: switches on native RELEASE_NAME to enable each host; excludes daemon/CLI from Web secret configuration. All releases use Mix's default bundled runtime.exs. The former `config/daemon_runtime.exs` and BEAMLET_CONFIG startup contract are obsolete.
- `apps/beamlet_node/mix.exs` and `lib/beamlet/node.ex`: no Application callback; explicit supervised role composition. Preserve this seam.
- `apps/beamlet_daemon/mix.exs`, `lib/beamlet/daemon.ex`, `lib/beamlet/daemon/application.ex`, `lib/beamlet/daemon/bootstrap.ex`: host identity, configuration validation, optional Node/storage composition and temporary peer startup task.
- `apps/beamlet_web/mix.exs`: app identity is :beamlet_web, callback remains Beamlet.Web.Application. Asset aliases currently use the beamlet_web esbuild/tailwind profile name (a tool profile, distinct from the OTP app identity).
- `apps/beamlet_web/lib/beamlet_web/endpoint.ex`: Phoenix otp_app and Plug.Static `from` need migration; browser cookie `_beamlet_web_key` and salts are independent identifiers and should remain stable.
- Web router/Gettext/locale/management/workbench source and tests contain application references. Keep Beamlet.Web modules and lib/beamlet_web source organization unless a concrete path dependency requires a change; application directory moves to apps/beamlet_app_web.
- `config/{config,dev,test,prod}.exs`: config namespaces, asset working directories, reload paths and watcher settings need coordinated review. Native RELEASE_NAME remains beamlet_web even after the OTP app is renamed.
- `apps/beamlet_i18n/test/support/catalogue_files.ex`: discovers the Web catalogue by application path. Gettext backend ownership must follow :beamlet_app_web; generated translation files should be regenerated through Mix only when needed.

## Deployment and verification inventory

- `scripts/deployment/check-local.sh`: ordinary/named tests, static checks, backend/server/CLI/Web builds and combined copied artifact gate.
- `check-release.sh`: release/lib closure exclusions, .rel filename, app identities, native eval, Web HTTP and asset checks. It currently contains `Code.ensure_loaded?(Beamlet.Daemon)` isolation assertion.
- `check-named-release.py`, `check-cli-release.py`: native launchers and RPC/config/module strings need migration, including peer fixtures and cleanup paths.
- `durable-e2e.sh`: explicit test path under old daemon directory.
- `scripts/deployment/daemon.example.exs` and README: migrate host example name/config and public Server command names while preserving actual native daemon terminology.
- Current `.trellis/spec/backend/` docs embed old source paths/app/module names. Update current contracts, preserve historical evidence provenance and archived task/journal files.
- Tracked `bom.cdx.json` is a historical snapshot. Per `.trellis/spec/backend/quality-guidelines.md`, the hook generates _build/bom.cdx.json and leaves the tracked snapshot unchanged. Follow that policy; current generated metadata should use new app identities.

## Validation shape

Run all commands from the umbrella root with the repository's Elixir/OTP environment. Use backend-only build root for Server/CLI and full build for Web. Prefer existing meaningful tests and copied artifacts to rename-string-only tests. Verify actual named distributed executed counts (ordinary helpers exclude them).

Expected full checks: format, warning-fatal compile, `mix test --seed 631927`, named `mix test --only distributed --seed 631927` with a fresh node name and private cookie, strict Credo, Sobelow, Gettext extraction drift, Dialyzer, fresh three-release builds/copies, and durable e2e. `check-local.sh` supplies most of this orchestration after its paths/names are updated; avoid repeating a gate that already passed unless code changes warrant it.

Build artifacts into fresh generated destinations: --overwrite can preserve obsolete files. Do not clear unrelated source or work. Copied Release named probes must observe native start/RPC/pid/stop and cleanup. Include an explicit default-release build check and a bounded native Unix daemon smoke check because the naming task makes those entrypoints part of acceptance. Preserve foreground start as the production recommendation.

Primary native release reference: https://mix.hexdocs.pm/Mix.Tasks.Release.html (reviewed earlier in this conversation). It distinguishes Release name from OTP app, supports daemon on Unix via run_erl, and recommends foreground start under service managers/containers. Runtime config is already native in the baseline.

## Confirmed compatibility decision

User explicitly chose removal without compatibility. Remove legacy OTP app identities, Beamlet.Daemon modules and beamlet_daemon Release entry; no aliases, fallbacks or forwarding modules. beamlet_web remains the public Release name, and lib/beamlet_web still represents the preserved Beamlet.Web namespace.
