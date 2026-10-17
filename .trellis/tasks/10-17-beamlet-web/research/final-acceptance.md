# Parent integration acceptance — source scope

Result: **PASS for source integration** across all four children and parent AC1–AC8/AC10. AC9 browser items are **user-deferred and NOT performed** ("暂不使用浏览器进行验证"); they are not a pass and not a blocker for the non-browser scope.

Authoritative evidence: research/parent-integration-check.md. All counts below were produced independently on the current tree; earlier child/implementer /tmp artifacts were absent in the reviewer environment and their counts remain historical, not evidence.

## Gate summary

- Parent AC matrix: AC1–AC8 and AC10 satisfied (AC4 and AC8 with stated caveats); AC9 source gates satisfied, browser items unverified by user constraint.
- New parent-level journey `all_role_journey_test.exs`: one enabled interaction+authority+executor Host driven only through WorkbenchLive — preset switch/edit/reset, create + first input, real executor Tool activity/result, second turn on the same Agent, stop-while-pending then survive, leave then survive, rediscovery via Handles, confirmed close; asserts Node.observation reports all three roles. 5/5 stable at distinct seeds.
- Authoritative full suite: **282 passed / 34 excluded, exit 0** (Harness35, Actions28, Runtime43/6, Agent26, Node68/20, Daemon5/2, CLI18/1, Web59/5).
- Web-only: 59 passed / 5 excluded.
- Named Web+Node gate: **152 passed** (Node88 = 68 ordinary + 20 distributed, Web64 = 59 + 5), 25 actual named tests, private cookie, peers cleaned.
- Format, warning-fatal compile (dev+test), strict Credo (137 files), Sobelow, existing-PLT Dialyzer (no refresh), umbrella-root assets build/minify/digest and `git diff --check` passed.
- Dependency/config audit: Web declares only libraries it calls; no Ecto/Repo/migrations/database/transcript/browser-storage/daemon-CLI coupling/new release requirement; router diff is routes-only; ordinary loading starts an empty Host tree; config files unchanged.

## Flake and evidence discipline

Four earlier full-suite attempts each failed one *different* untouched fixture only while unrelated sessions loaded the host (Harness HTTP `{:error, :closed}`; Runtime deadline `:killed` instead of `:unrelated_crash`; Runtime observation synthetic report refreshed). Those apps are unmodified in this delivery; each passed in isolation and the final authoritative run was clean. Assertions/timeouts were not weakened and no business retry was added. Preserve these logs separately; do not present a later green run as proof of the historical Runtime composition 100ms cause.

## Dispositions of review findings

- F1 (medium, child-dir commands): accepted as a pre-existing umbrella manifest inconsistency (`beamlet_web`/`beamlet_cli` declare `beamlet_runtime` — and CLI `beamlet_harness` — with `only: :test` while `beamlet_node` needs Runtime unconditionally). Documentation now points at root-level equivalents in quality-guidelines, the parent plan and child plans, and explicitly forbids dropping the restriction just to make a child command run. Manifests unchanged.
- F2 (low): HOST.md stale cross-child wording corrected by the reviewer.
- F3 (low, duplicated create adapters): retained deliberately. `Agents.create/1` and `WorkbenchCommands.create/3` serve different caller shapes (plain outcome vs guardian-ordered milestones) and both are exercised; consolidating them is future cleanup, not a defect.
- F4/F5 (low spec drift): corrected here — homepage assertion quote, child-dir/asset commands, unrouted `page_controller` wording — plus the whole-Host journey added to the web-host and web-workbench required-test lists.
- F6/F7/F8 (info): recorded as evidence limits, external-load flakes and preserved staged whitespace; no action.

## Remaining limits

Browser desktop/mobile/keyboard/scroll/disconnect, physical multi-host, paid-provider and real CLI-binary-to-Web journeys remain unverified. Local admission can complete after a caller deadline (documented unknown + late idle Agent, no retry). Embedded-authority loss is non-recoverable by source inspection, not by a whole-Host restart test. LSP diagnostics were unavailable/inconclusive.


## Browser walkthrough addendum (2026-10-18)

User requested local browser testing, superseding the earlier deferral. Real walkthrough: **34 PASS / 1 BLOCKED / 0 FAIL**, no product defect. See research/browser-walkthrough.md (per-check evidence, 21 screenshots under research/browser-assets/shots/) and results.json.

Verified in Firefox 158.0 through geckodriver 0.36.0 against an owned deterministic endpoint: desktop layout without overflow; narrow (500x758 inner) single-column layout with contained conversation region; conditional environment add/remove; preset switch/adjust/reset; create by Enter; real model-tool-model turn, completion, second turn and live activity card; observe-only child inspector; retained scrollTop with a working new-activity button back to the bottom; 19 visible keyboard focus stops and Enter activating navigation; leave/rediscovers the same Agent; stop keeps the instance; close requires confirmation and then ends it; all three read-only admin pages show real roles/readiness/report freshness/available-only capacity with no #PID or private values; hostile script text escaped with no dialog; nonce-less inline script blocked by CSP. Web suite re-ran 59 passed/5 excluded; format passed; no product file changed.

Explicitly not claimed: 390px viewport (Firefox clamps windows to 500 CSS px on this host; four techniques tried, so 500px is a lower bound, not 390px evidence); browser console logs (driver returns 405 for log endpoints; CSP evidenced in-page via securitypolicyviolation); busy/multi-observer rejection in the browser; touch, screen-reader, colour contrast, zoom/font scaling, real network-drop reconnect and browser-driven CSRF rejection. Physical multi-host, paid providers and real CLI-binary journeys remain unverified. The historical Runtime composition 100ms failure remains unknown/nonblocking.

No commit, branch, staging, archive or task-status change was performed. Finish steps (commit plan, task lifecycle, journal) require separate user authorization.