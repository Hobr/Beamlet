# Default Mix Release deployment — Minimal Execution Plan

Status: completed and accepted by the user (archived). Independent check was skipped by explicit user decision. The previous serial workflow is stopped. No new task or product files are needed. Reuse existing planning files and one implementation writer, followed by independent review.

## Ordered work

1. Confirm stopped writers and inspect current diffs. Record the explicit removal list from design.md; preserve unrelated/staged work. No stage/commit/push/branch change.
2. Remove abandoned new app/provider/adapters/wrapper/tests and their wiring. Restore existing shared defaults where the old implementation removed them unnecessarily.
3. Use default Mix runtime.exs packaging for each release, with minimal host-specific activation in that existing file. Keep backend startup independent of the Web secret; preserve host validation, optional storage and CLI foreground entrypoint. Do not add environment variables or files.
4. Retire old deployment runtime loaders and mandatory custom shell config/identity/port policy. Keep native Release controls/settings. Update existing deployment docs, examples and check fixtures in place; do not expand external configuration scope or change CLI Agent creation commands.
5. Run focused existing tests, format/warning-fatal compile, then applicable umbrella/static checks and copied-artifact Web/backend/CLI checks. Build Web assets using existing Mix tasks. Use temporary external probe files only, not new checked-in scripts or test files. Do not claim canceled or unexecuted gates passed.
6. Dispatch an independent whole-diff check, inspect its evidence, update existing specs to the new contract, and report results. Commit remains separately authorized.

## Checks

- git diff --check and git diff --cached --check; inspect untracked/product file list.
- mix format --check-formatted; mix compile --warnings-as-errors.
- mix test --seed 631927; focused existing host/config regression tests.
- mix credo --strict --all; mix sobelow; mix dialyzer (record PLT refresh separately); Gettext drift only when relevant.
- Existing backend build mode: BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite and beamlet_cli equivalent.
- Existing Web asset/digest tasks and MIX_ENV=prod mix release beamlet_web --overwrite after defining the release root.
- Copied service startup and native controls without BEAMLET_CONFIG, real Web HTTP/static requests, isolated closures, CLI foreground behavior and optional-storage safety. Adapt obsolete existing checks, retaining relevant failure assertions rather than pretending old external-file scenarios remain requirements.
- Active LSP diagnostics on changed source paths; timeout/unavailability remains inconclusive.

## Checkpoints

Do not launch implementation until the revised summary is approved. If default runtime packaging exposes an actual compatibility problem, report the concrete issue rather than introducing another app, file, variable or wrapper. Never remove unrelated work or hide known CLI entrypoint behavior under a claim that every launcher is completely unmodified.
