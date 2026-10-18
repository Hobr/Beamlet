# Implementation plan

## Entry gate

- [x] User approved task creation and target naming.
- [x] User chose removal without compatibility.
- [x] Inspect current source, configs, deployment checks and backend specs; record research/current-state.md.
- [x] Converge PRD and write design.md plus implement.md.
- [x] Populate both JSONL manifests with real spec/research entries.
- [x] Present complete planning summary and receive explicit approval in a subsequent user message (user: 批准).
- [x] Run task.py start; status is in_progress. Work branch: refactor/app-host-naming.

## 1. Migrate applications as one coordinated change (AC1, AC4, AC8)

- [x] Load implementation specs from implement.jsonl and inspect current git state/toolchain. Carry forward any independent user edits.
- [x] Move apps/beamlet_daemon → apps/beamlet_app_server; move its daemon modules/files/test identities to Server; update manifest application/callback and all app-env operations.
- [x] Move apps/beamlet_web → apps/beamlet_app_web; retain Beamlet.Web and lib/test beamlet_web namespace paths.
- [x] Update consumers, configuration atoms, explicit child-app fixtures, registered Server names and Server-specific errors. Keep Node's callback-free seam, role validation, optional storage and bootstrap ownership intact.
- [x] Remove old directories/identities/modules completely; add no aliases or fallback configuration.

Checkpoint: new app manifests and source compile consistently; no removal/weakening of existing behavior assertions.

## 2. Wire releases, configuration and Web resources (AC2, AC3, AC5)

- [x] Root mix.exs: default_release beamlet_server; Server/Web entry apps beamlet_app_server/beamlet_app_web; backend list and Sobelow root use new identities/paths.
- [x] config/runtime.exs: RELEASE_NAME beamlet_server enables Server; retained beamlet_web enables renamed Web app. Keep secret requirements and CLI behavior.
- [x] Update config/{config,dev,test,prod}.exs, Phoenix/Gettext otp_app, Plug.Static source, resource paths, asset working directories, dev reload paths and app metadata reads.
- [x] Keep tool profile beamlet_web, Release beamlet_web, browser cookie and salts where these represent retained concepts.
- [x] Update shared i18n test catalogue paths. Regenerate catalogues through Mix only if required, then verify ownership/translations.

Checkpoint: full umbrella and backend-only build configurations agree with the app moves; no stale artifact can be the sole evidence of compilation success.

## 3. Update deployment checks and documentation (AC3, AC6, AC8)

- [x] Migrate scripts/deployment references, default artifact paths, .rel/.app assertions, injected Elixir config, module isolation probes and CLI/server fixtures.
- [x] Move daemon.example.exs → server.example.exs and durable-e2e test path; update commands in deployment and app docs.
- [x] Extend existing acceptance tooling to check default Server selection and a bounded native Unix daemon lifecycle with guaranteed cleanup; preserve existing named foreground/control, HTTP/assets and CLI checks.
- [x] Document immediate-breaking app/config/module/command mappings and complete artifact replacement. Recommend native foreground start for service managers; native daemon remains optional.
- [x] Update current .trellis/spec/backend docs for paths/identities and host vs library vocabulary; preserve historical archive/journal evidence and tracked historical SBoM.

## 4. Verify and review (AC1–AC8)

Use the project's Elixir/OTP environment (`nix develop` if necessary), repository-root commands and finite/logged subprocess runs. Keep long-running gates observable and record their evidence paths under task research. Do not claim a gate passed merely because it ran historically. Reuse passing current gate results unless edits or failures require rerunning them.

- [x] Inventory old references using rg including hidden current config/tool files. Classify legitimate Release/profile/lib paths, historical documents and migration notes; require no live references to removed OTP app identities or Beamlet.Daemon modules.
- [x] Verify whitespace with git diff --check, format with mix format --check-formatted, and compile with mix compile --warnings-as-errors. Probe changed Elixir paths via active LSP if available; a timeout is inconclusive.
- [x] Run mix test --seed 631927 and actual named distributed suite via `elixir --sname <unique-name> --cookie <private-cookie> -S mix test --only distributed --seed 631927` with ERL_FLAGS='+S 2:2'. Generate the cookie privately, never print it; preserve executed/excluded counts and bootstrap/helper cleanup assertions.
- [x] Run mix credo and mix credo --strict --all, mix sobelow, mix gettext.extract --check-up-to-date and mix dialyzer. Distinguish existing-PLT analysis from any refresh.
- [x] Run Python fixture cleanup regressions and existing CLI PTY gate when reached by integrated checker.
- [x] Build into fresh generated release directories: `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release` demonstrates default selection; also verify explicit `mix release beamlet_server`. Assert old `mix release beamlet_daemon` is rejected for unknown release (not an unrelated build failure).
- [x] Build CLI via `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_cli`; build Web assets with `MIX_ENV=prod mix tailwind beamlet_web --minify`, `mix esbuild beamlet_web --minify`, `mix phx.digest`, then `mix release beamlet_web` in the same production environment.
- [x] Run updated bash scripts/deployment/check-release.sh against all three artifacts, including closure absence of old apps/modules, native named start/RPC/pid/stop, native daemon smoke, missing Web secret and actual HTTP/digested assets. Eval alone is insufficient.
- [x] Run bash scripts/deployment/durable-e2e.sh to validate unchanged optional storage/durable host behavior.
- [x] Updated check-local.sh may orchestrate ordinary/static/named/build/copied gates once; add missing default selection, old-release rejection, Gettext and durable checks separately as needed. Record failed attempts and final successes without overwriting evidence.
- [x] Run independent Trellis check against the complete change and spec/acceptance map; fix verified findings and rerun affected gates. Every subagent prompt starts with `Active task: .trellis/tasks/10-18-app-host-naming` and follows the implement/check no-recursion rule.

Current evidence: `research/implementation-evidence.md`. Integrated run needed one
production asset-ordering repair; final remaining gates and focused daemon cleanup
probes passed. Independent full-scope review is READY; see research/independent-review.md. Its watcher-profile repair passed 43 focused tests plus compile/format/strict Credo and native daemon verification. Final spec-sync added the executable host/release/profile contract to backend-release.md.

## 5. Finish

- [x] Record AC1–AC8 results, known limitations and artifact fingerprints in research/implementation-evidence.md.
- [x] Perform spec-sync review and ensure current docs match final checked behavior.
- [x] Inspect dirty paths, propose logical commits with user-owned/unrecognized changes kept separate, and follow the repository commit confirmation policy. User approved `refactor(apps): rename server and web host applications`; no unrelated dirty paths.
- [ ] Wrap up/archive/journal through the normal finish-work flow after implementation and verification.

## Rollback points and constraints

Before implementation only task artifacts have changed. During implementation use narrow edits and file moves; do not hard-reset or clean the user's workspace. Generated cleanup must target only confirmed generated destinations, not source/data. If identity wiring fails, keep deployment checks failing until it is corrected; do not reintroduce legacy forwarding or weaken isolation. Deployment rollback uses the prior complete release plus its matching config. No database format or migration changes are authorized here.
