# Implementation handoff — Web/CLI Gettext i18n (10-18-i18n-web-cli)

Continuation run. Everything below was executed on the current working tree; no
stage/unstage/reset/commit/branch/archive/task-pointer operation was performed and
no acceptance was marked.

Previous run was verified as already complete for: the `beamlet_i18n` app skeleton,
the Web locale plug/on_mount/switcher + translated LiveViews, the CLI
`Gettext`/`Locale`/`Renderer`/`Runner` wiring, `config/config.exs` defaults, and a
green `mix compile --warnings-as-errors`. That code was not reshaped. The reported
`use Beamlet.Web` / "module not loaded" blocker was stale `.expert` index noise: I
deleted `apps/beamlet_web/.expert`, `apps/beamlet_cli/.expert`,
`apps/beamlet_i18n/.expert` and the stray `apps/beamlet_i18n/erl_crash.dump`
(all git-ignored; none added to git). The tooling recreated the `.expert` caches
later, still ignored.

## 1. New and changed paths

### New files

Shared catalogue app:

- `apps/beamlet_i18n/mix.exs`, `apps/beamlet_i18n/.formatter.exs`
- `apps/beamlet_i18n/lib/beamlet/i18n.ex` (backend + runtime `gettext/2`, `dgettext/3`)
- `apps/beamlet_i18n/lib/beamlet/i18n/locale.ex` (single canonicalisation/default/`put`)
- `apps/beamlet_i18n/lib/beamlet/i18n/vocabulary.ex` (allowlisted status/reason lookup)
- `apps/beamlet_i18n/lib/beamlet/i18n/catalogue.ex` (sole declaration owner of shared msgids)
- `apps/beamlet_i18n/priv/gettext/{default,errors}.pot`
- `apps/beamlet_i18n/priv/gettext/{en,zh_CN}/LC_MESSAGES/{default,errors}.po`
- `apps/beamlet_i18n/test/test_helper.exs`
- `apps/beamlet_i18n/test/support/catalogue_files.ex` (PO/POT parser + source scan helpers)
- `apps/beamlet_i18n/test/beamlet/i18n/locale_test.exs` (10 tests)
- `apps/beamlet_i18n/test/beamlet/i18n/catalogue_test.exs` (5 tests)

Web:

- `apps/beamlet_web/lib/beamlet_web/locale.ex` (plug, `on_mount`, `on_params`, `resolve`, `options`, `path_for`, `html_lang`)
- `apps/beamlet_web/priv/gettext/default.pot`
- `apps/beamlet_web/priv/gettext/en/LC_MESSAGES/default.po`
- `apps/beamlet_web/priv/gettext/zh_CN/LC_MESSAGES/{default,errors}.po`
- `apps/beamlet_web/test/beamlet_web/i18n_test.exs` (14 tests)

CLI:

- `apps/beamlet_cli/lib/beamlet/cli/gettext.ex`
- `apps/beamlet_cli/lib/beamlet/cli/locale.ex`
- `apps/beamlet_cli/priv/gettext/default.pot`
- `apps/beamlet_cli/priv/gettext/{en,zh_CN}/LC_MESSAGES/default.po`
- `apps/beamlet_cli/test/beamlet/i18n_test.exs` (7 tests)

Task artifacts (pre-existing from planning, untracked):
`.trellis/tasks/10-18-i18n-web-cli/{prd.md,design.md,implement.md,implement.jsonl,check.jsonl,task.json}`.

### Modified files

Source:

- `mix.exs` (root): `:beamlet_i18n` added to the backend build selector.
- `config/config.exs`: `config :beamlet_web, :default_locale, "zh_CN"` and `config :beamlet_cli, :default_locale, "zh_CN"`.
- `apps/beamlet_web/mix.exs`: `{:beamlet_i18n, in_umbrella: true}`.
- `apps/beamlet_web/lib/beamlet_web/router.ex`: `plug Beamlet.Web.Locale` in `:browser`.
- `apps/beamlet_web/lib/beamlet_web/live/workbench_live.ex`, `live/workbench_live.html.heex`,
  `live/management_live.ex`, `components/observation_components.ex`,
  `components/layouts.ex` (locale switcher), `components/layouts/root.html.heex`
  (`lang` from resolved locale): user-visible copy through Gettext, shared
  vocabulary through `Beamlet.I18n.Vocabulary` (see §3 for the 5 duplicate-msgid
  corrections I made in this run), plus `Locale` aliases (Credo `--strict`).
- `apps/beamlet_cli/mix.exs`: `{:beamlet_i18n, in_umbrella: true}`, `{:gettext, "~> 1.0"}`.
- `apps/beamlet_cli/lib/beamlet/cli/renderer.ex`: all terminal copy through
  `Beamlet.CLI.Gettext`, shared reasons/status through `Beamlet.I18n`; allowlist
  `safe_reason/1` replaces the old inline list, so an unexpected term still
  renders `request_failed`.
- `apps/beamlet_cli/lib/beamlet/cli/runner.ex`: `Locale.put()` before reading stdin
  (+ `Locale` alias).
- `apps/beamlet_cli/lib/beamlet/cli/application.ex`: `Keyword.take(env, @host_keys)`
  so `:locale`/`:default_locale`/`:agent_options` are not read as host settings.
- `apps/beamlet_cli/lib/beamlet/cli/locale.ex`: precedence corrected (see §5).

Tests:

- `apps/beamlet_web/test/support/conn_case.ex`: connection now starts with an
  explicit `en` session locale (`@test_locale`, override with `@tag locale: "zh_CN"`,
  `test_locale/0` exposed). No global config/env mutation, so async cases stay safe.
- `apps/beamlet_cli/test/beamlet/session_test.exs`: setup pins
  `config :beamlet_cli, :locale, "en"` + `Locale.put("en")` and restores in `on_exit`;
  English assertions unchanged.

Docs:

- `apps/beamlet_web/WORKBENCH.md`: new "Language" section (default, precedence,
  switcher/session behaviour, fallback, catalogue ownership).
- `apps/beamlet_web/HOST.md`: UI language is presentation config, not part of the
  trusted `:host` schema.
- `scripts/deployment/README.md`: "Terminal language" (`BEAMLET_LANG` precedence,
  accepted spellings, unchanged grammar/bounds/exit codes) + note that
  `check-cli-release.py` pins `BEAMLET_LANG=en`.
- `scripts/deployment/check-cli-release.py`: adds `BEAMLET_LANG="en"` to the three
  CLI process envs (session, width/eval/invalid, pty). It asserts English copy
  (`error: invalid_command`, `no error:`), which the new Chinese default would
  otherwise break; pinning keeps the existing assertions exact instead of weakening
  them, and additionally exercises the env switch.
- `.trellis/spec/backend/quality-guidelines.md`: root-only `mix gettext.extract
  --merge` / `--check-up-to-date` rows, the ownership invariant (one msgid ↔ one
  catalogue, zh complete, en may be empty, shared-lookup literals must exist),
  the upstream duplicate `#:` artifact, and the test-locale rules for Web/CLI.
- `.trellis/spec/backend/directory-structure.md`: `beamlet_i18n` app row, nine
  manifests, dependency placement (web/cli `in_umbrella`, cli `gettext`), daemon
  closure rule, per-app catalogue paths, `Beamlet.Web.Locale` in the request flow.

## 2. Catalogue ownership and counts

| Catalogue | Message ids | zh_CN translated | en |
| --- | --- | --- | --- |
| `beamlet_i18n` default | 20 | 20 | 20 entries, empty msgstr (msgid is English) |
| `beamlet_i18n` errors | 22 | 22 | 22 entries, empty msgstr |
| `beamlet_web` default | 164 | 164 | 164 entries, empty msgstr |
| `beamlet_web` errors | 0 | 0 | 0 (no static msgids; changeset text is dynamic) |
| `beamlet_cli` default | 23 | 23 | 23 entries, empty msgstr |
| **total** | **229** | **229 (100 %)** | — |

Verified facts:

- The five msgid sets (three behaviours, `default`/`errors` domains) are pairwise
  disjoint — mechanically checked. Five msgids (`complete`, `partial`, `enabled`,
  `disabled`, `disconnected`, `unknown`) initially appeared in *both* the shared and
  the Web catalogue; I removed the Web duplicates by switching
  `management_live.ex` to `Vocabulary.status/1`, so the shared catalogue is the only
  owner.
- Extraction/merge ran from the repo root only:
  `mix gettext.extract --merge`, then `mix gettext.extract --check-up-to-date` → exit 0,
  stable across repeated runs.
- Shared msgids land only in `apps/beamlet_i18n/priv/gettext`; app-only msgids only in
  that app's `priv/gettext`. `Beamlet.I18n.Catalogue` is the sole declaration point for
  shared strings; Web/CLI never register that backend, so no app extraction can prune it.
- No PO/POT file is git-ignored (checked with `git check-ignore`).
- Upstream noise: with Elixir 1.20.4 + Gettext 1.0.2, `mix gettext.extract` compiles
  each app twice (`compile --force-elixir` and then `compile.elixir --force`), so
  generated POT/PO files contain duplicated `#:` reference lines, and the umbrella
  run prints `the Gettext backend X has the same :priv directory as X` for each
  backend (an artifact of the extractor agent accumulating per-app backends). Both are
  deterministic, harmless, and must not be hand-edited away.

## 3. Copy decisions worth knowing

- Grammar-only CLI help rows (`create …`, `attach …`, `input …|status …|watch …`,
  `stop …|close …|detach …|quit`) carry a short Chinese gloss in parentheses
  (`（创建）`, `（附加）`, `（输入 | 状态 | 观测）`, `（停止 | 关闭 | 分离 | 退出）`) so
  every extracted msgid has a real translation. Row count, row order, tokens,
  column layout, widths and bounds are unchanged; English rendering is byte-identical
  to before.
- Shared status/reason vocabulary is translated only through the allowlists in
  `Beamlet.I18n.Catalogue`; unknown identifiers (e.g. `not_configured`, `fresh`,
  tool names, service names) keep their existing rendering instead of inventing copy.
  That is intentional, and it is why unlisted tokens still appear untranslated inside
  otherwise Chinese sentences.
- `Beamlet.Web.ObservationComponents.text/1` now maps atoms through
  `Vocabulary.status/1`, which returns a string for every atom (so no atom/`nil`
  ever reaches the page).

## 4. Locale resolution as implemented

Canonicalisation and defaults live only in `Beamlet.I18n.Locale`:
`zh`, `zh-cn`, `zh_CN`, `zh_cn`, `cn` → `"zh_CN"`; `en`, `en-us`, `en_US` → `"en"`;
anything else (including `nil`/non-binary) → `nil`. `default/0` = `"zh_CN"`;
`put/1` canonicalises and sets the process-global Gettext locale (which covers both
`Beamlet.I18n` and the surface backend).

Web (`Beamlet.Web.Locale`):

1. valid `?locale=` (canonicalised; a valid value is written to the session);
2. session `"locale"`;
3. `config :beamlet_web, :default_locale`, else the shared default `zh_CN`.

The plug runs in the `:browser` pipeline (`fetch_query_params`, persist, resolve,
`put_locale`, assign `:locale` / `:locale_options`); LiveViews use
`on_mount({Beamlet.Web.Locale, :default})` plus `on_params/3` on every
`handle_params`, which re-resolves and re-installs the locale and records the current
path for the switcher. `Layouts.locale_switcher/1` renders `<.link href=...>` entries
(`中文` / `English`) that keep the current path and add `?locale=…`; it is a plain
page load, no client storage, no client-side translation. `root.html.heex` renders
`lang={Beamlet.Web.Locale.html_lang(assigns[:locale])}` (`zh-CN` / `en`).

CLI (`Beamlet.CLI.Locale.locale/0`):

1. `config :beamlet_cli, :locale` (trusted, wins over everything);
2. `BEAMLET_LANG`;
3. `config :beamlet_cli, :default_locale`;
4. shared default `zh_CN`.

An unusable value at any step is skipped. `Beamlet.CLI.Runner.run/2` calls
`Locale.put()` before reading stdin, so one process renders one language.

## 5. Deliberate deviation (needs review attention)

The design text ordered config (including `:default_locale`) **before** `BEAMLET_LANG`.
Because `config/config.exs` always sets `:default_locale, "zh_CN"`, that order made the
documented environment override unreachable in every release. I moved `BEAMLET_LANG`
above `:default_locale` (below the explicit `:locale`), which keeps "trusted
configuration first" for operator config while making `BEAMLET_LANG` work. Module docs,
`scripts/deployment/README.md`, and
`apps/beamlet_cli/test/beamlet/i18n_test.exs` all state and test this order.
Verified on the built release: default → Chinese help, `BEAMLET_LANG=en` → English
help, exit code 0 and identical columns/grammar in both.

Related, unchanged-on-purpose: `:locale` is *not* part of the trusted `BEAMLET_CONFIG`
host schema (`Beamlet.CLI.configuration/1` accepts only `:enabled`/`:allowed_nodes`),
so in a shipped release the operator-facing switch is `BEAMLET_LANG`; `:locale` works
for build-time application config. Adding `:locale` to the host schema would be a
config-contract change and was not made.

## 6. Tests

Added:

- `apps/beamlet_web/test/beamlet_web/i18n_test.exs` (14): shipped default Chinese with
  no session/query; `/`, `/agents/new`, workspace (real deterministic Agent + handle),
  and the three admin pages in Chinese; node read results in Chinese; no leftover
  English or internal terms (`#Function<`, `Elixir.Beamlet`, `%{`, `{{`) on five
  sampled Chinese pages; `?locale=en` → session persistence → switch back; aliases
  (`zh`, `en-us`); unknown locale fallback + never persisted; unknown locale keeps an
  existing session choice; LiveView mount honours session; `on_params/3` re-resolves
  for a mounted view; switcher keeps the path and offers both languages.
- `apps/beamlet_cli/test/beamlet/i18n_test.exs` (7): Chinese default; trusted
  `:locale` beats env; env beats shipped `:default_locale` and accepts aliases; unusable
  values skipped; `Runner` installs the locale before reading stdin (Chinese vs English
  help via captured output, exit 0); unknown reasons translate to `错误：请求失败` /
  `error: request_failed` and never leak the atom; shared vocabulary through
  `Beamlet.I18n`.
- `apps/beamlet_i18n/test/beamlet/i18n/catalogue_test.exs` (5): every extracted msgid
  has a non-empty `zh_CN` msgstr in its owning catalogue (and the PO set equals the POT
  set); `en` covers every msgid; the five catalogues are pairwise disjoint; every
  `Beamlet.I18n.gettext/…` and `Beamlet.I18n.dgettext/…` literal in
  `apps/beamlet_web/lib` + `apps/beamlet_cli/lib` exists in the shared catalogue (and
  the scan is asserted non-empty); the vocabulary allowlists are declared in the shared
  POTs.
- `apps/beamlet_i18n/test/beamlet/i18n/locale_test.exs` (10): canonicalisation,
  rejection of unknown/non-binary input, default/locales/options/html_lang, `put/1`
  (including unknown → default), vocabulary translation and pass-through.

Updated: `apps/beamlet_web/test/support/conn_case.ex` (explicit `en` session locale)
and `apps/beamlet_cli/test/beamlet/session_test.exs` (explicit English config + process
locale, restored in `on_exit`). All pre-existing English assertions were kept verbatim.

Counts (final tree): Web 73 passed / 5 excluded (59 before + 14 new); CLI 25 passed /
1 excluded (18 before + 7 new); `beamlet_i18n` 15 passed. No test was weakened; no
assertion was deleted or relaxed.

## 7. Validation (final tree, real output)

| Command | Result |
| --- | --- |
| `mix format --check-formatted` | exit 0 |
| `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_web/test` | `Result: 73 passed, 5 excluded`, exit 0 |
| `mix test apps/beamlet_cli/test` | `Result: 25 passed, 1 excluded`, exit 0 |
| `mix test apps/beamlet_i18n/test` | `Result: 15 passed`, exit 0 |
| `mix test --seed 631927` (root, all apps) | exit 0 — harness 35, actions 28, i18n 15, runtime 43 passed/6 excluded, agent 26, node 68 passed/20 excluded, daemon 5 passed/2 excluded, cli 25 passed/1 excluded, web 73 passed/5 excluded → **318 passed, 34 excluded, 0 failures** |
| `mix credo --strict` | exit 0 — `1326 mods/funs, found no issues` (150 files) |
| `mix sobelow` | exit 0 — `... SCAN COMPLETE ...`, no findings |
| `mix dialyzer --no-check` (existing PLT, no refresh) | exit 0 — `Total errors: 0, Skipped: 0, Unnecessary Skips: 0`, `done in 0m3.83s`, `done (passed successfully)` |
| `mix gettext.extract --check-up-to-date` (root) | exit 0 (only the known upstream `same :priv directory` warnings) |
| `git diff --check` | exit 0 |
| `mix.lock` | unchanged (`git status --porcelain mix.lock` empty; gettext 1.0.2 / expo 1.1.1 were already pinned) |

Exclusions are the suites' own `@tag :distributed` skips (`ExUnit.start(exclude:
[:distributed])`), none added here. Credo initially reported 7 new "nested modules
could be aliased" design suggestions from the new `Beamlet.Web.Locale` /
`Beamlet.CLI.Locale` calls; I added module aliases (no behaviour change) and the final
`--strict` run is clean.

Long gates ran detached with per-command logs and exit-code files under
`/tmp/i18n-gates/` (`full-test2.log/.exit`, `credo2.log`, `sobelow.log`,
`dialyzer.log/.exit`, `extract-check.log/.exit`, `release-daemon.log`,
`release-cli.log`), polled rather than assumed.

## 8. Release closure (manifests changed)

Both backend releases were rebuilt from the current tree
(`BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite`,
same for `beamlet_cli`; both exit 0), so the evidence is from fresh artifacts, not the
stale pre-change ones:

- `_build/backend/prod/rel/beamlet_daemon/releases/0.1.0/beamlet_daemon.rel` app list:
  `beamlet_daemon, beamlet_actions, beamlet_agent, beamlet_harness, beamlet_node,
  beamlet_runtime` (+ OTP/deps). **No `beamlet_i18n`, `gettext` or `expo`**; lib scan
  (`beamlet_i18n|gettext|expo`) → none; forbidden-host scan
  (`beamlet_cli|beamlet_web|phoenix*|plug*|bandit|websock*`) → none. 26 lib dirs.
- `beamlet_cli.rel` app list includes `beamlet_i18n` (as designed); lib dirs contain
  `beamlet_i18n-0.1.0`, `gettext-1.0.2`, `expo-1.1.1`; forbidden scan
  (`beamlet_daemon|beamlet_web|phoenix*|plug*|bandit|websock*`) → none. 31 lib dirs.
- Real release smoke (not just unit tests): `bin/beamlet_cli start` with
  `printf "help\nquit\n"` renders the Chinese help table; with `BEAMLET_LANG=en` it
  renders the English table and `error: invalid_command`, exit 0.
- **Not executed:** the full `scripts/deployment/check-release.sh` /
  `check-cli-release.py` acceptance (copied artifacts, named start/RPC/pid/stop on
  ports 9100/19101/19102, daemon/CLI multi-process sessions, pty enumeration). Those
  need free fixed ports, EPMD and a long single-host run; only the static closure part
  of `check-release.sh` was reproduced by inspection above. The closure check is
  therefore **partial evidence, not full release acceptance**. `check-cli-release.py`
  was made language-deterministic (`BEAMLET_LANG=en`) but has not been run.

## 9. Remaining gaps and risks

1. **LiveView re-render on `?locale=` without remount.** `on_params/3` resolves and
   installs the new locale (unit-tested), but LiveView caches `gettext/1` literals that
   depend on no assign, and copy already stored in assigns at mount (`status:`,
   `input_result:`) stays as rendered. Switching is therefore a full page load, which
   is exactly what `Layouts.locale_switcher/1` does (`href`, not `patch`/`navigate`).
   Consequence: editing `?locale=` on an already-open socket does not re-translate the
   visible page. If live re-translation is ever required, the copy must move out of
   mount-time assigns (e.g. store msgids/keys and translate at render time).
2. **`beamlet_web` `errors` domain is empty.** `core_components.translate_error/1`
   receives dynamic changeset messages, so nothing is extracted and form/validation
   messages are not translated (they render the original English changeset text). No
   crash, no `nil`, but PRD I1's "form/server feedback" is only met for the copy that
   is static in source. Localising changeset messages would need msgid-based error
   keys in the core layer — out of scope here.
3. **Unlisted identifiers stay untranslated** by design (e.g. `not_configured`,
   `fresh`, `routes`, tool/service names inside Chinese sentences). This is deliberate
   (no invented copy, no leaking of internal terms) but a Chinese page can therefore
   mix scripts.
4. **`:locale` is not part of the trusted CLI host schema**, so `BEAMLET_CONFIG`
   cannot set it (see §5). Operator switch in a release is `BEAMLET_LANG`.
5. **Upstream extraction artifacts**: duplicated `#:` refs and the spurious
   `same :priv directory` warnings; stable, documented, must not be hand-fixed.
6. **Release acceptance not run** (see §8).
7. `apps/beamlet_web/lib/beamlet_web/controllers/page_html/home.html.heex` is unrouted
   scaffold and was left untranslated (no reachable route renders it).

## 10. Not performed (by instruction)

No `git add`/`commit`/`push`/`merge`/`stash`, no branch or task-pointer operation, no
`task.py` state change, no archive, and no acceptance marking. Working tree only.
