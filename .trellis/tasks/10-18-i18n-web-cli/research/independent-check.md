# Independent check: Web/CLI Gettext i18n (10-18-i18n-web-cli)

Reviewer: `trellis-check` (independent, exclusive source writer for this review)
Tree: `/mnt/data/Project/Beamlet`, branch `dev`, 34 uncommitted delivery paths + this review's one fix.
Task status: `in_progress` (this review does **not** mark task or parent acceptance).

## 0. Context actually loaded

| Source | Status |
| --- | --- |
| `check.jsonl` (7 spec entries) | read; all 7 spec files opened, 2 of them read as full diffs (`directory-structure.md`, `quality-guidelines.md`), 5 skimmed for the clauses they own (`web-workbench`, `web-management`, `web-host`, `backend-release`, `error-handling`) |
| `prd.md`, `design.md`, `implement.md` | read in full |
| `research/implementation-handoff.md` | **absent** — `.trellis/tasks/10-18-i18n-web-cli/` contains only `prd.md`, `design.md`, `implement.md`, `implement.jsonl`, `check.jsonl`, `task.json`. No `research/` directory exists. Treated as never-written, not as evidence. Nothing in this report relies on it. |
| `/tmp/i18n-gates/*` retained artifacts | present (13 `.exit` files all `exit=0`), but they are **historical and unattributed to a tree state**; they contain no `check-release.sh` run (the `release-*.log` files are only `mix release` builds). Counts below are my own runs on the current tree; the historical numbers are quoted once, only to show they matched. |

## 1. Authoritative gates on the current tree

All commands run by me, in `/mnt/data/Project/Beamlet`, on the current working tree. Logs in `/tmp/check-i18n/`.

| # | Command | Result | Evidence |
| --- | --- | --- | --- |
| 1 | `mix format --check-formatted` | **pass** (exit 0) | also forced over the new files explicitly: `mix format --check-formatted apps/beamlet_i18n/lib/**/*.ex apps/beamlet_i18n/test/**/*.exs apps/beamlet_i18n/mix.exs apps/beamlet_cli/lib/beamlet/cli/{locale,gettext}.ex apps/beamlet_web/lib/beamlet_web/locale.ex` → exit 0 |
| 2 | `mix compile --warnings-as-errors` | **pass** (exit 0) | plus `mix compile --force --warnings-as-errors` → exit 0, zero warning lines (the non-forced run is a no-op, so I forced it) |
| 3 | `mix test apps/beamlet_i18n/test` | **pass** | `15 passed` |
| 4 | `mix test apps/beamlet_web/test` | **pass** | `73 passed, 5 excluded` (`ExUnit.start(exclude: [:distributed])`, pre-existing) |
| 5 | `mix test apps/beamlet_cli/test` | **pass** | `25 passed, 1 excluded` |
| 6 | `mix test --seed 631927` (full umbrella) | **pass** | 9 apps, **318 passed / 34 excluded / 0 failures** (harness 35, actions 28, i18n 15, runtime 43+6, agent 26, node 68+20, daemon 5+2, cli 25+1, web 73+5). Historical `/tmp/i18n-gates/full-test2.log` was also 318/34 — identical, so the counts did not drift. |
| 7 | `mix credo --strict` | **pass** | 150 source files, 1326 mods/funs, "found no issues" |
| 8 | `mix sobelow` (root alias → `--root apps/beamlet_web --private`) | **pass** | `... SCAN COMPLETE ...`, exit 0 |
| 9 | `mix dialyzer --no-check` | **pass** | `Total errors: 0, Skipped: 0, Unnecessary Skips: 0`, existing dev PLT reused (`check_plt: false`, no refresh) |
| 10 | `mix gettext.extract --check-up-to-date` (repo root) | **pass** (exit 0) | emits 3 upstream warnings "backend `Beamlet.I18n`/`Beamlet.CLI.Gettext`/`Beamlet.Web.Gettext` has the same :priv directory as itself" — an artifact of gettext 1.0.2 `@recursive` extraction double-registering backends; harmless, no POT/PO was rewritten (tree status unchanged) |
| 11 | `git diff --check` | **pass** (exit 0) | |
| 12 | `mix.lock` unchanged | **pass** | `git diff --exit-code mix.lock` → 0; gettext 1.0.2 + expo already resolved at HEAD |
| 13 | daemon `.rel` closure | **pass** | `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite`; `_build/backend/prod/rel/beamlet_daemon/releases/0.1.0/beamlet_daemon.rel` lists kernel/stdlib/elixir/sasl/iex/asn1/beamlet_{daemon,actions,agent,harness,node,runtime}/compiler/crypto/finch/hpax/jason/logger/mime/mint/nimble_options/nimble_pool/public_key/req/ssl/telemetry — **no `beamlet_i18n`, no `gettext`, no `expo`**; `ls .../lib \| grep -Ei 'i18n\|gettext\|expo'` → none |
| 14 | `scripts/deployment/check-release.sh` (full, both rebuilt releases) | **pass** (exit 0) twice | first run unmodified; second run after my fix (finding F1). Copied-manifest hash identical in both runs (`1817cd87bff8…4f911`), so both runs validated the same artifact. Output: `copied daemon closure passed`, three named-daemon modes, bootstrap+Gateway turn, `12 invalid runtime/config cases rejected`, `Copied CLI closure and three independent foreground stdin sessions passed` |
| 15 | shipped CLI, `BEAMLET_LANG` unset | **pass** | release `beamlet_cli start` with `help`/`bogus` on stdin → Chinese help body + `错误：无效命令`, exit 0 |
| 16 | shipped CLI, `BEAMLET_LANG=en` | **pass** | identical byte layout and text to the pre-change English help (header `commands / policy`, same 10 rows) + `error: invalid_command` |
| 17 | Web, session-less GET (real endpoint) | **pass** | `/`, `/agents/new`, `/admin/nodes`, `/admin/presets`, `/admin/diagnostics` → 200, `<html lang="zh-CN">`, h1 `你想做什么？` / `只读 节点`, status `连接中` / `未知 / 未观测`, buttons `立即发现` / `刷新观测`; `/?locale=en` → h1 `What would you like to do?`, `<html lang="en">` |
| 18 | ASCII-copy sweep of rendered Chinese pages | **pass** | only `Agent`, `Beamlet`, `English` (switcher label, by design), `Phoenix`/`Framework` (scaffold `<title>`); zero hits for `nil`, `%{`, `{{`, `#Function`, `Elixir.`, `true`, `false` |

Not run / not claimed: no browser walkthrough, no physical deployment, no paid provider, no `pre-commit run --all-files`, no `mix assets.build`.

## 2. Requirement-by-requirement verdicts

### R1 — shared `beamlet_i18n` leaf app — PASS

- `apps/beamlet_i18n` exists with `mix.exs` (`app: :beamlet_i18n`, deps `[{:gettext, "~> 1.0"}]` only, `extra_applications: [:logger]`), `.formatter.exs`, `lib/beamlet/i18n.ex`, `lib/beamlet/i18n/{locale,catalogue,vocabulary}.ex`, `priv/gettext/{default,errors}.pot`, `priv/gettext/{en,zh_CN}/LC_MESSAGES/{default,errors}.po`, tests.
- Leaf, proven by `mix deps.tree`: only `beamlet_cli` and `beamlet_web` list `beamlet_i18n`; `beamlet_i18n` depends on gettext (+expo transitively) and nothing else. `beamlet_daemon → beamlet_node → {actions, agent, harness, runtime}` has no i18n/gettext edge, and the built `.rel` (gate 13) confirms it.
- `Beamlet.I18n` = `use Gettext.Backend, otp_app: :beamlet_i18n` plus explicit **runtime** `gettext/1,2` / `dgettext/2,3` wrappers; documented that only `Catalogue` uses the macro set. Sound: it is why Web/CLI can look up shared msgids without importing a second backend.
- `Beamlet.I18n.Locale` is the single canonicaliser/default: `normalize/1` (`zh`,`zh-cn`,`zh_cn`,`cn`→`zh_CN`; `en`,`en-us`,`en_US`→`en`; else `nil`), `default/0` = `"zh_CN"`, `canonicalize/1`, `put/1`, `options/0`, `html_lang/1`. `Beamlet.CLI.Locale.normalize/1` delegates; `Beamlet.Web.Locale` never re-implements it. No duplicate normalize implementation exists (`grep` for `def normalize` → only `Beamlet.I18n.Locale`).
- `Beamlet.I18n.Vocabulary` translates only declared words and passes everything else through unchanged.
- `Beamlet.I18n.Catalogue` is the sole declaration point: every `#:` reference in both shared POTs resolves to `lib/beamlet/i18n/catalogue.ex` and to no other file.
- `mix.lock` unchanged; `mix.exs` only adds `:beamlet_i18n` to `backend_apps()` (the `BEAMLET_BACKEND_BUILD=1` list), which is required because `beamlet_cli` is in that list and now depends on it; it does not add the app to any release closure.
- Hygiene: `apps/beamlet_i18n/.expert/` build cache is gitignored (`.gitignore:85`); untracked file list is source/tests/catalogues only.

### R2 — five catalogues disjoint, zh complete, en covering, literals resolvable, real files — PASS (with one guard observation, F2)

My own parse (script over the files, independent of the project's test helper):

| Catalogue | POT msgids | zh_CN entries | zh empty msgstr | en entries | en empty msgstr | missing/extra |
| --- | --- | --- | --- | --- | --- | --- |
| `shared/default` (`Beamlet.I18n`) | 20 | 20 | 0 | 20 | 20 | 0/0 |
| `shared/errors` | 22 | 22 | 0 | 22 | 22 | 0/0 |
| `web/default` | 164 | 164 | 0 | 164 | 164 | 0/0 |
| `web/errors` | **0** | 0 | 0 | 0 | 0 | 0/0 |
| `cli/default` | 23 | 23 | 0 | 23 | 23 | 0/0 |

- Pairwise disjointness of the five POT msgid sets: **no overlap** (verified over all 10 pairs myself).
- zh coverage: every msgid in every owning catalogue has a non-empty zh_CN msgstr (229 msgids total across the four non-empty catalogues). Zero zh msgstr identical to its msgid; zero fuzzy flags; zero obsolete `#~` entries.
- en coverage: same msgid sets; empty msgstr is the documented design (msgid is English → Gettext falls back to it).
- Placeholder parity msgid↔msgstr: **0 mismatches** across all 458 non-empty pairs, so no `%{…}` can leak into rendered copy.
- `Beamlet.I18n.gettext`/`dgettext` literals in `apps/beamlet_web/lib` + `apps/beamlet_cli/lib`: **18 `dgettext("errors", …)` literals, all present in the shared `errors` catalogue** (alias_exists, alias_limit, busy, event_limit, invalid_alias, invalid_authority, invalid_command, invalid_configuration, invalid_watch_options, limit, not_authority, not_found, request_failed, stale_agent, timeout, timeout_or_loss, unavailable, unknown_alias). **0 `gettext("…")` literals** — shared default-domain words are reached through `Vocabulary.status/1` with a runtime variable, never a literal.
- Tests read the shipped files, not fixtures: `Beamlet.I18n.CatalogueFiles` resolves `Application.app_dir(app, "priv/gettext")`, and `_build/test/lib/{beamlet_i18n,beamlet_web,beamlet_cli}/priv` are **symlinks** into `apps/*/priv` (verified with `ls -la`). The source scan walks the real `apps/*/lib` via a root found from `__DIR__`.
- Non-vacuity: `refute all == []` in `catalogue_test.exs` is satisfied by the 18 dgettext hits, and the separate "shared vocabulary is declared once" test proves the 20 statuses and 22 reasons are present in their shared catalogues.

### R3 — Chinese really is the default, `en` really works, no term leaks — PASS

- Session-less real HTTP GETs (gate 17) prove the default for `/`, `/agents/new` and all three admin pages, including `<html lang="zh-CN">` from the root layout.
- The workspace page (`/agents/:handle`) is proven Chinese by `apps/beamlet_web/test/beamlet_web/i18n_test.exs` ("the Agent workspace is Chinese": `Agent 工作区`, `初始输入：未提交 · 导航：未请求`, `当前并发活动`, `refute "Agent workspace"/"Not submitted"`) with an explicit `zh_CN` session rather than a session-less request; the resolution path is identical (the `Beamlet.Web.Locale` plug covers the whole `:browser` pipeline) and `Locale.resolve(nil, nil) == "zh_CN"` is asserted, so the residual gap is only "not re-proven session-lessly".
- CLI default proven at three levels: `Locale.locale()` → `"zh_CN"` with config/env absent; `Renderer` output; and the **shipped release binary** with `BEAMLET_LANG` unset → Chinese help + `错误：无效命令` (gate 15).
- Explicit `en` end-to-end: Web `?locale=en` → English heading + `lang="en"` (gate 17); CLI `BEAMLET_LANG=en` on the release binary → byte-compatible English (gate 16).
- Session persistence and switch-back: `?locale=en` → session `"locale" = "en"` → next page without query stays English → `?locale=zh_CN` → back to Chinese and persists (test + my probe of the session write path in `persist_param/2`).
- Unknown locale: `?locale=klingon` with no session → Chinese, session stays `nil` (never persisted); with an existing `en` session, `?locale=klingon` keeps `en` instead of resetting — both covered.
- No `nil`/atom/function/raw-term leak: ASCII sweep of all five Chinese pages found only brand/technical tokens; `text/1` maps atoms through `Vocabulary.status/1` (unknown → `Atom.to_string/1`, i.e. the previous behaviour) and `turn/1`, `age/1`, `services/1`, `bounded/2` keep their existing bounded projection. CLI keeps its allowlist: an unexpected reason still renders `request_failed` and a `{:secret, "sentinel"}` term is proven not to leak.

### R4 — locale precedence, and the deliberate `BEAMLET_LANG` reorder — PASS (deviation judged justified; one artifact-doc drift, F4)

- Web, as implemented: valid `?locale=` → session `"locale"` → `config :beamlet_web, :default_locale` → `zh_CN`. Matches PRD/design exactly. `persist_param/2` only writes a **canonical** value, so garbage never reaches the session.
- CLI, as implemented: `config :beamlet_cli, :locale` → `BEAMLET_LANG` → `config :beamlet_cli, :default_locale` → `zh_CN`.
- **Judgement on the deviation: justified, documented and tested — do not revert.**
  - The design's order (`:default_locale` before the env var) is unreachable in practice because `config/config.exs` now *unconditionally* sets `config :beamlet_cli, :default_locale, "zh_CN"`. With the design's order, `BEAMLET_LANG` could never win, i.e. the feature's only operator-level switch would be dead. The reorder is the minimal fix and keeps every documented promise ("absent config still shows Chinese" is carried by `Shared.default()`).
  - Documented in three places that agree verbatim on the order and on the reason: `Beamlet.CLI.Locale` moduledoc (items 1–4 plus an explicit "`:default_locale` deliberately ranks *below* `BEAMLET_LANG`" paragraph), `scripts/deployment/README.md` §"Terminal language", and `apps/beamlet_cli/WORKBENCH.md`-sibling doc `HOST.md` (which correctly states the Web side and points at WORKBENCH.md#language).
  - Tested both ways: `i18n_test.exs` "trusted configuration wins over BEAMLET_LANG" asserts all four rungs, including the explicit `:default_locale="zh_CN"` + `BEAMLET_LANG=en` → `en` case and the reverse, and "unusable values are skipped instead of hiding a usable one" proves a typo falls through rather than disabling translation.
  - Security posture unchanged: `BEAMLET_LANG` is operator environment (same trust class as config), and the `:locale` key is explicitly **not** part of the `BEAMLET_CONFIG` host schema (`enabled`/`allowed_nodes` only), so a trusted config file cannot smuggle it in.
- Consequence of the deviation that I verified separately: `config :beamlet_cli, :default_locale` in the app env would otherwise have made `Beamlet.CLI.configuration/1` return `{:error, :invalid_configuration}` at application start (it rejects unknown keys). `Beamlet.CLI.Application.start/2` now passes `Keyword.take(Application.get_all_env(:beamlet_cli), @host_keys)` with `@host_keys = [:enabled, :allowed_nodes]`. Without this the release could not boot; with it, the shipped release boots (gate 15/16) and the strict schema validation is still intact on the `BEAMLET_CONFIG` path in `config/cli_runtime.exs` (which still calls `Beamlet.CLI.configuration/1` with the raw settings). See F3 for the one thing this trades away.

### R5 — no behaviour regression — PASS

- CLI English bytes: the only copy-preserving change is `to_string(status)` → `Vocabulary.status(status)`, which is identity for the English locale (msgid fallback) and identity for any non-vocabulary atom; `"error: #{safe}"` → `gettext("error: %{reason}", …)` renders `error: timeout` identically; the 10 help lines, the `(none)` cell, and the discovery/status/node headers are byte-identical (compared against `git diff` of the pre-change strings and against the release binary in gate 16).
- Table shape: column order/count and `max_width: :infinity` / `max_column_widths: 512` / `padding_x: 1` unchanged; only header text differs in zh. The existing bound assertion (`String.length(text) < 16_384`) still holds (zh adds a few characters); the Ucwidth display-bounds test is untouched and still asserts `Owl.Data.length("中国") == 4`.
- Command grammar/exit codes: `Command.parse/1`, `Session.execute/3`, `Runner.loop/2` untouched except `Locale.put()` inserted once *before* the read loop; `read_line/1` untouched; exit codes 0/1 identical and re-proven by `check-release.sh` (`invalid.returncode == 1`, three sessions `returncode == 0`).
- Web: `phx-click`/`phx-change`/`phx-submit` names, form field names, ids (`#refresh`, `#agent-search`) are unchanged (diff scan); state machine functions changed only in that they now assign translated **strings** instead of English literals. CSP/CSRF: `router.ex` changed only by inserting `plug Beamlet.Web.Locale` after `:fetch_session` (required, since the plug calls `put_session`); the CSP plug + nonce and `protect_from_forgery` are untouched, and `mix sobelow`/`check-release.sh`+the web tests pass. Error pages: `ErrorHTML`/`ErrorJSON` and their tests untouched (`"Not Found"`, `"Internal Server Error"`), and PRD explicitly scopes those out.
- Existing Web/CLI test *files* are unchanged except `test/support/conn_case.ex` (adds the explicit English test session) and a `setup/1` block added to `session_test.exs` (assertions untouched). So the deterministic journey/management/workbench suites still assert what they asserted before.
- `check-cli-release.py`: the only change is `BEAMLET_LANG="en"` pinned into three env maps. Every assertion is byte-for-byte unchanged (`assert "error:" not in output`, `b'error: invalid_command' in invalid.stdout`, `assert invalid.returncode == 1`, pty `output.count(b'pty-ok') >= 2`). This **preserves** the assertions (without the pin they would now fail because the shipped default became Chinese) — nothing was weakened or deleted. Residual: the copied-release gate now only exercises English; Chinese at release level is covered by the CLI unit tests and by my gate 15.

### R6 — the two acknowledged gaps — see §5 for the judgements.

### R7 — no new persistence — PASS

- No database/ecto (`grep ecto apps/beamlet_web/mix.exs` → none), no schema, no browser storage added (`localStorage` only in the pre-existing theme `setTheme` script in `root.html.heex`), no new cookie: the locale rides the already-signed session via `put_session`.
- Locale is per-request (plug, next to `:fetch_session`) and per-LiveView-process (`on_mount` + `put`), so concurrent sessions can differ; nothing is written to Node/Agent/Runtime state.

## 3. Catalogue numbers I verified myself

`shared/default` 20 msgids; `shared/errors` 22; `web/default` 164; `web/errors` 0; `cli/default` 23. Total 229 extracted msgids, all zh-translated, pairwise disjoint across the five sets, 0 placeholder mismatches, 0 fuzzy, 0 obsolete. `web/default.pot` line-count grep shows 165 `^msgid ` lines because it counts the header entry.

## 4. Findings

### F1 (fixed by this review) — the daemon closure guard did not cover the new app
- **Source**: `scripts/deployment/check-release.sh` lines 18 and 33 forbade `beamlet_cli|beamlet_web|phoenix*|plug*|bandit|websock*` only. Requirement R1's core risk is precisely the *new* `beamlet_i18n` (and the `gettext`/`expo` it drags in), which the guard could not detect. `design.md` cited "the existing copied-closure check" as the proof for this invariant, so the delivery's own verification story had a hole. Note the same list is used for `.rel`, `.app`, and each app's `required` applications, so the hole covered all three levels.
- **Consequence**: a future dependency edge from Node/daemon to `beamlet_i18n` would ship Web/CLI presentation copy (and a PO parser) into the daemon artifact with every gate still green.
- **Remedy (applied)**: added `beamlet_i18n|gettext|expo` to both the `grep -Ei` alternation and the `~r/\A(…)\z/` regex in the in-release `eval`, with a comment stating the invariant. Verified: `bash -n` clean; `check-release.sh` re-run end-to-end → exit 0 with an **identical** copied-manifest hash (`1817cd87…4f911`), i.e. the same artifact passes the stricter assertion; and a negative test on a synthetic lib tree confirmed the grep now fires on `beamlet_i18n-*`, `gettext-*`, `expo-*` while staying silent on the real daemon set (`beamlet_node`, `mime`, `jason`). `apps/beamlet_daemon` itself was not touched.

### F2 (low, not fixed) — half of the shared-lookup guard is dead code
- **Source**: `apps/beamlet_i18n/test/beamlet/i18n/catalogue_test.exs` `@shared_gettext ~r/Beamlet\.I18n\.gettext\("…"\)/u`. In the current design shared *default-domain* words are always resolved through `Vocabulary.status/1` with a runtime variable, so **zero** literals match this pattern in `apps/beamlet_web/lib` + `apps/beamlet_cli/lib`; only the `dgettext` branch produces hits (18).
- **Consequence**: the assertion is not vacuous (the 18 dgettext hits keep `refute all == []` meaningful, and the "shared vocabulary is declared once" test independently pins the 20 statuses / 22 reasons), but the `gettext` half of the guard can never fail today and would silently stay inert if a future literal were mistyped.
- **Remedy (recommended, not applied)**: either drop the dead branch and scan `Beamlet.I18n.gettext(`/`dgettext(` in `apps/beamlet_i18n/lib/beamlet/i18n/catalogue.ex` instead (that file *is* the literal declaration site), or add an explicit `assert length(gettext_lookups) + length(dgettext_lookups) > 0` with a comment that the gettext branch is for future literal call sites. I left the code alone because no msgid is actually unguarded and this is a "strengthen the guard" cleanup, not a misstatement.

### F3 (low) — app-start host-config validation is now filtered, not strict
- **Source**: `apps/beamlet_cli/lib/beamlet/cli/application.ex` passes `Keyword.take(Application.get_all_env(:beamlet_cli), [:enabled, :allowed_nodes])` into `Beamlet.CLI.configuration/1` (necessary: `:default_locale` in `config/config.exs` would otherwise make boot return `{:error, :invalid_configuration}` and the release/`mix test` app boot would fail).
- **Consequence**: a typo in a *compile-time* `config :beamlet_cli, <typo>` key is now silently ignored instead of failing the boot. The operator-facing path is unaffected: `config/cli_runtime.exs` still validates the trusted `BEAMLET_CONFIG` file with the unfiltered `Beamlet.CLI.configuration/1`, so unknown keys there still raise. No test pins the filtered boot path explicitly (it is exercised implicitly: every `beamlet_cli` test starts the application, and the shipped release boots — gate 15/16).
- **Remedy**: acceptable as-is. Optional hardening: allow `:locale`/`:default_locale` inside `Beamlet.CLI.configuration/1` and drop the `Keyword.take`, which would keep boot-time strictness; if kept, add one test asserting `Application.start/2` succeeds with `:default_locale` present.

### F4 (low, doc drift in a task artifact) — `design.md` still shows the old CLI order
- **Source**: `design.md` §"CLI resolution" says `:locale`/`:default_locale` → `BEAMLET_LANG` → default, which is the order the implementation deliberately replaced (R4).
- **Consequence**: a future reader of the design would think the env override is broken; only the task artifact is affected — code, `CLI.Locale` moduledoc, `scripts/deployment/README.md` and the tests all agree on the implemented order.
- **Remedy**: parent to either amend `design.md` with a one-line "superseded: `:default_locale` ranks below `BEAMLET_LANG` because `config/config.exs` always sets it" note, or archive as-is. I did not edit it (artifact ownership belongs to the parent on acceptance).

### F5 (low) — live re-resolution can produce a mixed-language view; two upstream artifacts are dirty but harmless
- **Source (a)**: `Beamlet.Web.Locale.on_params/3` calls `Shared.put/1` for a `?locale=` arriving through `handle_params`, while mount-time assign values (`@status`, `@input_result`, `@feedback`) are already-rendered **strings** captured in the old language. So a manual LiveView navigation to `?locale=zh_CN` would translate the template text but leave those assign values in the previous language. Not reachable from the UI: the switcher is a plain `<.link href>` (full page load), and no `patch`/`navigate` link carries `?locale=`.
- **Source (b)**: generated artifacts carry upstream noise — duplicated `#:` reference lines in every POT/PO (gettext 1.0.2 `@recursive` extraction registers backends twice and force-compiles twice) and a `###`-prefixed header plus a bare `msgid ""/msgstr ""` in `apps/beamlet_web/priv/gettext/errors.pot`. `mix gettext.extract --check-up-to-date` is green, so the files are self-consistent; `quality-guidelines.md` already documents the duplication as an upstream artifact that must not be hand-edited.
- **Consequence**: (a) cosmetic inconsistency only in an unreachable path; (b) no runtime effect — PO/POT comments are metadata. Both already documented in `WORKBENCH.md` ("Text that was already rendered stays in the language it was rendered in until the next page load") and the spec.
- **Remedy**: nothing required now. If desired later, either stop re-resolving `params["locale"]` in `on_params/3` (rely on the full page load) or recompute the locale-dependent assigns on locale change. Do **not** hand-edit the `#:`/`###` noise.

### Observation (not a finding) — tiny spec staleness
`backend-release.md` still says `BEAMLET_BACKEND_BUILD=1` "compiles five core libraries plus both hosts", which now also compiles `beamlet_i18n`; `directory-structure.md` was correctly updated to "nine child manifests". `backend-release.md`'s closure sentence ("without Web/Phoenix/Plug/Bandit/WebSock or the opposite host") remains true and is now enforced more strictly (F1). Parent decides whether to extend that sentence with `beamlet_i18n`/Gettext/Expo.

## 5. The two acknowledged gaps — judgements

**(a) `beamlet_web` `errors` domain is empty so dynamic changeset messages are not translated — ACCEPTABLE, and technically a non-gap.**
The Web app has no Ecto and no changesets (`grep ecto apps/beamlet_web/mix.exs` → nothing). `core_components.translate_error/1` and the `<.form>/<.input>` scaffolding that consumes the `errors` domain are unreachable in this product: the workbench forms are plain `<form phx-submit>` with no changeset, and `dgettext("errors", …)` is not called anywhere in `apps/beamlet_web/lib`. So the empty domain is an honest report of zero user-visible text, not missing copy, and "所有文字信息" is still fully satisfied: my ASCII sweep of all five Chinese pages found no untranslated product copy. It would only become a real gap the day a changeset-backed form is added; the `errors` catalogue (both `.po` files) already exists and is wired into `translate_error/1`, so the fix at that point is data-only. **No action now**; if the parent wants belt-and-braces, note it in the task journal rather than pre-translating invented Ecto copy (which the review rules forbid anyway).

**(b) LiveView does not re-translate an already-mounted view when `?locale=` changes — ACCEPTABLE now, documented, with a narrow residual.**
The only locale switch in the UI is the header switcher, a plain full-page link, so every real switch remounts and re-renders everything; there is no client-side re-translation by design (also the reason there is no browser storage). The residual is a manual LiveView navigation to `?locale=` producing a partially stale view (F5a) — unreachable through the product's own affordances, cosmetic, and already disclosed in `app/beamlet_web/WORKBENCH.md` §Language ("Text that was already rendered stays in the language it was rendered in until the next page load"). Judged **not** worth a fix in this task; if it ever becomes reachable (e.g. a `patch`-based switcher), the cheap fix is to force a full reload or recompute the locale-dependent assigns.

## 6. Residual risks

1. **No browser-level evidence for this change.** Chinese default and switching are proven by rendered-HTML assertions and my endpoint probes, not by a real browser walkthrough (the archived Web task had geckodriver evidence; this delivery does not). CSP nonce/theme script interaction with the new switcher is covered only by the existing static/CSP tests.
2. **Release-level Chinese coverage rests on one path.** `check-cli-release.py` now pins `BEAMLET_LANG=en`, so the copied-release gate no longer observes the shipped Chinese default. I closed this manually (gate 15) but nothing in CI will re-detect a Chinese-only regression in the release artifact.
3. **`en` catalogues are intentionally all-empty msgstr.** Any future msgid whose English text should differ from the msgid would silently render the msgid; the completeness test asserts key coverage only, not that a non-empty English translation was considered.
4. **`zh_TW`-style input is rejected, not mapped** (`normalize("zh_TW") == nil` → default `zh_CN`). Correct per design; noted because a Traditional-Chinese user silently gets Simplified.
5. **Unlisted reason atoms stay English** in zh mode (e.g. an agent/node reason not in the 22-word vocabulary renders as `snapshot_limit`). This is the documented "unknown identifiers keep their existing rendering" rule, not a leak, but it is user-visible mixed language if a new reason is introduced without a catalogue entry. The vocabulary test only pins the *declared* list, so adding a reason without translating it would not fail.
6. **F2/F3/F4/F5 above** are all low severity and none affects a rendered string or a boundary.
7. Historical `/tmp/i18n-gates` artifacts were treated as unverified; all numbers in this report are from my own runs. `research/implementation-handoff.md` was never written, so the implementer's intent for R4 rests on code/moduledoc/README/tests only (which agree).

## 7. Recommendation

**PASS** — no blocker. The delivery meets every requirement I was asked to verify, on an independently re-run gate set, with catalogue numbers I parsed myself. One real defect in the delivery's verification story was found and fixed (F1: the daemon closure guard did not cover the newly introduced `beamlet_i18n`/`gettext`/`expo`; the fix is verified against the same artifact and a negative test). F2–F5 are low-severity observations, documented above with remedies; none needs to block acceptance. F4 (design.md's stale CLI precedence order) and the `backend-release.md` sentence are the only documentation items the parent may want to touch before archiving, since spec/artifact acceptance is explicitly the parent's.
