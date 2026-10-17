# Workbench implementation handoff

Source delivery for parent independent review; this report does not mark WA acceptance, modify shared specifications, or complete the task lifecycle. **WA4 actual browser walkthrough remains blocked.**

## Scope and preservation

Loaded workbench implement.jsonl, its referenced specifications/research, child PRD/design/plan, parent PRD/design/plan, and preset acceptance/independent-check. Applied `.agents/skills/trellis-before-dev/SKILL.md`. Inspected adjacent Phoenix/Agent/Node contracts and tests before implementation. Used existing public Agent APIs, preset resolution and exact Handles semantics. No core, management, catalogue API, database, SPA, daemon/CLI dependency or new Tool/system-prompt implementation.

Source paths authored:

- `apps/beamlet_web/WORKBENCH.md`
- `apps/beamlet_web/assets/js/app.js`
- `apps/beamlet_web/lib/beamlet_web/router.ex`
- `apps/beamlet_web/lib/beamlet_web/components/observation_components.ex`
- `apps/beamlet_web/lib/beamlet_web/live/owned_call.ex`
- `apps/beamlet_web/lib/beamlet_web/live/workbench_commands.ex`
- `apps/beamlet_web/lib/beamlet_web/live/workbench_live.ex`
- `apps/beamlet_web/lib/beamlet_web/live/workbench_live.html.heex`
- `apps/beamlet_web/test/beamlet_web/controllers/page_controller_test.exs`
- `apps/beamlet_web/test/beamlet_web/workbench_live_test.exs`
- `apps/beamlet_web/test/beamlet_web/workbench_distributed_test.exs`

Asset build/deploy also produced compiled/digested static outputs. Seven visible generated static files (favicon digest, logo digest/gzip and robots digest/gzip) became externally staged. Kept these rather than deleting staged content. No manifest, lock, host adapter or shared specification changes were authored here.

Entry inventory is in the tool transcript and `/tmp/workbench-index-before.patch`. Initial binary index comparison still matched `/tmp/workbench-index-after.patch` at 00:24. By 00:26 external staging had added this worker's files and digest artifacts (`/tmp/workbench-index-current.patch`). This worker performed **no stage/unstage/reset/commit/branch/merge/archive/pointer operations** and preserved the externally changed index. Final source hashes: `/tmp/workbench-checks/source-inventory.json`. The global cached whitespace check finds pre-existing trailing whitespace in Runtime historical evidence logs; scoped workbench whitespace is clean. Do not rewrite those evidence logs as incidental cleanup.

## Delivered behavior and evidence map

| Requirement | Source and executed evidence | Remaining qualification |
| --- | --- | --- |
| WA1 | `/`, `/agents/new`, `/agents/:handle` are verified LiveView routes. Public preset selection applies defaults; adjustments/reset/modified marker, conditional environment, authority, capability/effect summary and disabled missing configuration. Missing Presets returns explicit pre-dispatch unavailability. Tests exercise form creation, duplicate clicks while actual admission is suspended, immutable reset and missing configuration. | Parent independently reviews final UX and acceptance. |
| WA2 | Explicit local `Agent.list(node())` plus connected-remote aggregation; search shows public ID and authority; browser keys map to exact private descriptors; opening uses Handles lookup/incarnation validation. Actual externally created local Agent and named remote Agent are discovered/opened. Tests reject a same-ID replacement and show remote observer loss without clearing business ownership. | Same-host peers only; no physical machine or paid provider claim. |
| WA3 | Shared escaped ObservationComponents and replaceable current snapshot display. Source turn references and entry IDs are opaque correlation labels. Real Model -> two concurrent held Tools -> Model -> second turn is exercised using public core APIs. Actual `Agent.delegate` exposes a child inspector; opening that exact child defaults observe-only with commands hidden. Parameters/results/truncation/placement unknown are facts, not fabricated timeline/reasoning/token streaming. | Projection is current retained context and activities, never complete history. |
| WA4 | HEEx/DaisyUI responsive layout, focusable conversation scroll region and bounded scrollable outputs. DOM-only FollowContext hook follows bottom only while reader is there; otherwise new-activity button. Actual long Tool fields show truncation. Snapshot absence clears display; generation fences reject old snapshots. | **No actual desktop/mobile/keyboard/scroll browser walkthrough.** Browser tools are absent in this session; Firefox is installed, but Playwright, Puppeteer and Selenium drivers are unavailable. No driver installed and no alternate provider/browser workaround attempted. WA4 visual acceptance remains outstanding. |
| WA5 | Owned callers have finite 16s creation / 8s ordinary UI deadlines and owner-loss cleanup. Identity is reported before start, confirmed Ref before input/navigation. Caller death is explicitly not cancellation. Duplicate submit locks and generation fences; confirmed creation survives Handles failure. One selected subscription, sink-owned ack only after LiveView consumption, previous sink retired before replacement. Stop preserves instance; close independently confirms; leaving only observes/unsubscribes. Actual 16s UI deadline proves later queued local creation remains discoverable and idle, without input/retry. Actual external busy, stop survival, observer teardown survival, delayed admission after actual caller DOWN and confirmed close tested. | Remote cancellation/external-effect rollback are never promised. |
| WA6 | No stored transcript/event accumulator, private resolver/binding inspection, raw term rendering or browser Ref/PID/config fields. Hostile script content is escaped; private config/credential/root sentinels absent from final Web/focused logs and rendered assertions. CSP nonce, CSRF/origin pipeline, error-page and development gating tests retained; only scaffold home copy assertion changed. Existing flash/disconnect component reused. | Trusted provider/Tool text may itself echo sensitive content; no universal secret-erasure claim. |

## Lifecycle implementation notes for reviewer

`OwnedCall` places a linked blocking worker under a separate guardian that can process finite deadlines and owner DOWN while the worker is suspended in local supervisor admission. Creation milestones are generation/command-tag fenced. Terminating a caller cannot retract queued start requests. The UI keeps the identity for explicit discovery and never retries. Narrow Presets exit handling distinguishes pre-dispatch configuration unavailability.

Creation orchestration deliberately reports confirmed Ref before the one initial input and navigation call; these outcomes are independent. Known Ref remains private server state and remains selected if navigation fails. Browser payload contains public IDs/text and opaque navigation/correlation keys only. Handles are navigation, not authorization.

The subscription sink itself calls subscribe/ack/unsubscribe. It sends one snapshot to LiveView and waits for consumption before ack, preserving source credit/coalescing rather than allowing an unbounded UI mailbox transcript. Retirement removes observation only. Switching waits for prior guardian cleanup before attaching; process monitor also reports Agent/remote loss. Projection absence replaces old display with nil. No private Agent state read is used in product source.

## Checks and counts

Authoritative logs and separate exit files: `/tmp/workbench-checks`. Commands use installed Elixir1.20.4/OTP29 with `ERL_FLAGS='+S 2:2'`; named checks use a new private cookie passed explicitly, never recorded in this report. Owned peer fixtures clean up via standard-IO peer control. Each detached command has a 240s total cap; calls used to inspect progress remain short.

Final delivery gates (all exit **0**, final source including feedback reset when deliberately switching instances):

| Command | Actual result | Evidence |
| --- | --- | --- |
| `mix test apps/beamlet_web/test --seed 631927` | **38 ordinary passed / 4 distributed excluded** | `web-release.log/.exit` |
| Named `elixir --sname [owned] --cookie [private] -S mix test apps/beamlet_web/test --only distributed --seed 631927` | **4 actual distributed passed / 38 ordinary excluded** | `named-release.log/.exit` |
| `mix compile --warnings-as-errors` | passed | `compile-release.log/.exit` |
| `mix format --check-formatted` | passed | `format-release.log/.exit` |
| `mix credo --strict` | 132 files,1144 mods/funs, no issues | `credo-release.log/.exit` |
| `mix sobelow` | scan complete, no findings | `sobelow-release.log/.exit` |
| `mix dialyzer --no-check` | 0 errors / 0 skips, existing dev PLT, no refresh | `dialyzer-release.log/.exit` |
| `mix assets.build` and `mix assets.deploy`, umbrella root | both passed; Tailwind/DaisyUI/esbuild and digests produced | `assets-build-release.log/.exit`, `assets-deploy-release.log/.exit` |
| Workbench scoped cached and working diff whitespace | passed | final tool output / `scoped-diff.log/.exit` |

Full umbrella `mix test --seed 631927` passed **261 ordinary / 33 distributed excluded**, exit0 in `all-verified.log/.exit`: Harness35, Actions28, Runtime43/6excluded, Agent26, Node68/20excluded, Daemon5/2excluded, CLI18/1excluded, Web38/4excluded. This snapshot immediately preceded the final Web-only reset of command feedback/drafts when deliberately switching instances; that final adjustment was rechecked by all final delivery gates above. No extrapolated new umbrella count is claimed. Historical Runtime composition100ms failure did **not** recur in either successful umbrella run; its cause remains unknown.

Earlier snapshots are separate: prerequisite Web25/3excluded; initial implementation Web25/3excluded; first successful focused workbench3, then6,11,12 tests; `all-delivery` **259/33excluded** with Web36; standalone `web-verified` **37/4excluded** before the final added slow-sink regression, while final umbrella and final standalone Web both actually execute38. Final added ordinary cases are13; final added named case is1. Early named verified4/37excluded preceded the slow-sink addition; final named release4/38excluded is authoritative. All expected exclusions are retained.

Final13 ordinary workbench cases exercise: actual concurrent Tool chain and second turn; finite caller deadline/owner loss; controlled duplicate creation; late local admission after caller DOWN; exact replacement/observer loss; missing Handles preserving Ref and input; clearing absent display and old-generation rejection; actual external busy + stop survival; real delegated child observe-only; Presets absence before dispatch; actual16s UI deadline + explicit late discovery; preset defaults/reset immutability; sink credit backpressure and leave while Agent still running. These use real public core operations. The supplemental replacement test uses a real public snapshot then removes display to exercise the consumer's omission branch; it does not substitute a mocked Tool flow.

No browser interaction was performed. `command -v firefox` finds Firefox; session tools have no browser-control interface, and Node resolution reports Playwright/Puppeteer/Selenium unavailable. Browser acceptance remains concretely blocked. Paid provider tests were deliberately not invoked.

## Original failures and remedies

- Initial test fixture syntax (`receive after` without `do`) failed format/test. Corrected syntax; original `live-first.log` retains the failure.
- `live-second.log`: local discovery was unavailable because non-distributed local nodes are not included by Cluster.connected. Corrected Web composition to explicit local list plus remote aggregation; core untouched.
- Early duplicate test tried submitting a DOM form after confirmed creation had already replaced that form. Controlled actual suspended admission now fences duplicate clicks before release. The first error remains in the session tool transcript; its early `web-final.log` filename was later reused by the final runner, so that full original file is not retained. No claim of complete original-log retention is made.
- `web-final2.log`: a supplemental projection test omitted the required Agent ID. Fixture corrected without weakening core validation.
- `all-tests.log`: catalogue load Ready status could overwrite stale-open feedback. Kept unavailable/stale feedback separate from asynchronous load status; regression now passes.
- First child-directory asset invocations failed standalone dependency/lock resolution (`assets-build.log`, `assets-deploy.log`). Same commands from umbrella root use shared project configuration and succeed; no deps/lock modifications.
- `named-delivery.log`: test called local Process.alive? on remote PID. Corrected to the peer's actual is_process_alive call; no provider/CLI substitution.
- `all-final.log` / `named-final.log`: making the peer fixture self-contained omitted Phoenix.ConnTest.get/2 needed by LiveViewTest macro. Added the explicit import; preserved failed logs. LSP initially reported ConnCase unavailable, while test-context compile and `Code.ensure_loaded?` proved the support module loads; final peer fixture uses explicit ExUnit/ConnTest setup. LSP availability remains incomplete, not a global clean diagnostic claim.
- Early strict Credo reports retained in `credo-first.log`/`credo-second.log`; corrected alias ordering and nesting rather than suppressing checks.

## Residual risks / next owner

- Parent owns independent full-scope review, shared-spec synchronization and acceptance. No WA checkbox or task status was marked here.
- Browser UX walkthrough is blocked as described above; source/build/test evidence cannot substitute for actual desktop/mobile/keyboard/scroll interaction.
- Local admission can finish after owner/caller DOWN; explicit unknown identity and no retries are intentional. Unknown input/navigation must not be treated as proof of business cancellation.
- Historical Runtime composition100ms failure remains unexplained and previously dispositioned nonblocking. No timeout increase, weakened success assertion or business retry was added. Check final run outcomes below; no historical root-cause conclusion follows from a passing run.
- Named automation is same-host only. No paid-provider, physical-host, release-closure rebuild, full pre-commit benchmark/SBOM or browser acceptance claim. Core/release closures were not changed.
- Web restart invalidates ephemeral navigation. Embedded authority Agents may be lost; remote surviving Agents can be rediscovered. No replay/recovery/persistent history promised.

## Structured delivery report

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Implemented scoped Web workbench and recorded final checks, original failures and browser/physical/provider limitations in this handoff."
    }
  ],
  "changedFiles": [
    "apps/beamlet_web/WORKBENCH.md",
    "apps/beamlet_web/assets/js/app.js",
    "apps/beamlet_web/lib/beamlet_web/router.ex",
    "apps/beamlet_web/lib/beamlet_web/components/observation_components.ex",
    "apps/beamlet_web/lib/beamlet_web/live/owned_call.ex",
    "apps/beamlet_web/lib/beamlet_web/live/workbench_commands.ex",
    "apps/beamlet_web/lib/beamlet_web/live/workbench_live.ex",
    "apps/beamlet_web/lib/beamlet_web/live/workbench_live.html.heex",
    "apps/beamlet_web/test/beamlet_web/controllers/page_controller_test.exs",
    "apps/beamlet_web/test/beamlet_web/workbench_live_test.exs",
    "apps/beamlet_web/test/beamlet_web/workbench_distributed_test.exs"
  ],
  "testsAddedOrUpdated": [
    "apps/beamlet_web/test/beamlet_web/workbench_live_test.exs",
    "apps/beamlet_web/test/beamlet_web/workbench_distributed_test.exs",
    "apps/beamlet_web/test/beamlet_web/controllers/page_controller_test.exs"
  ],
  "commandsRun": [
    {
      "command": "mix test apps/beamlet_web/test --seed 631927",
      "result": "passed",
      "summary": "38 passed, 4 distributed excluded; web-release artifacts"
    },
    {
      "command": "named Web test --only distributed --seed 631927",
      "result": "passed",
      "summary": "4 actual distributed passed, 38 ordinary excluded; named-release artifacts"
    },
    {
      "command": "mix test --seed 631927",
      "result": "passed",
      "summary": "261 passed, 33 excluded before final Web-only feedback clearing; final Web gates repeated"
    },
    {
      "command": "format; warning-fatal compile; strict Credo; Sobelow; existing-PLT Dialyzer; assets.build; assets.deploy",
      "result": "passed",
      "summary": "All final release artifacts exit0"
    },
    {
      "command": "Desktop/mobile/keyboard/scroll browser walkthrough",
      "result": "not-run",
      "summary": "No callable browser-control tool or installed automation driver; Firefox alone available"
    }
  ],
  "validationOutput": [
    "Final Web: 38 passed / 4 excluded",
    "Final named: 4 passed / 38 excluded",
    "Existing-PLT Dialyzer: 0 errors / 0 skips; no refresh"
  ],
  "residualRisks": [
    "WA4 actual browser walkthrough outstanding",
    "Parent independent review/shared-spec synchronization/acceptance outstanding",
    "Local creation can outlive caller; unknown identity discovery required, no retry",
    "Historical Runtime composition100ms failure remains unknown, did not recur",
    "Same-host named only; no paid-provider or physical-host evidence",
    "Externally staged files/index preserved; global cached whitespace contains unrelated historical logs"
  ],
  "noStagedFiles": false,
  "diffSummary": "11 Web source/test/doc paths plus generated static outputs; task-first routes, preset adjustment, exact discovery, owned commands and sink, source-authoritative displays, child inspector, controls and DOM scroll hook.",
  "reviewFindings": [
    "blocker: WA4 browser walkthrough unperformed due missing browser-control infrastructure; no source blocker identified by worker checks"
  ],
  "manualNotes": "No staging/unstaging/reset/commit/branch/merge/archive/pointer/shared-spec operations by this worker. External index changes were observed and preserved. Parent owns independent acceptance; this report attests handoff completeness only."
}
```
