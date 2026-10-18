# Independent full-scope acceptance review

Verdict: **READY** after the fixes below. No unresolved P0/P1/P2 findings.
Reviewed against baseline `13824da` on `refactor/app-host-naming`.
No commits, archive, push or external deployment performed.

## Scope and method

Loaded the active task through `task.py current --source`, read `check.jsonl`,
its curated specs/research, PRD/design/implementation plan and implementation
evidence. Package discovery reports a single repo with backend specs. Followed
backend/index.md's pre-development checklist and quality-guidelines.md (the index
has no separate Quality Check section), plus the shared thinking/reuse guidance.
Repeated package discovery after verification.

Inspected the tracked diff AND both untracked replacement app trees. Compared
all baseline-tracked files under the former app roots to their mapped new paths,
normalizing expected identity changes to expose other differences. No missing
migrated source, tests, catalogues or tracked binary resources were found.
Server behavior is a namespace/application-identity migration; Web logic and
assertions remain equivalent apart from new app ownership and asset paths.
Catalogue content, browser cookie/salts, UI source and CLI behavior are preserved.

Reviewed root release selection, runtime secret discrimination, application
callbacks/dependencies, explicit Node composition, Phoenix/Gettext/static ownership,
asset profile/colocated paths, distributed fixtures, deployment controls/cleanup,
current specs and breaking migration instructions. Current-source legacy-identity
search found only migration documentation and negative artifact/build assertions;
retained Web release/profile/module paths are intentional. Historical evidence and
tracked SBoM were not edited.

## Findings and fixes

1. **P2 — Development watchers referenced an undefined asset profile.**
   `config/dev.exs` passed `:beamlet_app_web` to Esbuild/Tailwind while
   `config/config.exs` retains their `:beamlet_web` profiles. Independent execution
   reproduced `ArgumentError: unknown esbuild profile`. Production asset and
   copied HTTP checks cannot detect this development-only failure. Restored both
   watcher arguments to `:beamlet_web`; both actual `config_for!/1` lookups now
   succeed and point to existing new asset directories. Captured this requirement
   in quality-guidelines.md. Before/after logs are preserved separately.
2. **P3 — Host package tarball ignore patterns used release names.**
   Updated both new app `.gitignore` files to match their actual package app names:
   `beamlet_app_server-*.tar` and `beamlet_app_web-*.tar`.
3. **P3 — Web host instructions still called the other host daemon.**
   Updated `apps/beamlet_app_web/HOST.md` to say server. Native Unix `daemon`
   terminology remains intact elsewhere.

Also found a recreated `apps/beamlet_daemon/.expert` cache (one file, no source
or mix.exs). Inspected every file, then moved the cache-only root to
`_build/independent-retired-beamlet_daemon-editor-cache`. Both obsolete app roots
were absent at final inspection. This is editor cleanup, not a compatibility app.

Review source edits: `config/dev.exs`, both host `.gitignore` files,
`apps/beamlet_app_web/HOST.md`, `.trellis/spec/backend/quality-guidelines.md`,
and this report. No runtime implementation or lifecycle/isolation assertion was
changed.

## Independent executable verification

Fresh logs: `/tmp/beamlet-host-naming-independent/`.

- Watcher profile failure reproduced (`watchers-before.log`, exit 1); both repaired
  real tool lookups and opt-in Node absence passed (`watchers-after.log`).
- `mix format --check-formatted` and `mix compile --warnings-as-errors` passed
  after the fix and cache move; final logs are empty, without old-root warnings.
- Focused seed-631927 tests passed: i18n 15, Server config/runtime 7,
  Web controllers/i18n 21, **43 total** (`focused-tests.log`).
- `mix credo --strict --all` passed: 197 files, no findings (`credo.log`).
- Python cleanup fault injection passed all six tests (`cleanup.log`).
- Independently copied the checked Server artifact and ran native Unix
  daemon launch/readiness/RPC/pid/stop/actual exit with a fresh private cookie:
  passed (`daemon.log`, `daemon/`). No private cookies printed.
- Rehashed every file of the existing Server/CLI/Web artifacts against their
  acceptance copy manifests: exact matches, respectively 1342/1437/2034 files
  (`artifacts.log`). Also inspected all four artifact app inventories/launchers:
  default and explicit Server use beamlet_app_server/bin/beamlet_server;
  Web uses beamlet_app_web/bin/beamlet_web; CLI retains its identity. No removed
  OTP apps, Beamlet.Daemon beams or obsolete launcher found.
- `git diff --check` and Bash syntax checks passed. Final package discovery:
  single repo, backend layer (`packages.log`).

All Mix probes used the installed project Elixir 1.20.4 toolchain and
`ERL_FLAGS='+S 2:2'`, from the umbrella root.

## Existing acceptance evidence challenged against logs/artifacts

The reviewed integrated evidence is `/tmp/beamlet-acceptance.mwUw5z`, with
additional completion/cleanup probes in `/tmp/beamlet-host-naming-evidence`.
The retained failed first Tailwind run is followed by production compilation,
successful assets/digest/Web assembly and copied HTTP checks. The resumed gates
are explicit in resume.sh/resume.log; this is not a claim that the first integrated
invocation completed without interruption.

| AC | Reviewed evidence and result |
| --- | --- |
| AC1 | New manifests/callbacks; baseline-normalized app diff; app-contracts-final.log; Node manifest has no Application callback. PASS. |
| AC2 | build-default.log/build.log/build-web.log and actual fresh artifact inventories. Default and explicit Server artifacts have the correct native launcher. PASS. |
| AC3 | release.log plus copied logs: isolated closures, all three named Server modes, remote deterministic turn, Web/CLI controls, missing-secret rejection, HTTP/assets; fresh independent daemon pass. PASS. |
| AC4 | tests.log sums to 441 passed/49 excluded. distributed.log actually executes Runtime 6 + Node 20 + Server 2 + Web 5 + CLI 1 = 34, with 556 excluded overall. Existing assertions retained; durable.log completes both phases. PASS within stated storage exclusions. |
| AC5 | Unchanged catalogues/session/UI except ownership; 43 focused tests above; copied HTTP and digested CSS/JS evidence. PASS. |
| AC6 | Current specs/docs/examples/checkers map to new source and native commands; migration instructions require complete artifact plus matching config, with foreground service-manager recommendation. PASS. |
| AC7 | Current logs show format/compile, ordinary/named tests, default/strict Credo, Sobelow scan complete, Gettext drift, Dialyzer zero errors, PTY, Python cleanup, copied releases and durable e2e. Dialyzer removed/added 27 modules in its existing PLT: this is an updated PLT, not analysis-only evidence. PASS with limits below. |
| AC8 | Actual artifact identity inventories and exact manifest matches; old-release.log specifically rejects unknown :beamlet_daemon and lists the new releases; no source aliases/fallbacks/forwarders. PASS. |

Full manifest SHA256 values independently match the recorded evidence:

- Server: `5511962f1f7b9de6ccdef2234c72d72d9d6ecc702a7e74b2e8920b3d77e18767`
- CLI: `9632ac5c67c64ebb50514af9512bb9709a7ca3994134c9bc74cc9a0a7d683580`
- Web: `2923c1eb01276f64230e51f643e8aa177151d16b9859fa7c3104952c088eface`

## Artifact currency and residual limits

Artifacts under `_build/host-naming.ETqZWy/{server-default,server,cli,web}` remain
current for production acceptance: review edits touch only development config,
ignore metadata and documentation. No production source/runtime/assets were
changed; no release rebuild is required for these edits. Full previously passing
suites were not repeated without a relevant change; independent checks are listed
separately above.

PostgreSQL-tagged adapter tests were excluded in the ordinary suite; there is no
new PostgreSQL adapter-contract evidence. SQLite and durable e2e evidence passed.
Active Elixir LSP evidence remains inconclusive. No physical cross-host deployment
or paid provider calls are claimed. Editor tooling may recreate cache-only old
roots, so inspect them again before staging. The migrated app trees are currently
untracked and must be included with the tracked deletions when the main session
prepares commits; a tracked-only diff is not the completed change.

Final disposition: **READY**, with no unresolved in-scope defects identified.
