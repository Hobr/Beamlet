# Design: Web/CLI i18n with Gettext

## Shared vs app-owned catalogues

Three Gettext backends, one ownership rule:

| Backend | App | Contents |
| --- | --- | --- |
| `Beamlet.I18n` | new `beamlet_i18n` | strings used by both surfaces: status/reason vocabulary, generic actions and table headers, shared locale normalisation and default locale |
| `Beamlet.Web.Gettext` | `beamlet_web` | Web-only titles, descriptions, form labels, server feedback |
| `Beamlet.CLI.Gettext` | `beamlet_cli` | help body, CLI-specific headers, terminal session prompts |

Rule: a msgid needed by both surfaces lives only in the shared catalogue; a string used by one surface never enters the shared one. The three msgid sets must stay disjoint.

- New umbrella app `apps/beamlet_i18n/mix.exs` (`app: :beamlet_i18n`, dep `{:gettext, "~> 1.0"}`, `extra_applications: [:logger]`) so shared translations are a real dependency of Web and CLI, and are **not** pulled into the daemon closure.
- `Beamlet.I18n` uses `use Gettext.Backend, otp_app: :beamlet_i18n`; catalogue at `apps/beamlet_i18n/priv/gettext/{en,zh_CN}/LC_MESSAGES/{default,errors}.po`.
- `Beamlet.I18n.Locale` owns `normalize/1`, `default/0` and `options/0` for both surfaces, so locale canonicalisation cannot drift. Web/CLI keep thin wrappers only.
- Calls: app-owned strings use the imported `gettext("...")`/`dgettext("errors", "...")` macros. Shared strings use the **runtime** functions `Beamlet.I18n.gettext("...")` / `Beamlet.I18n.dgettext("errors", "...")`.
- Extraction only happens through macros, so shared msgids must be *declared* in the shared app: `Beamlet.I18n.Catalogue` calls each shared `gettext("...")` once (and each shared error msgid through `dgettext("errors", ...)`). That module is the single owner of the shared POT; Web/CLI never register the shared backend, so per-app extraction can never prune another surface's shared entries.
- Guard: a test scans `apps/beamlet_web/lib` and `apps/beamlet_cli/lib` for `Beamlet.I18n.gettext("…")`/`Beamlet.I18n.dgettext("errors", "…")` literals and asserts every one exists in the shared catalogue, and that no shared msgid is duplicated in an app catalogue.

Extraction: each backend writes its POT into its own `priv`, so the three catalogues stay separate by construction. Extract from the umbrella root (`mix gettext.extract --merge`, recursive over all apps) so the shared, Web and CLI catalogues are refreshed in one command; `mix gettext.extract --check-up-to-date` is the drift gate.

## Backends and catalogues

- Reuse `Beamlet.Web.Gettext` (`apps/beamlet_web/lib/beamlet_web/gettext.ex`) with `otp_app: :beamlet_web`.
- Add `Beamlet.CLI.Gettext` (`use Gettext.Backend, otp_app: :beamlet_cli`) and declare `{:gettext, "~> 1.0"}` in `apps/beamlet_cli/mix.exs`. The version is already resolved in the shared `mix.lock`, so no new resolution is required; verify `mix.lock` is unchanged.
- Catalogues: `priv/gettext/en/LC_MESSAGES/{default,errors}.po` and `zh_CN/LC_MESSAGES/{default,errors}.po` for both apps, plus the generated `default.pot`/`errors.pot`. English `msgstr` may stay empty (msgid is English); zh_CN must translate every msgid.
- Domains: `default` for product copy; `errors` for form/validation copy already used by `core_components.translate_error/1`. HTTP status phrases stay Phoenix-owned unless covered by an `errors` msgid.

## Locale canonicalisation and default

- Canonical locales: `zh_CN` (default) and `en`.
- One shared normaliser per app (`Beamlet.Web.Locale.normalize/1`, `Beamlet.CLI.Locale.normalize/1`) accepts `zh`, `zh-cn`, `zh_CN`, `cn` → `zh_CN`; `en`, `en-us`, `en_US` → `en`; anything else → `nil`.
- Config defaults: `config :beamlet_web, :default_locale, "zh_CN"` and `config :beamlet_cli, :default_locale, "zh_CN"`. Absent config falls back to `zh_CN` in code, so a stripped config still shows Chinese.

## Web resolution

Order: session `"locale"` → `?locale=` query (validated, canonicalised) → config default.

- `Beamlet.Web.Locale` plug in the `:browser` pipeline: resolve, `Gettext.put_locale(Beamlet.Web.Gettext, locale)`, put `?locale` into the session when present, and assign `:locale` plus `:locale_options` for the switcher.
- `on_mount({Beamlet.Web.Locale, :default})` for LiveViews: same resolution from session/params, `Gettext.put_locale`, assign locale. `handle_params` re-runs resolution so a `?locale=` change applies without remount.
- Layout switcher: two links/buttons (`中文` / `English`) that navigate with `?locale=zh_CN|en`, preserving the current path. No client-side storage; the session cookie is signed but the locale is non-sensitive.
- Every LiveView/component module that renders copy adds `use Gettext, backend: Beamlet.Web.Gettext`; HEEx uses `gettext("...")`, `dgettext("errors", ...)` for form errors.

## CLI resolution

Order: `:beamlet_cli, :locale` trusted config → `BEAMLET_LANG` environment → `:beamlet_cli, :default_locale` → default `zh_CN`.

> Superseded detail: this task originally put `:default_locale` above `BEAMLET_LANG`. Because `config/config.exs` always sets `:default_locale, "zh_CN"`, that order made the environment override unreachable, so the implemented order places `BEAMLET_LANG` above `:default_locale` (still below the explicit `:locale`). See `.trellis/spec/backend/i18n.md` and `Beamlet.CLI.Locale`.

- `Beamlet.CLI.Locale.locale/0` reads config/env and canonicalises; `Beamlet.CLI.Runner` calls `Gettext.put_locale(Beamlet.CLI.Gettext, locale)` once before reading stdin, so every later `Renderer`/`Session` call in that process renders in the chosen language.
- `Renderer`/`Session`/`Runner` wrap user-visible strings in `gettext(...)`/`dgettext("default", ...)`; table headers, help text, `(none)`, discovery summary, `error: ...`, and session prompts are all covered. Column layout, ordering, bounds, exit codes and parsing are unchanged.
- Tests may set the locale explicitly with `Gettext.put_locale/2`; a helper resets it after each test.

## Extraction and merge

- Planned commands (verify which works in this umbrella): `mix gettext.extract --merge` from the repo root; if the umbrella task cannot target a single app, fall back to per-app `cd apps/beamlet_web && mix gettext.extract --merge`.
- That child-directory form is currently blocked by a pre-existing umbrella `:only` mismatch (`beamlet_runtime` declared `only: :test` in Web/CLI but unconditional in Node). Do not weaken dependency truth just to run the task. Preferred unblock: declare `beamlet_runtime` (and `beamlet_harness` for CLI) consistently without `only: :test` in the Web/CLI manifests, since both are already in Node's compile closure and Web/CLI production code does not call them; verify `mix.lock`, compile, and the backend release closure are unchanged. If that is rejected during review, add a small root-level Mix task that invokes `Gettext.Extractor` per app instead.
- Reviewed zh_CN `.po` files are committed, so a fresh checkout does not need extraction to build.


## Dependency and closure impact

- `beamlet_web` and `beamlet_cli` add `{:beamlet_i18n, in_umbrella: true}`; `beamlet_cli` also adds `{:gettext, "~> 1.0"}` (the shared app already brings it transitively, but CLI calls it directly). `mix.lock` is unchanged because gettext 1.0.2 is already resolved.
- The daemon must not gain `beamlet_i18n`: it depends only on Node, and the shared app is not a sibling used by that graph. Verify with the existing copied-closure check (`check-release.sh`) that the daemon artifact still ships no CLI/Web/Phoenix/Plug/Bandit/WebSock apps.
- The CLI release gains `beamlet_i18n`, `gettext` and `expo`; `check-cli-release.py` forbids only `beamlet_daemon|beamlet_web|phoenix*|plug*|bandit|websock*`, so this is allowed — but re-run `check-cli-release.py` and record the new closure manifest.

## Catalogue ownership tests

- Parse shared and per-app `.po`/`.pot` files and assert the three msgid sets are pairwise disjoint.
- Assert every extracted msgid has a non-empty `zh_CN` msgstr in the catalogue that owns it, and that no catalogue contains an unused msgid.
- Assert `mix gettext.extract --check-up-to-date` passes on a clean checkout.
## Compatibility and failure behaviour

- Missing translation → Gettext returns the msgid (English); no crash, no `nil`/term rendering. Unknown locale → normaliser returns `nil` → default `zh_CN`.
- No behaviour, state, protocol, security or storage change. Locale is request/session scoped; LiveView processes set their own locale, so concurrent sessions can differ.
- CLI output stays bounded and single-line-safe; translations must not introduce unbounded text or new control characters.

## Test strategy

- Update existing English assertions to set the locale explicitly (`en`) so they keep testing behaviour rather than copy; keep them deterministic and restore locale in `on_exit`.
- Add: default-zh assertions for `/`, `/agents/new`, workspace, three admin pages and CLI help/error/discovery/status; switch-to-en and switch-back for Web (session + `?locale`); unknown locale fallback; CLI env/config override ordering; PO completeness test that every extracted msgid has a non-empty zh_CN msgstr and that zh pages contain no leftover English for a sampled key set.
- Keep existing CSP/CSRF/escaping/error-page regressions and CLI bounds tests unchanged except for locale setup.

## Rollout and rollback

Ship both catalogues together; no feature flag. Rollback: revert the i18n commit(s); product behaviour is unaffected because no business logic is translated, only presentation strings.