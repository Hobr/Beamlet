# Configuration for packaged Elixir deployments

## Current User Decision and History

Latest decision: reuse native `runtime.exs` / `Config.Provider` configuration at the current stage, explicitly without Hush (user approved removal). The external format is no longer TOML-only; trusted operator `.exs` is acceptable. The intermediate TOML-only decision, TOML mapping recommendations and contemplated pre-VM TOML bootstrap below are superseded historical analysis, not implementation instructions.

Still valid: packaged deployments without target-side project source/Mix; external editable configuration; FHS/XDG single-file discovery and CLI selection; startup-only loading without online editing/persistence/hot reload. Current requirements are authoritative in `../prd.md`.

## Primary-source findings

1. **A Mix release is already compiled, self-contained distribution, not source deployment.** By default it includes the Erlang VM/runtime and does not require installed Erlang/Elixir or source on the target. It is ordinarily a directory/archive with launcher scripts, not a single native executable. Native/system dependency and platform compatibility requirements still apply.
   - Source: https://hexdocs.pm/mix/Mix.Tasks.Release.html, sections Why releases? and Deployments.
2. **The official built-in configuration approach distinguishes build-time config from runtime config.** `config/runtime.exs` can read environment variables/external configuration after compilation. A bundled developer-owned runtime script does not imply operators require Mix or application source.
   - Source: https://hexdocs.pm/elixir/config-and-distribution.html, Compile vs runtime configuration.
3. **External declarative configuration is a supported release extension, not an anti-pattern.** `Config.Provider` runs early during boot and can read JSON/TOML and return merged application configuration. The official example reads JSON; an external `.exs` file is not required by the interface. Needed dependency startup in a provider is explicit.
   - Source: https://hexdocs.pm/elixir/Config.Provider.html, Custom config provider and load/2.
4. **TOML release support already exists in the ecosystem.** `toml` v0.7.0 documents `Toml.Provider` for both Elixir releases and Distillery. It reads the configured file at boot and fails boot when missing/unreadable. Its generic mapping uses application-name top-level tables and atom-key defaults; the product should not blindly expose arbitrary application/module settings through this provider.
   - Source: https://hexdocs.pm/toml/Toml.Provider.html.
5. **Configuration providers do not imply live reload.** The provider API is a boot-time mechanism. Updating application environment alone is not a general reconfiguration protocol for running listeners, supervisors, pools or storage.
   - Source: https://hexdocs.pm/elixir/Config.Provider.html, provider boot/load lifecycle; product consequence inferred from existing startup-owned host configuration.

Toolchain clarification after inspecting backend manifests/specs: backend hosts require Elixir ~> 1.20 and the installed toolchain is 1.20.4; only the Web manifest retains ~> 1.17. Use the actual umbrella/backend toolchain, not Web's lower bound. No toolchain upgrade is proposed.

## Historical TOML Architecture Proposal (Superseded — Do Not Implement)

- Operator interface: TOML documents only; no external executable `.exs` fallback for these hosts.
- Compiled shared loader: explicit CLI/environment path selection and FHS/XDG discovery, TOML parsing to string keys, product schema validation, Hush secret/reference resolution, existing host validation, and final boot configuration.
- Keep Hush responsible for environment/file-backed value references; it is not the TOML parser or the path-discovery implementation. Encode references as declarative TOML tables, not Elixir tuples or eval strings.
- Module-valued trusted providers/tools become shipped identifier-to-module registries. TOML must not load arbitrary modules or create atoms from arbitrary operator strings. Exact identifiers and supported settings still need schema design.
- Apply values before starting endpoints, Node trees and repositories. Preserve startup opt-in and storage-no-migration contracts.
- Internal build/runtime glue may remain developer-owned Elixir source, or be a compiled Config.Provider; the operator-facing contract is what must be TOML-only.
- Proposed v1 behavior is restart-required changes; live reload would need a separately scoped reconfiguration design.

## Follow-up: programmatic persistence

- `Config.Reader` documents evaluation/read/merge APIs, not a round-trip editor or writer: https://hexdocs.pm/elixir/Config.Reader.html. `Config.config/2,3` defines configuration during evaluation; it does not rewrite the source script: https://hexdocs.pm/elixir/Config.html.
- A program can write generated `.exs` text, but evaluation results do not preserve a reversible relationship to original expressions, comments, imports, repeated declarations or environment-dependent values. Safely patching arbitrary operator scripts is a source-rewriting problem, not native configuration persistence support.
- Declarative TOML makes semantic read/modify/write practical. Parser support does not imply an encoder or comment-preserving round-trip editing; dependencies must be checked if persistence is in scope.
- Any writer needs a defined writable target, validation, same-directory temporary-file replacement, permissions, and a concurrency/conflict policy. Atomic replacement avoids partially written files but alone does not prevent stale concurrent updates or guarantee power-loss durability.
- Preserve secret references in the stored document; do not persist Hush-resolved secrets as a flattened effective configuration. Account for environment overrides so that persisted values are not misleadingly presented as currently effective.
- `/etc` configuration may be intentionally read-only to the service account. Online administration does not imply granting the daemon write access to all system configuration; writable-target/override policy needs an explicit decision.
- Persistence and live runtime application are separate features. The user's example raises possible scope; it is not yet approval to implement a web settings page, configuration writer, or hot reload.

## Follow-up: putting distribution startup settings in TOML

### Inspected evidence

- `rel/env.sh.eex:3-16` currently requires RELEASE_NODE/RELEASE_COOKIE/BEAMLET_CONFIG and assigns a fixed BEAMLET_DIST_PORT for service startup, but port 0 for rpc/remote/restart/stop/pid helper VMs.
- Inspected the existing generated artifact `_build/backend/prod/rel/beamlet_daemon/bin/beamlet_daemon` (local build evidence, not tracked source). It sources env.sh before evaluating command branches; `start` uses `--cookie`, distribution name, vm.args and runtime sys config; rpc/remote use distinct helper node names and remote.vm.args. `eval` uses start_clean without distribution. This demonstrates that only changing an application Config.Provider cannot set all pre-launch parameters.
- The artifact passes cookie through command-line arguments. Do not claim that a new TOML reader alone prevents process-list/privileged inspection of the cookie; avoid logging, tracing, generated shell-code evaluation and unnecessary plaintext artifacts.

### Feasibility and bounded scope

Assessment: feasible, moderate additional complexity, not a redesign of business/runtime libraries. Most added work is bootstrap order, control-command regression and secret handling rather than TOML decoding.

A possible approach is a release-packaged bootstrap stage using the bundled runtime and compiled loader to read/validate just the startup section, followed by the real service/control VM. This avoids requiring system Python/Elixir/Mix or implementing a TOML parser in shell. It adds a short-lived VM invocation and must avoid recursive wrapper/env.sh execution. It is a candidate, not an approved technical design.

The bootstrap-to-launch handoff must be structured and safely quoted, not eval/source of file-derived shell fragments. Service and control paths must use consistent config selection and validated identity. Define handling of config changes between bootstrap and application load (snapshot/version check), preserve control port 0, and document that changing node identity/cookie requires managing the old process with its old identity/config before the next start.

Recommended bounded product scope if approved: node long name, cookie or env/file reference, service distribution port; not arbitrary ERTS flags/VM-args text, schedulers/tuning, TLS distribution, new OS packaging or hot changes. Existing CLI release remains compatible and outside feature migration.

The user asked about difficulty but never approved the extension, then chose native runtime.exs / Config.Provider integration instead. Do not implement this TOML bootstrap proposal.

## Native Release Defaults and Whether Hush Is Necessary

Verified against Mix v1.20.4 source (the installed toolchain): https://github.com/elixir-lang/elixir/blob/v1.20.4/lib/mix/lib/mix/tasks/release.ex, especially `build_rel/2` and `maybe_add_config_reader_provider/3`; documentation: https://hexdocs.pm/mix/Mix.Tasks.Release.html and https://hexdocs.pm/elixir/Config.Provider.html.

- Build time: `config/config.exs` and imported environment config are evaluated and embedded into the release's `releases/<version>/sys.config`; these source files are not automatically re-read on the target.
- Runtime script selection happens at build time: `runtime_config_path: false` disables automatic inclusion; an explicit `runtime_config_path` selects that source file; otherwise Mix checks `config/runtime.exs` relative to the project's config directory. The inspected version has a deprecated `config/releases.exs` fallback if runtime.exs is absent. This is not target-side filesystem discovery.
- The chosen source script is copied as `$RELEASE_ROOT/releases/<version>/runtime.exs`. An automatically prepended Config.Reader evaluates it before user-configured providers; provider arguments disable imports, so `import_config` is not the way to bring an external config into release runtime.exs. Use explicit Config.Reader/provider integration instead.
- Extra `config_providers` run in configured order after the bundled runtime reader, if present. Config.Reader merges external native settings with incoming configuration. A bundled runtime script that raises for a missing secret cannot be fixed by a later provider; external resolution and required-value validation must be ordered correctly.
- The default launcher uses `$RELEASE_ROOT/releases/<version>/sys.config` unless RELEASE_SYS_CONFIG overrides its base path (without the `.config` suffix). That variable selects Erlang sys.config, not an arbitrary Elixir `.exs` file. The launcher may create a writable runtime config copy for providers; avoid conflating this generated artifact with an operator's source configuration.
- There is no built-in FHS/XDG search, BEAMLET_CONFIG meaning, or generic `--config <external.exs>` host flag. BEAMLET_CONFIG is an existing Beamlet convention. A Config.Reader provider can read a path from a chosen environment variable; FHS/XDG first-file selection still requires a small product-specific selector.
- Current `mix.exs` daemon runtime_config_path points to `config/daemon_runtime.exs`, copied under the same release runtime.exs name; it explicitly reads BEAMLET_CONFIG. The existing local artifact's sys.config provider entry also refers to `/releases/0.1.0/runtime.exs` (local build evidence only).

Hush is not necessary to meet native external-file loading, environment-value reads, file-value reads, or discovery requirements. Native scripts can call System.fetch_env!/get_env and File.read!, and Config.Reader supplies native evaluation/merge. Hush remains useful as a uniform placeholder/provider/transformer API, especially if remote secret sources are later required. It does not add FHS/XDG discovery. The user subsequently approved removing the planned Hush dependency; native-only loading is now the active requirement.

## Native Organization Proposal

See `../design.md` and `../implement.md` for planning drafts. Key proposal: separate build defaults, pre-VM Release options, early external application configuration, and ordinary application startup. Explicitly register Web as a Release root. For migrated Web/daemon releases, use `runtime_config_path: false` with one small native provider so external loading and final validation have a single ordering owner; this is an officially supported choice, not an official requirement to abandon per-host runtime scripts. Keep existing CLI runtime/foreground behavior compatible.

Phoenix's official release guide (https://hexdocs.pm/phoenix/releases.html) separately documents asset compilation/digests, packaged HTTP-server activation, environment reads in runtime configuration rather than libraries, pre-VM cluster options in rel/env.sh.eex, and explicit operational migration commands. Apply those principles to Beamlet without adding Phoenix/Ecto migration behavior to its existing custom storage lifecycle.

Current gaps are documented with source evidence in design.md. In particular, configuration entries for Web in an umbrella sys.config do not prove Web code is shipped in a backend release. The copied dependency closure remains the actual packaging check.

## Shared Environment Configuration Clarification

The user accepted the native proposal while asking whether daemon can share Phoenix-generated dev/test/prod config. It already does: Web, daemon and CLI manifests all point to ../../config/config.exs. These are Mix umbrella configuration files, irrespective of which scaffold created them. Keep one shared root/environment configuration tree; separate application keys and Release dependency roots, not duplicated daemon_dev/prod/test files. The selected provider approach also does not require a separate per-host runtime script for migrated releases. Build environment and Release target are independent axes; a prod artifact is not converted into a dev build by setting MIX_ENV on deployment.

This sharing clarification does not automatically add a new shared multi-host external config format or import hierarchy. External discovery filenames remain deployment entry names, and explicit paths can use other names. Current no-file policy and final acceptance are restated in PRD/design for review.

## Interpretation boundary

Official docs establish recommended mechanisms and supported options, not statistical prevalence across all production Elixir systems. It is accurate to say environment variables plus runtime.exs are the documented standard path, and Config.Provider is the official extension for external formats. No claim that TOML is the most popular format is supported by this research.
