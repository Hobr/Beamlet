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
| Static checks | `mix dialyzer`, `mix credo`, `mix sobelow` (`README.md`, root tool deps); root alias runs `sobelow --root apps/beamlet_web --private` |
| Repository hooks | `pre-commit run --all-files` (`README.md`, `.pre-commit-config.yaml`); this includes general file hygiene and Elixir test/format hooks |
| Asset changes | `cd apps/beamlet_web && mix assets.build`; `mix assets.deploy` for minified/digested output (child `mix.exs` aliases) |
| Benchmark setup smoke check | `mix bench` (root alias runs `bench/enum.exs` without starting apps); this compares Enum/comprehension, not Beamlet performance |

The local hooks use system `mix`; test and format hooks match Elixir files.
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
`apps/beamlet_runtime/test/beamlet/runtime_test.exs`. They currently only verify
`hello/0 == :world`, not domain behavior.

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

Current gaps: no implemented Agent/runtime/action behavior to test; no focused
supervision, telemetry, reusable component, or end-to-end exception tests. Add
behavioral regression coverage with new functionality instead of counting the
hello-world tests as evidence for it.

## Review Before Handoff

- Compare implementation against its owning child manifest and neighboring tests,
  not only the intended architecture document.
- For routing/template changes, check the shared `Beamlet.Web` setup and the CSP
  regression together. For failures/state changes, consult the linked topic specs.
- Run applicable checks above; record what ran, failed, or was skipped and why.
  Keep dependency updates, generated assets, and unrelated scaffold cleanup out
  of a narrowly scoped change unless the task explicitly requires them.
