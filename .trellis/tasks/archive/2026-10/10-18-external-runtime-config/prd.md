# Default Mix Release deployment

## Goal

Use the normal Mix Release deployment/configuration flow with minimal changes to existing files. The user's latest instruction withdraws every custom configuration requirement previously explored in this task. This document supersedes the former external-configuration PRD and historical research recommendations.

## Requirements

- R1 — Use shared config/config.exs, dev/test/prod configuration and the existing config/runtime.exs, packaged by Mix through its default runtime configuration mechanism.
- R2 — No new application, dependency, configuration framework, custom Config.Provider, shell wrapper, configuration file, or environment variable. In particular, do not implement --config, FHS/XDG discovery, a required external document, or a replacement BEAMLET_CONFIG interface.
- R3 — Remove the abandoned implementation and the deployment startup requirement for BEAMLET_CONFIG. Merely restoring the pre-task baseline is insufficient: that baseline already has custom daemon/CLI external-file loaders and a mandatory custom shell policy.
- R4 — Retain independent Web/daemon/CLI release dependency closures, shared defaults, existing host validators and opt-in ordinary library loading. Do not refactor business modules, protocol, storage or CLI interaction behavior to solve configuration cleanup. Boot must not migrate/create databases.
- R5 — No new deployment environment variables. Existing Web secret handling and native Mix Release settings remain available; backend startup must not require a dummy Web secret. The existing backend-only build selector is not a new deployment requirement.
- R6 — No staging, commit, push, branch switch or physical deployment without separate authorization. Reuse existing task/docs/tests rather than proliferating files.

## Acceptance Criteria

- [x] AC1 (R1–R3): No beamlet_config application, custom provider/validation adapter framework, wrapper, CLI config flag, discovery policy or required external deployment file remains from this task.
- [x] AC2 (R1, R3, R5): Named releases use the default bundled runtime.exs mechanism; startup/help/control commands do not require BEAMLET_CONFIG or a newly introduced environment variable.
- [x] AC3 (R4, R5): Web listens with its existing required secret and packaged assets; daemon/CLI boot without Web code or a Web secret. Verify copied artifacts using temporary fixtures, not new checked-in scripts.
- [x] AC4 (R4): Host validation, dependency isolation, optional storage/no-boot-migration and existing CLI foreground behavior remain intact. Existing runtime host loaders are retired rather than duplicated.
- [x] AC5 (R2, R6): No new product/config/script/test files remain; relevant format/compile/test and copied-release checks are recorded honestly. Update existing documentation/specs only as needed.

## Evidence and Compatibility

Root mix.exs originally declares daemon/CLI releases with custom runtime_config_path values; CLI also has an existing foreground entrypoint hook. config/daemon_runtime.exs (HEAD) and config/cli_runtime.exs read BEAMLET_CONFIG, and rel/env.sh.eex (HEAD) requires it for every command and pins distribution ports. Those are existing Beamlet policies, not Mix defaults. config/runtime.exs currently requires SECRET_KEY_BASE for production Web; scope that existing check to Web rather than duplicating runtime scripts. Existing validators live in Beamlet.Daemon, Beamlet.CLI and Beamlet.Web.Host.

Removing custom deployment config intentionally retires the old external-file startup contract. It does not remove the CLI's business command for reading Agent creation options. The existing CLI foreground entrypoint is a separate pre-existing behavior to preserve, not a reason to add another launcher layer.

## Planning Status

Implemented and accepted by the user. The superseded external-configuration architecture remains withdrawn; design.md and implement.md are retained as the historical revised plan.

Acceptance evidence is the implementation handoff recorded at session artifact
`default-release/implementation.md`: 441 ordinary passes / 49 excluded against a 439
tracked baseline, format/warning-fatal compile/strict Credo/Sobelow/existing-PLT
Dialyzer, 34 actual named distributed passes, three fresh isolated release builds,
and copied-artifact checks covering daemon role modes plus a real remote turn,
CLI foreground identity/PTY behavior, and Web missing-secret rejection then HTTP
200 with digested CSS/JS. The independent check was skipped by explicit user
decision; those implementation-reported gates are not parent-reproduced evidence.
Known limits: LSP diagnostics inconclusive (tool dependency failure), PostgreSQL
adapter tests excluded, no physical deployment or paid-provider execution. Native
Config script/reader exceptions are no longer sanitized by Beamlet because the
custom reader was retired.
