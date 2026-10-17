# Quality Guidelines

## Formatting and Local Code Shape

`.editorconfig` specifies UTF-8, LF, two-space indentation, final newline, and no
trailing whitespace. Root `.formatter.exs` includes root Mix/config/benchmark
files and delegates to `apps/*`. Child formatters cover Elixir source/tests;
`apps/beamlet_web/.formatter.exs` imports Phoenix and uses
`Phoenix.LiveView.HTMLFormatter` for HEEx. Use those formatters rather than
reformatting by hand.

Follow nearby modules: snake_case file/function names and `Beamlet.*` modules
(e.g. `apps/beamlet_agent/lib/beamlet/agent.ex` and
`apps/beamlet_web/lib/beamlet_web/controllers/page_controller.ex`). Public stub
modules have `@moduledoc`/`@doc` with doctests, while Application callbacks use
`@moduledoc false` and `@impl true`; this is scaffolding evidence, not a mature
domain typing or documentation policy. Web setup belongs in
`apps/beamlet_web/lib/beamlet_web.ex`; reuse its imports and verified routes.

## Commands and Their Scope

Check executables and dependencies before promising a passing check. `README.md`
uses `nix develop`; `flake.nix` selects OTP 29 and Elixir 1.20. The five non-web
manifests require Elixir `~> 1.20`; the web manifest still says `~> 1.17`.
Use the umbrella toolchain rather than assuming the web lower bound suffices.

Run these from the repository root unless noted:

| Change/check | Command and evidence |
| --- | --- |
| Fetch dependencies when setup is needed | `mix deps.get` (`README.md`); children share root `mix.lock` |
| Compile | `mix compile` (`README.md`) |
| Format/check Elixir and HEEx | `mix format` / `mix format --check-formatted` (`.formatter.exs`, child formatters, `.pre-commit-config.yaml`) |
| All app tests | `mix test` (`README.md`, pre-commit test hook) |
| Focused web regression | `cd apps/beamlet_web && mix test test/beamlet_web/controllers/page_controller_test.exs` (child manifest uses shared root config) |
| Static checks | `mix dialyzer`, `mix credo`, `mix sobelow` (`.pre-commit-config.yaml`, root tool deps); root alias runs `sobelow --root apps/beamlet_web --private` |
| Repository hooks | `pre-commit run --all-files` (`README.md`, `.pre-commit-config.yaml`); this includes general file hygiene, Elixir test/format hooks, Dialyzer, Credo, Sobelow, the example benchmark and CycloneDX SBoM generation |
| Asset changes | `cd apps/beamlet_web && mix assets.build`; `mix assets.deploy` for minified/digested output (child `mix.exs` aliases) |
| Benchmark setup smoke check | `mix bench` (root alias runs `bench/enum.exs` without starting apps); this compares Enum/comprehension, not Beamlet performance |

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

## Tests to Follow and Limits to Preserve

Each app has `test/test_helper.exs` calling `ExUnit.start()`. Non-web tests mirror
source directories and use ExUnit plus doctests; examples include
`apps/beamlet_actions/test/beamlet/actions_test.exs`,
`apps/beamlet_agent/test/beamlet/agent_test.exs`, and
`apps/beamlet_runtime/test/beamlet/runtime_test.exs`. Actions/Runtime now have
behavioral validation, composition, lifecycle, limit and distributed tests; the
Harness tests independently cover native contracts and actual TCP/TLS/workspace
behavior; Agent/Node tests cover orchestration, roles, lifecycle ownership and actual peer VMs.

Web tests use `apps/beamlet_web/test/support/conn_case.ex`, which imports
`Plug.Conn`, `Phoenix.ConnTest`, and verified routes and builds a connection in
setup. It does **not** start a database sandbox, despite its generated prose.
`config/test.exs` sets `server: false`; connection tests need no listening server.

From `apps/beamlet_web/test/beamlet_web/controllers/page_controller_test.exs`:

```elixir
test "GET /", %{conn: conn} do
  conn = get(conn, ~p"/")
  assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
end
```

The same file tests the CSP nonce in both response policy and rendered script,
a 16-byte decoded nonce, a fresh value per response, secure headers, and absence
of unsafe script policy/debugger allowance in test. Preserve this router/layout
contract when editing scripts:
`apps/beamlet_web/lib/beamlet_web/router.ex` assigns the nonce and
`apps/beamlet_web/lib/beamlet_web/components/layouts/root.html.heex` consumes it.
Do not relax CSP to bypass a rendering failure. Error HTML/JSON tests in that
controller test directory use `ConnCase, async: true` and check 404/500 renderers;
the page tests do not opt into async. Follow a test's actual state needs rather
than treating async as universal policy.

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

## Review Before Handoff

- Compare implementation against its owning child manifest and neighboring tests,
  not only the intended architecture document.
- For routing/template changes, check the shared `Beamlet.Web` setup and the CSP
  regression together. For failures/state changes, consult the linked topic specs.
- Run applicable checks above; record what ran, failed, or was skipped and why.
  Keep dependency updates, generated assets, and unrelated scaffold cleanup out
  of a narrowly scoped change unless the task explicitly requires them.
