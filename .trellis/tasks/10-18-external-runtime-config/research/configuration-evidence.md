# External configuration: initial evidence

## Status

Planning only. Latest user decision: reuse native runtime.exs / Config.Provider configuration, explicitly without Hush. This supersedes both the original Hush requirement and the intermediate TOML-only decision/all TOML translation/bootstrap recommendations. Preserve the approved single-file FHS/XDG selection order, now with `.exs` names, and startup-load-only scope. See current `prd.md` and `elixir-release-configuration.md`.

## Repository evidence

- `config/daemon_runtime.exs:8`: daemon release currently requires absolute `BEAMLET_CONFIG`, reads trusted executable Elixir using `Config.Reader.read!`, accepts only `:beamlet_daemon`, validates with `Beamlet.Daemon.configuration/1`, then enables it. Failures have a static credential-safe message.
- `apps/beamlet_daemon/lib/beamlet/daemon.ex:20`: supported host keys are enabled/node/allowed_nodes/peers/storage. Node settings include module-valued provider registries, resource profiles and nested options; optional storage is delegated to `Beamlet.Storage.Host`.
- `scripts/deployment/daemon.example.exs:1`: an existing directly editable external Config script with role selection, model-provider modules, routes and optional executor profiles.
- `config/runtime.exs:3`: ordinary production web startup currently reads `SECRET_KEY_BASE`; it has no external file discovery. Endpoint binds IPv6 wildcard by current production default.
- `config/config.exs:23` and `config/prod.exs:8`: endpoint defaults span runtime-capable values and compile-time settings. `force_ssl` is explicitly compile-time; do not promise arbitrary build configuration is runtime-editable.
- `apps/beamlet_web/lib/beamlet_web/host.ex:9`: opt-in web host accepts enabled/node/allowed_nodes/peers/catalogue and validates Node and presets. Native configuration includes nested maps and module identities.
- `mix.exs:17`: explicit daemon and CLI releases exist; there is no explicit web release entry. Daemon uses a dedicated runtime config; backend-only builds exclude web.
- `rel/env.sh.eex:3`: shared release environment currently requires RELEASE_NODE, RELEASE_COOKIE and BEAMLET_CONFIG and manages fixed service vs ephemeral control distribution ports. A new web release must not accidentally inherit daemon/CLI assumptions. CLI remains outside requested feature scope and must keep working.

## Hush primary-source findings

Source: https://github.com/gordalina/hush (inspected fetched repository README, mix.exs, lib/hush.ex, lib/hush/config_provider.ex, lib/hush/provider/file_system.ex).

- Inspected upstream declares version 1.3.0 and Elixir ~> 1.12.
- Hush resolves `{:hush, Provider, key, options}` placeholders, supports SystemEnvironment/FileSystem, transformers and custom providers.
- It is not a TOML/YAML/JSON configuration parser and does not define FHS/XDG discovery or command-line flags.
- FileSystem retrieves whole file contents under configured search paths; parsing a document remains separate work.
- Hush.ConfigProvider delegates release configuration to Hush.resolve!. Runtime resolution is also supported.
- `Hush.resolve!/2` writes application environment while resolving. Integration must account for validation/order/early-start timing rather than assume it is a pure transformation.
- Native `.exs` Config preserves existing rich settings and executable trusted operator behavior. Declarative TOML would require a parser plus explicit schema/adapter identity mapping; it is not merely a filename change.

## Filesystem standards (primary sources)

- XDG Base Directory Specification v0.8: https://specifications.freedesktop.org/basedir/latest/
  - XDG_CONFIG_HOME defaults to `$HOME/.config` when empty/unset.
  - XDG_CONFIG_DIRS defaults to `/etc/xdg`; ordered colon-separated directories.
  - Relative XDG paths are invalid and ignored.
  - User config precedes directory-list config. Applications must specify first-file vs merge behavior themselves.
  - Configuration is distinct from persistent data/state/cache/runtime files.
- FHS 3.0 /etc: https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s07.html
  - `/etc` holds host-specific configuration; app subdirectories are recommended.
  - `/etc/opt/<subdir>` applies to packages installed under corresponding `/opt/<subdir>`.
  - These conventions do not require a particular text serialization.

## Decisions still needed

- Startup-only loading and single-file discovery/explicit-path failure policy have been approved.
- The user accepted the preceding proposal while clarifying shared umbrella configuration. Required-file packaged startup and native integration/VM environment compatibility are included explicitly in the final planning review.
- Web/daemon/CLI already share root config/config.exs via child manifest config_path. Dev/test/prod are umbrella environment files, not Phoenix-owned or per-Release files; no duplicated daemon environment tree is needed.

Recommendations must be reviewed with the user before implementation. No sandboxing claim for native Config files.
