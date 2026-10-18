# Default Mix Release deployment — Minimal Design

Status: implemented and accepted by the user (archived). Supersedes the provider/shared-app/wrapper architecture and all FHS/XDG or external-file recommendations in historical research.

## Configuration and packaging

- Keep the existing shared build configuration and environment files. Undo unrelated default removals made by the abandoned implementation.
- Remove runtime_config_path overrides for daemon/CLI and all added custom config_providers. Mix packages the existing config/runtime.exs in the normal way.
- Keep independent application roots in mix.exs; define the Web root in that existing file. Do not add a library merely for shared deployment logic.
- In existing runtime.exs, use the native RELEASE_NAME context only where required to distinguish the packaged host. Activate only that release's host; keep source dev/test/library startup opt-in. Keep production Web secret/listener handling local to Web and preserve source-run production behavior. No new environment variable is introduced.
- Rely on native Mix distribution/node/cookie/VM defaults and supported native settings. Retire custom mandatory shell policy rather than replacing it with another parser. Remove obsolete host runtime loader files and the custom rel/env.sh.eex if it has no remaining responsibility.
- Preserve existing validators in their current owners. No generic callback framework, new ReleaseConfig adapters, external reader, discovery or error abstraction.
- Preserve the pre-existing CLI foreground behavior/entrypoint; do not turn a configuration cleanup into a CLI lifecycle rewrite. No new launcher customization is added.

## Cleanup boundary

Remove this task's new apps/beamlet_config sources/tests/manifests, host ReleaseConfig adapters/tests, release launcher test and rel/config-wrapper.sh.eex. Remove their references from manifests and release steps. Identify files explicitly; no git clean, hard reset or broad restoration of unrelated changes. Preserve existing staged planning files and stop all writers before cleanup.

Retire deployment startup BEAMLET_CONFIG reads in old host runtime loaders and shell policy, not every occurrence in historic tasks or the separate CLI Agent-options command. Update existing deployment docs/checks/examples to match; do not create replacement examples, scripts or tests. Existing external-config check scenarios no longer represent required behavior and should be adapted in place, not silently reported as passing.

## Compatibility and validation

Changing the old deployment config contract is intentional. Operators now configure normal application config/runtime.exs and use Mix-generated artifacts/native Release settings, rather than a Beamlet discovery layer. Build-time versus runtime semantics remain native; do not promise hot reload, arbitrary runtime editability or a new target-side external-file interface.

Check copied host artifacts and actual Web HTTP/static serving, backend absence of Web secret/code, native help/start/pid/rpc/stop, isolated closures and CLI foreground behavior. Use temporary validation fixtures outside the repo and existing test files. No schema migration, network/provider purchase, data recovery promise or physical deployment.

Reference facts were already verified against Mix 1.20.4: https://hexdocs.pm/mix/Mix.Tasks.Release.html . Historical local spec descriptions of mandatory external config/fixed ports are intentionally superseded by this task, not implementation instructions to restore those policies.
