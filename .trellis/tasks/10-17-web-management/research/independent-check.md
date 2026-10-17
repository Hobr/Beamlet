# Independent management review

Recommendation: **no source blocker remains in the eight authored paths after the four low-severity repairs below; source engineering evidence for MA1–MA5 passes.** Browser/visual/keyboard/scroll/disconnect verification was **not performed** under the user's explicit instruction “暂不使用浏览器进行验证”, so this report does not claim that acceptance and does not mark child or parent acceptance, change task status, or synchronize shared specifications.

## Scope, inputs and preservation

Loaded the child `check.jsonl` and read every referenced file: `backend/index.md`, `directory-structure.md`, `agent-orchestration.md`, `database-guidelines.md`, `error-handling.md`, `operation-runtime.md`, `logging-guidelines.md`, `quality-guidelines.md`, `live-observation.md`, `web-host.md`, `web-workbench.md`, plus `10-17-beamlet-web/research/current-capabilities.md`. Read the child `prd.md`, `design.md`, `implement.md`, `research/implementation-handoff.md`, the parent `prd.md`/`design.md` (§6 and plan) and `implement.md`, and the prerequisite dispositions: `10-17-web-observation/research/{acceptance,independent-check}.md`, `10-17-web-presets/research/{acceptance,independent-check}.md`, `10-17-web-workbench/research/{acceptance,independent-check}.md` (browser-walkthrough/capability were read only as preserved, stopped research; nothing was resumed).

Reviewed actual working content of the eight authored paths against public source in `apps/beamlet_node` (`Cluster`, `Observation`), `apps/beamlet_runtime` (`Observation`, `Directory.handle_call(:observation)`), `apps/beamlet_agent` (`Ref`, id bounds), `apps/beamlet_web` (`Presets.describe/reset/resolve`, `Handles.fetch`, `OwnedCall.start/observe`, `ObservationComponents`, endpoint/session/router security) and the prerequisite sources present in the working tree. The HEAD diff also contains previously accepted observation/preset/workbench and parent-artifact content; **none of that is attributed to this child**.

Preservation: entry and final porcelain entry count were both **111**; 111 of them are staged (`git diff --cached --name-only` = 111) and exactly **3** are unstaged — the three files I edited, all inside the authored set. I performed no stage/unstage/reset/restore/checkout/commit/branch/archive/task-pointer/shared-spec operation, and did not touch `.trellis/spec/**` or other tasks' artifacts. I do **not** have an entry-time cached-diff hash (I did not snapshot it), so I claim only: no git write command was issued by me, the staged set size is unchanged, and my content changes are limited to the three paths below. Final staged binary diff SHA256: `09cb022beb7acbe1a14e267d4629c35ecffc09cf02fda17d6b3eff669eee62dc`; unstaged diff covers `management_live.ex`, `management_reads.ex`, `management_live_test.exs`.

## Findings repaired

All four are low severity: none changes MA1–MA5 intent, and none was a blocker.

1. **Target resolution used a raising pattern match and hid the real failure category** — `management_reads.ex:13` (original): `{:ok, target} = Cluster.authority(name, allowed)`. With the current `Cluster` contract this cannot fire (`Cluster.connected/1` validates the same allowlist first, so `authority/2` cannot fail for a name taken from it), and `OwnedCall.safe/1` would have swallowed a stray `MatchError` as `:unavailable`. The real consequence was the *status text*: every `{:error, _}` became “Unavailable / stale identity”, which is wrong for a nodes/presets read and hides `invalid_authority`. Consequence: an operator could not distinguish a misconfigured `allowed_nodes` (or a deadline) from a stale Agent handle. Remedy: `resolve/1` (`management_reads.ex:30`) reduces the allowlist through public `Cluster.authority/2` and returns `{:error, reason}` instead of raising; `ManagementLive` now renders action-specific, reason-labelled failure text (`management_live.ex:310–326`) while retaining the previous observation. Permanent regression: “invalid configured scope is an explicit failure that retains the last observation” plus the strengthened catalogue-failure assertion.

2. **Known-absent preset facts were rendered as unknown** — `management_live.ex` original preset block used `text(entry[:environment])` and `text(@data.default_authority)`. `Presets.reset/2` maps an absent preset environment to `nil`, which the creation form renders as “not required”; `default_authority: nil` is a valid catalogue with no default. The page therefore reported “Unknown / omitted”, i.e. unknown facts where the descriptor knows there are none — an MA2 “missing environment explicit”/creation-parity defect. Remedy: `environment(nil) -> "not required"` (`:307`), `labels([]) -> "none"` (`:303`), and `@data.default_authority || "none configured"` (`:283`). Permanent regression: the parity test asserts `Tools: none`, `Environment: not required`, and keeps the private-config/`binding`/`<form>` refutations.

3. **Management pages had no escaping evidence (MA4 sanitization)** — node/preset text is untrusted source text (report capabilities/pool names, catalogue titles/descriptions). Added a component-level regression rendering `"<script>alert(1)</script>"` and `"<b>pool</b>"` through `runtime_reports/1` and asserting the escaped HTML plus `Environments: none`; also added `refute render(view) =~ "#PID"` to the diagnostics and invalid-scope tests, so no PID/Ref structure leak can regress silently.

4. **No permanent evidence for allowlist-shape robustness** — duplicate entries and a local-inclusive allowlist were tolerated by inspection but untested. Added “duplicate and local-inclusive allowlists resolve without duplication or a second read”: `["missing@localhost", "missing@localhost"]` yields `[node(), :missing@localhost]`, `excluded == []`, and a single aggregate covering exactly 2 targets; `allowed_nodes: [Atom.to_string(node())]` yields `targets == [node()]` with `excluded == []` (no duplicate local read, no 33rd phantom entry).

Review-test authoring error, preserved rather than hidden: `/tmp/mgmt-check/focused-ordinary-after.log` (14/15, exit 2) is **my** wrong assertion — I asserted a `Compatible environment references` line while that fixture catalogue defines **zero tools**, so no tool section exists. I removed that assertion; no product behavior changed. The final focused log is `focused-ordinary-after2.log` (15/15, exit 0).

Changed paths (all inside the authored set):

- `apps/beamlet_web/lib/beamlet_web/live/management_reads.ex`
- `apps/beamlet_web/lib/beamlet_web/live/management_live.ex`
- `apps/beamlet_web/test/beamlet_web/management_live_test.exs`

## MA evidence and qualification

| Area | Independent result |
| --- | --- |
| MA1 | `node_results/1` distinguishes **local** (`target == node()` → “local (no distribution required)”), **connected at read entry** (`target in @data.connected`), and **disconnected** from the same trusted scope list; per-target configured status, configured roles (`labels/1`), registration readiness (`services/1` over routes/runtime/authority/executor), and a separate Runtime block with `source`, coverage (`complete`/`partial`), per-report `status` (`not_reported`/`fresh`/`stale`), **source receipt age** (`age_ms`, `:unknown` → “Unknown”), `ready`/`execution_ready`, capabilities, environment IDs and `available` pool quantities only. The page states registered readiness is not provider health, missing/stale reports do not prove death, totals/utilization are unknown and available is advisory. Freshness age comes only from the source-reported `age_ms`; no remote monotonic timestamps are subtracted anywhere (`age/1` accepts an integer only). Actual authority-only/executor-only/combined/unconfigured/service-loss trees execute through public `Beamlet.Node`; the named test drives real remote facts, a real 5 s source timeout and a real disconnect. Missing/stale/fresh rendering uses explicitly named public-shape fixtures — it is rendering evidence, not evidence that the core admits reports (the core tests own that). |
| MA2 | Presets content comes from exactly `Presets.describe/0` — the same call creation uses (`workbench_live.ex:354`); parity with the live public descriptors is asserted. Rendered: labels/descriptions, default model and default authority references, preset tool/environment references, tool environment compatibility (“Empty means no environment required”), and the source category (“trusted startup catalogue”, “No provider probes; online availability unknown”). `describe/2` takes only `[:title, :description, :model, :tools, :environment]` / `[:title, :description, :environments]`, so `binding`/`route`/`descriptor`/`value`/`target` never reach the DOM; tests refute the private config sentinel, `binding`, and any `<form>`. The only events are `refresh` and an ignoring catch-all, so there is no mutation path. |
| MA3 | Diagnostics resolves the **exact opaque handle** through `Handles.fetch/1` (32-byte binary, re-lookup, `ref == expected`, else `stale_handle`), subscribes only through `OwnedCall.observe/4` (the repaired observer) and renders the shared `.activities` component plus retained entries. Turn/entry/activity/operation/attempt identities are rendered as opaque SHA-256 labels via `turn/1`; the `activity` query parameter is compared against computed labels only — it is never rendered, atomized or used to reconstruct a timeline, and a stale key yields “Activity identity stale / unknown; no historical reconstruction.” No `:sys`, `:erlang`, `Process.info`, `inspect/1`, `apply/`, `String.to_atom` or `:rpc` appears in either management module. Same-ID replacement and invalid handles degrade explicitly; the real Agent survives the page, and `Agent.snapshot(ref)` still reports `:idle` after forged `input`/`stop`/`close`/`inspect-child` hooks. |
| MA4 | Only `refresh` reads; every other event (including the shared component's `inspect-child` button, which is rendered disabled here) is ignored by `handle_event(_, _, s)`. Routes add exactly the three read-only LiveViews inside the existing `:browser` pipeline; no RPC/terminal/restart/connect/role/config/recovery route or handler exists. A global trace of `Agent.start/2`, `Agent.input/2`, `Agent.stop/1`, `Agent.close/1`, `Runtime.submit/2`, `Node.connect/1` records zero calls across a nodes-page mount, refresh and forged controls. HEEx escapes all interpolated source text (new regression); CSP nonce + `default-src 'self'`/`object-src 'none'`/`frame-ancestors 'self'`/`form-action 'self'`, `protect_from_forgery`, socket origin configuration, production `SECRET_KEY_BASE` fail-fast, session options and the compile-time `:dev_routes` LiveDashboard/LiveDebugger gates are unchanged by this delivery. No PID/Ref/inspect/secret/root sentinel appears in rendered output or logs inspected. |
| MA5 | One read is admitted while `pending` (repeated refreshes do not dispatch), generation fencing drops results from other generations/actions, results are applied only for the current Ref, and `OwnedCall` enforces a 12 s outer page deadline with owner monitoring and observed linked-worker retirement. Node reads inherit the public 32-target/8-worker/5 s/1 MiB ceiling; a 32-entry allowlist plus the explicit local VM becomes 33 visible scope entries where the excess target is shown as “Scope partial: … not read (32-target limit including explicit local). Facts unknown.” rather than being silently truncated or read twice. Failures keep the last observation with a labelled Web receipt time and an explicit reason; observation loss clears nothing and says so. No storage, Ecto, exporter, collector or trace database is added; audit of the delivery shows only read paths. |

## Read-bound and resolution audit (answers to the specific questions)

- **`Cluster.authority/2` pattern-match failure** — unreachable as written (`connected/1` pre-validates the identical allowlist and `authority/2` only additionally requires `name in allowed`); if the contracts ever diverged it would be caught by `OwnedCall.safe/1` as `:unavailable`, i.e. silently mislabelled. Now returns `{:error, reason}` and is rendered as `Node scope read unavailable: invalid_authority` with the last observation retained.
- **Invalid allowlist** — `Cluster.connected/1` returns `{:error, :invalid_authority}`; `nodes/0` propagates it (no crash, no partial page), and the page distinguishes it from a deadline. Verified by a real LiveView refresh plus the last observation still on screen.
- **Duplicate allowlist** — tolerated end to end: `connected/1`/`authority/2` accept repeats, `Enum.uniq/1` collapses them, and `Node.observe/1`'s distinctness rule is satisfied. Regression asserts 2 targets → one aggregate of size 2, `excluded == []`.
- **Local already allowlisted** — `Enum.uniq([node() | resolved])` collapses the duplicate, so the scope stays at 32 and no target is excluded. Regression asserts `targets == [node()]`, `excluded == []`.
- **Configured-but-disconnected authority** — retained in `targets` (rendered “disconnected”) and reported by `Node.observe/1` as `failures[target] = :unavailable` with `complete: false` (“partial / unknown”), so it is explicit rather than omitted. Exercised by both the ordinary unconfigured-local test and the named peer test after a real `Node.disconnect/1`.
- **Local pushes scope past 32** — explicit unread entry (above), no second read. Advisory: which target is dropped is the last configured name; if an operator values a specific peer it must appear earlier. This is visible, bounded and documented on the page, so it is a limitation, not a silent omission.
- **Single in-flight page read / generation / ref fencing / owner cleanup** — pending lock; `{:owned, {:management, g}, _}` matches only the current generation; observation messages match `{generation, ref}`; owner DOWN kills the worker/sink; unmount (`GenServer.stop`) is asserted to DOWN the actual `OwnedCall.start` guardian while the source is still suspended, and the primitive is separately asserted to DOWN its caller before the source resumes.
- **Zero business/connection/provider side effects from navigation or refresh** — refresh is the only reading event; arrival on an admin route mounts the same traced read path; `Cluster.connected/1` and `Node.observe/1` never connect or submit work; `Presets.describe/0` and `Handles.fetch/1` are pure reads. Trace test covers mount + refresh + forged events.

## Verification (this review, independent of the implementer's logs)

**The implementer's retained artifacts were not present in this environment.** `/tmp/management-final`, `/tmp/management-gates`, `/tmp/management-focused-*.log`, `/tmp/management-before.{status,index}` and `/tmp/management-inventory.json` do not exist here (the only `/tmp` files matching a "management" prefix belong to an unrelated project). I could therefore **not** inspect the claimed `exit0` artifacts, the Web-55/5 and umbrella-278/34 logs, the named-25 log, or the original-failure logs; those claims remain unverified by me. I did not recreate them by guessing; instead I ran my own gates on the actual working tree, with logs/exits under `/tmp/mgmt-check/`.

Installed toolchain: Elixir 1.20.4 / OTP 29, `ERL_FLAGS='+S 2:2'`. Every command below exited 0 unless stated.

| Command | Result (this review) |
| --- | --- |
| `mix test apps/beamlet_web/test/beamlet_web/management_live_test.exs --seed 631927` **before** repairs | **12 passed** (matches the handoff's focused count) |
| same file, **after** repairs | **15 passed** (12 + 3 new regressions) |
| `mix test apps/beamlet_web/test --seed 631927` | **58 ordinary passed / 5 distributed excluded** (handoff claimed 55/5 pre-review; +3 = my added tests) |
| `mix test --seed 631927` (umbrella) | **281 ordinary passed / 34 excluded** — Harness 35, Actions 28, Runtime 43/6, Agent 26, Node 68/20, Daemon 5/2, CLI 18/1, Web 58/5 |
| `elixir --sname [owned] --cookie [private hex] -S mix test apps/beamlet_web/test apps/beamlet_node/test --only distributed --seed 631927` | **25 actual named passed** — Node 20/68 excluded, Web 5/58 excluded (includes the management named peer test: real connected `authority, executor`, real 5 s source timeout, real disconnect). Cookie generated privately, never printed, deleted after; `epmd -names` shows no registered nodes afterwards. |
| `mix format --check-formatted` | passed |
| `mix compile --warnings-as-errors` (dev and `MIX_ENV=test`) | both passed |
| `mix credo --strict` | 136 files, **1197** mods/funs, no issues (handoff: 1185 pre-review) |
| `mix sobelow --exit` | scan complete, no findings |
| `mix dialyzer --no-check` | **existing dev PLT reused (`check_plt: false`, no refresh)**; 0 errors, 0 skipped, 0 unnecessary skips |
| `git diff --check HEAD -- [authored paths]` | passed (also after formatting my edits) |

Final-vs-earlier distinction: the only earlier artefacts are mine — `focused-ordinary.log` 12/0 (pre-repair baseline), `focused-ordinary-after.log` 14/15 exit 2 (my bad assertion, preserved), `focused-ordinary-after2.log` 15/0, then the 58/5, 25-named and 281/34 gates. No earlier umbrella or named number is inferred from a different candidate. I did not rebuild assets: this review added no JS/HEEx class or static resource (edits are text/attribute content and Elixir only), so the prerequisite asset build/deploy evidence was not re-exercised.

## Browser deferral (explicit)

Per “暂不使用浏览器进行验证”: **no browser, geckodriver/chromedriver session, browser endpoint fixture, screenshot, or visual/keyboard/scroll/disconnect journey was launched.** All LiveView evidence here is in-process `Phoenix.LiveViewTest`/`ConnCase` HTML, which is not a browser journey. Desktop/small-screen navigation, focus order, scroll-follow and reconnect behaviour of the three admin pages remain **unperformed**. The stopped workbench browser research artifacts were not resumed or investigated.

## Residual risks

- Visual/interaction acceptance for management navigation and small screens is unperformed (user-deferred), as is any claim that navigation “looks” correct.
- Same-host named peers prove neither physical multi-host behaviour nor paid-provider health; registered readiness is registration presence only and available capacity is advisory.
- 33-entry scope drops the last configured target as an explicit unknown; operators must order `allowed_nodes` with priority in mind.
- Admin pages do not set `page_title`, so the document title stays the layout default; they do carry distinct `h1` headings. Cosmetic/advisory, consistent with the accepted workbench, not addressed here.
- A workbench *error message* is not itself a link; diagnostics entry is the page-level “Current Agent diagnostics” link and the per-activity “Inspect activity diagnostics” links. Reading M3 as “reachable from the workspace” this is satisfied; a per-error deep link is not implemented.
- `ManagementReads` reads `:beamlet_web, :host, :allowed_nodes` from application env (the same pattern as `WorkbenchCommands`); it re-validates on every read and fails explicitly rather than trusting a stale validated copy if the env changed at runtime.
- Tool/provider/source content can itself echo sensitive text; projections avoid known private fields but are not a universal secret-erasure boundary.
- LSP analysis was unavailable/timed out in this environment and one reported “ConnCase not loaded” blocker was a false positive (`ConnCase` lives in `test/support` via `elixirc_paths(:test)`); language-server coverage is **inconclusive**. Compilation, ExUnit, Credo, Sobelow and Dialyzer are the authoritative evidence.
- The historical Runtime composition 100 ms failure remains unknown/nonblocking by prior disposition; it did not recur in my runs, and I introduced no timeout inflation, weaker success assertion or business retry. If it recurs, preserve correlated outcome/admission/worker timing facts.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Eight authored paths reviewed against public source and MA1–MA5; four low-severity defects repaired with permanent regressions; independent gates: focused 15/0, Web 58/5 excluded, umbrella 281/34 excluded, named 25 actual, format/compile/credo/sobelow/existing-PLT dialyzer all exit 0; browser unperformed by explicit user instruction; residual risks enumerated."
    }
  ],
  "changedFiles": [
    "apps/beamlet_web/lib/beamlet_web/live/management_reads.ex",
    "apps/beamlet_web/lib/beamlet_web/live/management_live.ex",
    "apps/beamlet_web/test/beamlet_web/management_live_test.exs"
  ],
  "testsAddedOrUpdated": [
    "apps/beamlet_web/test/beamlet_web/management_live_test.exs"
  ],
  "commandsRun": [
    {
      "command": "mix test apps/beamlet_web/test/beamlet_web/management_live_test.exs --seed 631927",
      "result": "passed",
      "summary": "12 passed before repairs; 15 passed after repairs"
    },
    {
      "command": "mix test apps/beamlet_web/test --seed 631927",
      "result": "passed",
      "summary": "58 passed, 5 distributed excluded"
    },
    {
      "command": "mix test --seed 631927",
      "result": "passed",
      "summary": "281 ordinary passed, 34 excluded across umbrella"
    },
    {
      "command": "named Web+Node --only distributed --seed 631927 (private sname/cookie)",
      "result": "passed",
      "summary": "25 actual named passed (Node 20/68, Web 5/58 excluded)"
    },
    {
      "command": "mix format --check-formatted",
      "result": "passed",
      "summary": "exit 0"
    },
    {
      "command": "mix compile --warnings-as-errors (dev and test)",
      "result": "passed",
      "summary": "both exit 0"
    },
    {
      "command": "mix credo --strict",
      "result": "passed",
      "summary": "136 files, 1197 mods/funs, no issues"
    },
    {
      "command": "mix sobelow --exit",
      "result": "passed",
      "summary": "scan complete, no findings"
    },
    {
      "command": "mix dialyzer --no-check",
      "result": "passed",
      "summary": "existing PLT, 0 errors/0 skipped/0 unnecessary skips, no refresh"
    },
    {
      "command": "git diff --check HEAD -- [authored paths]",
      "result": "passed",
      "summary": "exit 0 after formatting"
    }
  ],
  "validationOutput": [
    "Logs/exits: /tmp/mgmt-check/{focused-ordinary,focused-ordinary-after,focused-ordinary-after2,web,all,named,format,compile,compile-test,credo,sobelow,dialyzer}.log",
    "Implementer artifacts /tmp/management-final, /tmp/management-gates, /tmp/management-focused-*.log and /tmp/management-before.* were absent in this environment: their exit0/55-5/278-34/25 claims could not be inspected and are reported as unverified",
    "No-browser confirmation: no driver, fixture, screenshot or visual journey launched; only in-process LiveViewTest/ConnCase HTML"
  ],
  "residualRisks": [
    "Browser/visual/keyboard/scroll/disconnect verification unperformed under explicit user deferral",
    "Same-host named peers do not prove physical multi-host or paid-provider behaviour",
    "32-remote allowlist plus explicit local exposes the 33rd target as unread/unknown (visible limitation, not silent truncation)",
    "Implementer's retained final/original-failure artifacts were not present, so their counts remain unverified here",
    "LSP unavailable/timeout is inconclusive; compilation/ExUnit/Credo/Sobelow/Dialyzer are the evidence",
    "Historical Runtime composition 100ms failure remains unknown/nonblocking; did not recur",
    "Admin pages share the layout default document title (no page_title assign)",
    "Workbench error text itself has no per-error diagnostics deep link; entry is the page-level and per-activity links"
  ],
  "noStagedFiles": false,
  "diffSummary": "Review repairs only: explicit allowlist resolution returning {:error, reason}; action/reason-labelled failure status with retained last observation; preset known-absent environment/default-authority/empty-list rendered explicitly instead of unknown; plus three permanent regressions (escaping, duplicate/local-inclusive allowlist, invalid-scope explicit failure).",
  "reviewFindings": [
    "low: management_reads.ex:13 - raising {:ok, target} pattern match unreachable today but would be swallowed as :unavailable and every error rendered as 'stale identity'; replaced with explicit resolve/1 + action-specific reason text",
    "low: management_live.ex preset block - known-absent environment/default authority rendered as 'Unknown / omitted', diverging from creation's 'not required' and MA2 explicit-missing; rendered explicitly",
    "low: management_live_test.exs - missing escaping evidence for untrusted report/catalogue text and no #PID leak assertion; added",
    "low: management_live_test.exs - duplicate and local-inclusive allowlist dedup untested; added",
    "advisory: ManagementLive does not set page_title; workbench error text has no per-error diagnostics link; 33rd configured target is explicitly unread",
    "no blocker identified in the eight authored paths"
  ],
  "manualNotes": "I was the exclusive source writer for this review and changed only three of the eight authored paths; no agents spawned, no stage/unstage/reset/commit/branch/archive/task-pointer or shared-spec edit. The index was not modified by me and external staged content was preserved (111 staged entries before and after; 3 unstaged files are mine). The one failing log (focused-ordinary-after.log, 14/15) is my own bad assertion about a tools section absent from the fixture, preserved rather than overwritten; no product change followed from it. Parent retains independent acceptance, broader integration and shared-spec synchronization."
}
```
