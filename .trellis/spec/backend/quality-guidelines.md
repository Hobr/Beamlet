# Quality Guidelines

## Formatting and Local Code Shape

`.editorconfig` specifies UTF-8, LF, two-space indentation, final newline, and no
trailing whitespace. Root `.formatter.exs` includes root Mix/config/benchmark
files and delegates to `apps/*`. Each new child MUST have its own `.formatter.exs` for root delegation to cover it.
Both persistence domain apps import Ecto/SQL and use the established Storage input
patterns. A passing root check with a missing child formatter proves no coverage
of that child (independent review F2). Child formatters cover Elixir source/tests;
`apps/beamlet_app_web/.formatter.exs` imports Phoenix and uses
`Phoenix.LiveView.HTMLFormatter` for HEEx. Use those formatters rather than
reformatting by hand.

Follow nearby modules: snake_case file/function names and `Beamlet.*` modules
(e.g. `apps/beamlet_agent/lib/beamlet/agent.ex` and
`apps/beamlet_app_web/lib/beamlet_web/controllers/page_controller.ex`). Public stub
modules have `@moduledoc`/`@doc` with doctests, while Application callbacks use
`@moduledoc false` and `@impl true`; this is scaffolding evidence, not a mature
domain typing or documentation policy. Web setup belongs in
`apps/beamlet_app_web/lib/beamlet_web.ex`; reuse its imports and verified routes.

## Commands and Their Scope

Check executables and dependencies before promising a passing check. `README.md`
uses `nix develop`; `flake.nix` selects OTP 29 and Elixir 1.20. Backend manifests require Elixir `~> 1.20`; the web manifest still says `~> 1.17`.
Use the umbrella toolchain rather than assuming the web lower bound suffices.

Run these from the repository root unless noted:

| Change/check | Command and evidence |
| --- | --- |
| Fetch dependencies when setup is needed | `mix deps.get` (`README.md`); children share root `mix.lock` |
| Compile | `mix compile` (`README.md`) |
| Format/check Elixir and HEEx | `mix format` / `mix format --check-formatted` (`.formatter.exs`, child formatters, `.pre-commit-config.yaml`) |
| All app tests | `mix test` (`README.md`, pre-commit test hook) |
| Focused web regression | `mix test apps/beamlet_app_web/test/beamlet_web/controllers/page_controller_test.exs` from the umbrella root (child-dir form is blocked by an umbrella `:only` mismatch; see below) |
| Static checks | `mix dialyzer`, `mix credo`, `mix sobelow` (`.pre-commit-config.yaml`, root tool deps); root alias runs `sobelow --root apps/beamlet_app_web --private` |
| Repository hooks | `pre-commit run --all-files` (`README.md`, `.pre-commit-config.yaml`); this includes general file hygiene, Elixir test/format hooks, Dialyzer, Credo, Sobelow, the example benchmark and CycloneDX SBoM generation |
| Asset changes | `mix tailwind beamlet_web`, `mix esbuild beamlet_web`; add `--minify` for deploy output and `mix phx.digest` for digests. Run from the umbrella root: `cd apps/beamlet_app_web && mix assets.build` currently fails on an umbrella dependency-consistency check |
| Catalogue regeneration after any copy change | `mix gettext.extract --merge` from the umbrella root (it recurses over all apps, so the shared, Web and CLI catalogues are refreshed in one run); do not run extraction inside a child directory |
| Catalogue drift gate | `mix gettext.extract --check-up-to-date` from the umbrella root; a clean exit is required before claiming the catalogues match the source |
| Benchmark setup smoke check | `mix bench` (root alias runs `bench/enum.exs` without starting apps); this compares Enum/comprehension, not Beamlet performance |

Before building production assets in a fresh checkout/build environment, run
`MIX_ENV=prod mix compile --warnings-as-errors`. Phoenix generates colocated assets
under `_build/prod/phoenix-colocated/beamlet_app_web` during compilation; Tailwind
and esbuild must consume that same environment. Keep their `beamlet_web` profile
labels and the `beamlet_web` release name distinct from the OTP app identity.
Development Endpoint watchers must also pass `:beamlet_web` to
`Esbuild.install_and_run/2` and `Tailwind.install_and_run/2`; passing the OTP app
`:beamlet_app_web` fails profile lookup even when production asset builds pass.

Umbrella child-directory commands are unreliable: `apps/beamlet_app_web` and `apps/beamlet_cli` declare `beamlet_runtime` (and CLI also `beamlet_harness`) with `only: :test`, while `apps/beamlet_node` declares `beamlet_runtime` without it, so Mix aborts any task started inside those child directories ("does not match the :only option calculated"). Root-level equivalents are authoritative until that pre-existing manifest inconsistency is resolved; do not silently drop the restriction just to make a child command run.

The local hooks use system `mix`; test and format hooks match Elixir files.
Dialyzer, Credo, Sobelow, benchmark and SBoM hooks also match root `mix.lock`
changes and use `pass_filenames: false` to run once against the umbrella.
Run `pre-commit install` after cloning to enable the commit hook. The SBoM hook
uses `--force --output _build/bom.cdx.json` to avoid interactive overwrite prompts
and leave the tracked root `bom.cdx.json` unchanged.
There is no checked-in GitHub build/test workflow, coverage threshold, or custom
Credo configuration. Tool declarations and README commands do not establish a
passing baseline; report actual results, including dependency/tool failures.
For documentation-only edits, check whitespace, links/source paths, and example
accuracy; application tests need not run solely because Markdown changed.

## Credo Gate for the Merged Durable Code

The durable/storage merge (Agent, Runtime, Storage plus their tests) is now
Credo-clean on the repo defaults: `mix credo` and `mix credo --strict --all` both
exit 0 with no findings. Keep it that way, and keep the remedy a refactor:

- Fix findings with the safe refactor patterns only: a top-level `alias` group
  for repeated `Beamlet.*` prefixes (ordered alphabetically), small `defp`
  helpers to cut nesting/cyclomatic complexity/arity, `if`/`unless` for two-branch
  `cond`, `case` for a single-clause `with`, and composed `quote` fragments for
  the shared storage-contract macro.
- Suppression is not the remedy: no `.credo.exs`, no `--ignore`/directory
  exclusions, no rule downgrades, no `# credo:disable-*` comments. Only
  `@moduledoc false` on test-support modules is expected.
- Refactoring must be behaviour-equivalent: no schema/migration, transaction/CAS/
  admission, public function signature, error reason or test-assertion change.
  Audit assertion ownership when splitting suites; a changed count alone cannot
  establish parity. Historical cleanup counts were umbrella439/49 excluded and
  Storage59/13; current ownership/accounting is in the independent review.
- Verify with `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test --seed 631927`, `mix credo`, `mix credo --strict --all`, `mix sobelow`,
  `mix gettext.extract --check-up-to-date`, `mix dialyzer` and
  `bash scripts/deployment/durable-e2e.sh`; the initial cleanup run recorded
  44 findings under the default profile (exit 12) and 106 under `--strict --all`
  (exit 14) before the refactor.

## Checked format3 migration evidence

The authoritative [independent review](../../tasks/archive/2026-10/10-18-storage-action-decoupling/research/independent-review.md)
records the corrected full candidate, exact per-app/adapter accounting, commands,
retained logs and AC1–AC8 assessment. Ordinary552/37 excluded, named587/2 excluded
(the separately executed E2E phase tags), and actual Agent PG109 passed. Foundation:
10 SQLite +2 PG +4 codec +1 fresh-VM; Actions:5 SQLite authority +7 PG authority +5
SQLite journal; Agent Storage:17 dataset +23 SQLite domain +24 PG domain. These are
executed owning suites, not inferred coverage or a union of partial runs.
Warning-fatal compile, expanded root format, strict Credo, existing-PLT Dialyzer
(0 errors/0 skipped), Sobelow/catalogue, fresh releases and two-process E2E passed.
F1 requires strict JSON safe normalization in both read AND write facades; see
[Error Handling](./error-handling.md#scenario-strict-persisted-json-failure). F2 is
child formatter coverage above. Neither has a remaining blocker. Failed original
logs remain failures; earlier evidence in this file is historical to its stage.
No LSP-clean, physical-host, power-cut or provider-execution claim follows.
Markdown-only synchronization checks links/source signatures/whitespace and does
not manufacture new application gate runs.

## Tests to Follow and Limits to Preserve

Each app has `test/test_helper.exs` calling `ExUnit.start()`. Non-web tests mirror
source directories and use ExUnit plus doctests; examples include
`apps/beamlet_actions/test/beamlet/actions_test.exs`,
`apps/beamlet_agent/test/beamlet/agent_test.exs`, and
`apps/beamlet_runtime/test/beamlet/runtime_test.exs`. Actions/Runtime now have
behavioral validation, composition, lifecycle, limit and distributed tests; the
Harness tests independently cover native contracts and actual TCP/TLS/workspace
behavior; Agent/Node tests cover orchestration, roles, lifecycle ownership and actual peer VMs.

Web tests use `apps/beamlet_app_web/test/support/conn_case.ex`, which imports
`Plug.Conn`, `Phoenix.ConnTest`, and verified routes and builds a connection in
setup with an explicit **English** session locale (`@test_locale "en"`), because
the product ships Chinese copy by default and behaviour assertions must not depend
on the shipped language. A test that needs another language sets
`@tag locale: "zh_CN"`; a test that must prove the shipped default builds a
session-less `Phoenix.ConnTest.build_conn()`. The case does **not** start a
database sandbox, despite its generated prose. `config/test.exs` sets
`server: false`; connection tests need no listening server.

CLI tests that assert terminal copy set `config :beamlet_cli, :locale, "en"` and
`Beamlet.CLI.Locale.put("en")` in setup and restore both in `on_exit`, so
`Runner`-driven locale installation cannot leak into later assertions. Locale
behaviour itself is covered by `apps/beamlet_cli/test/beamlet/i18n_test.exs`,
`apps/beamlet_app_web/test/beamlet_web/i18n_test.exs` and the catalogue ownership
tests in `apps/beamlet_i18n/test`.

From `apps/beamlet_app_web/test/beamlet_web/controllers/page_controller_test.exs`:

```elixir
test "GET /", %{conn: conn} do
  conn = get(conn, ~p"/")
  assert html_response(conn, 200) =~ "What would you like to do?"
end
```

The same file tests the CSP nonce in both response policy and rendered script,
a 16-byte decoded nonce, a fresh value per response, secure headers, and absence
of unsafe script policy/debugger allowance in test. Preserve this router/layout
contract when editing scripts:
`apps/beamlet_app_web/lib/beamlet_web/router.ex` assigns the nonce and
`apps/beamlet_app_web/lib/beamlet_web/components/layouts/root.html.heex` consumes it.
Do not relax CSP to bypass a rendering failure. Error HTML/JSON tests in that
controller test directory use `ConnCase, async: true` and check 404/500 renderers;
the page tests do not opt into async. Follow a test's actual state needs rather
than treating async as universal policy.

Translation ownership is a checked invariant, not a convention: one msgid has
exactly one owning catalogue (shared `beamlet_i18n`, Web-only, CLI-only), the
`zh_CN` `.po` of every catalogue must translate every extracted msgid, English
`msgstr`s may stay empty, and every `Beamlet.I18n.gettext/1,2` /
`Beamlet.I18n.dgettext/2,3` literal in Web/CLI source must exist in the shared
catalogue. `mix gettext.extract` under Elixir >= 1.19.3 compiles sources twice
(`compile --force-elixir` plus `compile.elixir --force`), so POT/PO files contain
duplicated `#:` reference lines; that is an upstream Gettext 1.0.2 artifact, it is
stable across runs, and it must not be "fixed" by hand-editing generated files.

Runtime distributed tests are excluded by default. Run them explicitly on a named
VM with an isolated cookie and low peer scheduler counts; inspect actual executed
counts. Same-host peers do not prove physical multi-host acceptance. Runtime
`review_test.exs` covers limits, live progress, discovery and admission regressions.
See [Operation Runtime](./operation-runtime.md) and [Native Harness](./harness-providers.md)
for required assertions. Harness socket tests require local TCP/SSL, OpenSSL,
mkfifo and Linux /proc/self/fd; report unavailable prerequisites as skips, not
passing evidence. Agent contracts are covered by [Agent and Node](./agent-orchestration.md);
local release/CLI review passed; cross-physical-host acceptance was removed by the user; physical execution is untested. See
[Backend CLI and Release](./backend-release.md) for isolated build and copied named
start/RPC/stop checks. Eval alone misses control-helper fixed-port collisions.
An empty diagnostic cache or timed-out LSP probe is not a clean result. Record
PLT refresh separately from Dialyzer analysis against an existing PLT.

## Agent Helper Lifecycle Regression Gate

Independent Agent/Node review exposed a recurring failure pattern: moving a
blocking infrastructure call into a monitored helper preserves Agent callback
responsiveness but does not bound the helper's lifetime. A receive timeout starts
only after the call returns and can reset on recursion; it cannot interrupt an
infinite supervisor admission call. A monitor alone cannot process owner loss
while the monitored caller is blocked. Raw spawned helpers also need explicit
authority-lifecycle ownership.

For operation owners and delegation admission/cleanup helpers, assert actual DOWN
within a finite bound while target infrastructure remains suspended. Exercise
Agent loss, authority teardown, delayed coordinator/child creation after the
requester exits, nested delegation and blocked progress acknowledgement. Resume
infrastructure only after the bounded-cleanup assertion, then verify late-created
work observes dead ownership and is not retried. Keep temporary helpers accounted
until observed exit; accepting a business Result or sending `:finished` does not
establish owner termination. Use genuine native progress followed by Runtime
completion to test terminal/ack races.

The previous repair missed these cases because tests resumed infrastructure before
asserting cleanup and removed terminal-owner accounting before DOWN. This is an
implicit lifecycle assumption and integration coverage gap. These are required regression assertions. Independent child3 review passed them
with public Runtime admission integrated (86 impacted tests, seed631927); preserve
these assertions in future changes. Physical-host and release acceptance are separate.


## Distributed Capacity Synchronization

A successful Result does not refresh Directory capacity. Sequential-success tests
must observe actual gateway release/zero tasks and a newer eligible capacity report
before the next single submission. Runtime's distributed regression uses a fence
and lease both from the executor clock; wait deadlines remain local. Exercise an
occupied cached report explicitly rather than rely on scheduler timing. Never add
business retries or weaken success assertions to mask missing synchronization.
The controlled probe established stale capacity → no_target; historical uncaptured
failure reasons remain unknown. Historical MVP gates passed123 ordinary/7 distributed
at two seeds. Provider-migration final independent recheck passed161 ordinary/12
actual named distributed tests at seed631927 (Harness35,Actions28,Runtime30,Agent4,
Node57,Web7; distributed Runtime6+Node6). Same-host evidence is not physical acceptance.

## Provider Contract Regression Gates

Preserve direct malformed reply/catalogue safe errors, exact1MiB/one-byte-over envelopes,
Actions/Harness matching recursive credential root-label and JSON/depth/count/name/byte
vectors, and two independent authorities with different provider registries. Parent
validates portable child shape/common limits; target validates its actual adapter.
Tests must observe successful direct and delegated child input, correlated target
rejection with exactly one dispatch/no parent adapter callback, and malformed local
options producing no helper. Ordinary sibling dependencies must remain independent.

Final provider checks passed format/warning-fatal compile/strict Credo/full existing-PLT
Dialyzer and rebuilt all-seven copied eval/named release combinations. No forced PLT
refresh occurred. Active LSP probe:5 key files,1 confirmed clean,4 timed-out inconclusive;
zero returned diagnostics is not complete coverage. Preserve separate failed/final logs;
overwritten original failure logs cannot establish original root-cause proof.

## Deadline Classification and Observation Gates

`deadline_classification_test.exs` must prove actual admission from a valid aged
report, shorter executor budget, actual worker DOWN and execution-source deadline.
A Coordinator deadline with no worker does not exercise that defect. Fence mailbox
forwarding when controlling local cancel/deadline order, test both source orders,
kill/crash/success and late tombstone messages; assert one terminal and one capacity
release. Do not infer cross-VM ordering from an unsorted trace.

The deadline repair independent gate passed25 focused plus5 temporary adversarial
cases. Inspected broader gates passed230 ordinary/29 distributed excluded and27
named Runtime/Node/CLI distributed/129 ordinary excluded; two Server distributed
cases were not included. Existing-PLT Dialyzer passed with no refresh. The earlier
60s-interrupted distributed run is incomplete, not a pass. Preserve it separately
from the bounded replacement. One historical composition100ms failure remains
unexplained; bounded current tracing shows success, not historical root cause.
Retain that risk and collect correlated outcome/timing evidence on recurrence;
do not increase timeouts, weaken success assertions or retry business work.

Observation regression contracts are in [Live Observation](./live-observation.md).
Reserve-pressure tests must use distinct failure keys: repeated Map.put on one key
does not exercise many-failure overhead. Synthetic private-state pressure tests do
not prove normal report validators accept that state. Registered-service readiness
is not responsiveness; controlled restarts do not alone prove natural coupled loss.

## Review Before Handoff

- Compare implementation against its owning child manifest and neighboring tests,
  not only the intended architecture document.
- For routing/template changes, check the shared `Beamlet.Web` setup and the CSP
  regression together. For failures/state changes, consult the linked topic specs.
- Run applicable checks above; record what ran, failed, or was skipped and why.
  Keep dependency updates, generated assets, and unrelated scaffold cleanup out
  of a narrowly scoped change unless the task explicitly requires them.
