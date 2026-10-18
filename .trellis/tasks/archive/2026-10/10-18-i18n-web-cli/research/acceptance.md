# Acceptance: Web/CLI Gettext i18n

Result: **PASS for source acceptance** after independent review. No blocker. Browser-level verification was not part of this task's scope and was not performed.

Evidence: research/implementation-handoff.md and research/independent-check.md (the reviewer parsed the catalogues itself and re-ran every gate; its historical `/tmp` evidence was treated as unverified).

## Verified invariants

- Shared + per-surface catalogues: `beamlet_i18n` is a Gettext-only leaf app owning `Beamlet.I18n`, `Locale`, `Vocabulary` and the sole declaration module `Catalogue`; Web and CLI depend on it and each own only surface-specific copy. The daemon closure has no `beamlet_i18n`/`gettext`/`expo` (`.rel` and lib scan). `mix.lock` unchanged.
- Catalogue numbers (independently parsed): shared default 20, shared errors 22, Web default 164, Web errors 0, CLI default 23 = **229 msgids, all with non-empty `zh_CN`**, `en` keys complete, five sets pairwise disjoint, zero placeholder mismatches, zero fuzzy/obsolete.
- Default Chinese proven end to end: session-less HTTP GETs for `/`, `/agents/new` and the three admin pages return Chinese copy with `<html lang="zh-CN">`; CLI without config/env renders Chinese (unit, renderer and shipped-release levels); explicit `en` restores the previous bytes/layout; aliases and unknown-locale fallback behave as specified.
- Locale precedence: Web `?locale=` → session → `:default_locale` → `zh_CN`; CLI `:locale` → `BEAMLET_LANG` → `:default_locale` → `zh_CN`. The deliberate move of `BEAMLET_LANG` above `:default_locale` is judged justified, documented in three places and tested both ways; design.md now carries a superseded note.
- No behaviour regression: CLI grammar/columns/order/widths/bounds/exit codes unchanged and English output byte-identical; Web events, state machine, CSP/CSRF/escaping and error pages unchanged; `check-cli-release.py` only pins `BEAMLET_LANG=en` so its existing exact assertions keep their meaning.
- No new persistence: locale is request/session scoped, no database, no browser transcript, no new cookie.

## Gates (independent re-run on the final tree)

format; warning-fatal compile (`--force`, zero warnings); i18n 15 passed; Web 73 passed/5 excluded; CLI 25/1 excluded; umbrella **318 passed/34 excluded/0 failures**; strict Credo (150 files, 1326 mods/funs); Sobelow; existing-PLT Dialyzer (0 errors, no refresh); `mix gettext.extract --check-up-to-date` exit 0; `git diff --check`; `mix.lock` unchanged; daemon `.rel` closure; full `check-release.sh` **passed twice** (identical copied-manifest hash) including named daemon modes, bootstrap/Gateway turn, 12 invalid configs and three CLI sessions; shipped CLI Chinese default and `BEAMLET_LANG=en` layout equality.

## Findings and dispositions

- F1 (fixed in review): the daemon closure guard did not forbid the newly introduced `beamlet_i18n|gettext|expo`. Both the `grep` and the in-release `eval` regex now do; re-run passed with an identical artifact and a negative synthetic-tree test.
- F2 (fixed by parent after review): the shared-lookup guard's `gettext` branch was inert because shared default words resolve through `Vocabulary` with a runtime value. The test now also scans the declaration module (`CatalogueFiles.source_file/0`) and asserts a real `gettext` declaration exists, so the branch is live. i18n suite 15 passed.
- F3 (accepted): `Beamlet.CLI.Application` filters app-env keys before `CLI.configuration/1` because `:default_locale` would otherwise fail boot. The `BEAMLET_CONFIG` path keeps strict validation. Optional future hardening noted: accept `:locale`/`:default_locale` in the schema and drop the filter.
- F4 (fixed): design.md's stale CLI order annotated as superseded.
- F5 (accepted): a manual LiveView `?locale=` change can leave mount-time assigns in the previous language; unreachable from the UI (switcher is a full page load) and documented in WORKBENCH.md. Generated `#:` duplication is an upstream Gettext artifact that must not be hand-edited.
- Doc staleness (fixed): `backend-release.md` now says seven backend libraries and names the forbidden `beamlet_i18n`/`gettext`/`expo` set.

## Gap judgements

- **Web `errors` domain empty**: accepted as a non-gap. The Web app has no Ecto/changesets and no reachable changeset-backed form, so there is no user-visible text in that domain; the catalogue and `translate_error/1` wiring already exist for the day a changeset form appears.
- **No live re-translation of a mounted LiveView**: accepted. The only real switch is a full-page link, so every product path remounts; no client-side translation is a deliberate consequence of the no-browser-storage rule.

## Residual risks

No browser walkthrough for this change (CSP/theme interaction with the switcher covered only by static/CSP tests). Release-level Chinese coverage rests on the pinned-English `check-cli-release.py` plus manual shipped-CLI checks, so CI would not catch a Chinese-only release regression. `en` msgstrs are intentionally empty. Unlisted reason atoms remain in English inside Chinese sentences; adding a reason without translating it would not fail a test. No physical multi-host, paid-provider or `pre-commit run --all-files` evidence.

No commit, branch, staging or archive operation was performed for this acceptance.
