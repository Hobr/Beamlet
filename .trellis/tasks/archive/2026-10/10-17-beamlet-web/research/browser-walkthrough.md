# Browser walkthrough of the Beamlet Web workbench (local, real browser)

Status: **executed**. The user's earlier "暂不使用浏览器进行验证" deferral was superseded for this run by an
explicit request to try local browser testing. 35 checks were recorded: **34 PASS, 1 BLOCKED, 0 FAIL**.
WA/parent acceptance is **not** marked by this report.

All interaction was real: WebDriver clicks, keystrokes (including Tab/Enter), programmatic scroll position,
viewport resize and screenshots. No LiveView event was injected, no page state was mocked, and
`execute/sync` was used only for layout measurement, scroll position, focus inspection and one CSP probe.

## Capability actually used

| Item | Value |
| --- | --- |
| Driver | `/home/kanade/.cache/selenium/geckodriver/linux64/0.36.0/geckodriver`, `--host 127.0.0.1 --port 19602` (a second owned instance on 19603 was used only for the 390 px attempt) |
| Browser | `/home/kanade/.nix-profile/bin/firefox`, `browserName=firefox`, `browserVersion=158.0`, `platformName=linux`, `moz:firefoxOptions.args=["-headless"]` |
| Capabilities | `binary`, `args`, `prefs` only. `moz:firefoxOptions.profile` was **not** sent (per the parent's gotcha about the base64-ZIP requirement); geckodriver's own isolated temp profile was used and left nothing behind. |
| Isolation | Loopback only, owned ports verified free before start, isolated temp profile per session, one session per run |
| Harness | Python 3 stdlib W3C client written for this run (`browser-assets/wd.py`), no packages installed, no alternate automation framework or agent CLI |

## Endpoint fixture and root cause of the earlier startup failure

Fixture: `.trellis/tasks/10-17-beamlet-web/research/browser-assets/endpoint.exs`
(previous failing fixture preserved at `../10-17-web-workbench/research/browser-assets/endpoint.exs` and its log).

```bash
MIX_ENV=test ERL_FLAGS='+S 2:2' FIXTURE_PORT=19601 FIXTURE_OUT=<owned temp dir> \
  mix run --no-start .trellis/tasks/10-17-beamlet-web/research/browser-assets/endpoint.exs
```

`Application.put_env(:beamlet_web, Beamlet.Web.Endpoint, ...)` and `Application.put_env(:beamlet_web, :host, ...)`
run before `Application.ensure_all_started(:beamlet_web)`; no tracked config was mutated, no `config/*.exs`
or product source was edited. Port 19601, loopback.

**Diagnosis of `invalid_web_host_configuration`.** The failure was *not* in `Host` or `Presets`; Host folds a
`Beamlet.Node` rejection into its own generic error. Step-by-step probes on the real modules showed every
candidate validation passing except `Beamlet.Node.valid_profiles?/2`:
`profile?/2` requires a binary `:capability` label on each profile entry (and the Tool module must be listed in
the Node `allowlist`). The old fixture sent `%{type: :tool, module: ..., settings: %{}}` with no `:capability`,
so `Node.configuration/1` returned `{:error, :invalid_node_configuration}` → Host returned
`invalid_web_host_configuration`. The corrected fixture adds `capability: "tool.slow-echo"` and puts the Tool in
`allowlist: %{tool: [BrowserFixtureTool]}`, plus `environment: "workspace"` on the profile so executor
eligibility (`op.environment in r.environments`) holds.

A second real defect was found and fixed in my own fixture while exercising it: `Model.validate_reply/2`
canonicalises reply calls through `canonical_call/1`, which matches **atom-key** maps only, so a
`%{"id" => ..., "name" => ..., "arguments" => ...}` call map is `{:error, :invalid_reply}` and the turn ends with
no tool call. Fixed to atom keys.

Fixture content (all deterministic, no network provider, no key):

- Node roles `[:interaction, :authority, :executor]`, `model_providers %{"fixture" => BrowserFixtureModel}`,
  Tool profile `slow-echo` (`capability "tool.slow-echo"`, `environment "workspace"`, 2.5 s sleep),
  `pools %{"work" => 4}` so management shows real available-only capacity.
- Catalogue: model `local`, tool `slow-echo` (requires environment `workspace`), environment `workspace`,
  presets `chat` (no tools) and `tool-run` (slow-echo + workspace), authority `local`, `default_authority "local"`.
- A CLI-like external Agent created through the public Agent API (`cli-external-agent`, one completed turn) and
  a parent Agent (`parent-browser`) delegating a long-running child (`child-browser`), both with handles written
  to the owned temp dir so the walker can navigate to their exact workspaces.

Model behaviour is deterministic: `TOOLS` in the task → one `slow-echo` tool call; last message role `tool` →
tool summary plus ~90 context lines and one very long unbreakable token; second and later user turns →
`SECOND-TURN-ACK: <text>`; `HOLD` → a long-running turn used for stop/keep and the child.

## Per-check results

Viewport column is the viewport the browser reported for that check. Screenshots are under
`research/browser-assets/shots/`.

### 1. Desktop 1440x900 and small viewport

| # | Viewport | Action | Observed | Verdict | Screenshot |
| --- | --- | --- | --- | --- | --- |
| 1-desktop-home | 1440x814 inner (1440x900 window) | navigate `/`, measure `documentElement`/`body` scrollWidth vs clientWidth and control rects | doc 1440/1440, body 1440/1440, no horizontal overflow; `#creation` textarea/select/button and search input all `right <= 1440`; sidebar lists `child-browser`, `parent-browser`, `cli-external-agent` (CLI-created instance discovered) | PASS | `01-desktop-home.png` |
| 1d-390-requested | requested 390x844 | `POST /window/rect {width:390,height:844}` and read effective CSS viewport | requested rect came back 500x844; effective inner 500x758; this Firefox build clamps windows to a 500 CSS px minimum width | **BLOCKED** | none |
| 1b-mobile-home | 500x758 inner (narrowest attainable) | resize, navigate `/`, measure overflow and control rects | doc 488/488, body 488/488, no overflow; textarea/select/button/input `right <= 456 < 500`; single-column layout (sidebar above task entry) | PASS | `09-mobile-home.png` |
| 1c-mobile-workspace | 500x758 inner | navigate `/agents/<handle>`, measure conversation region and follow-up controls | doc 488/488; region `clientWidth 412 == scrollWidth 412`, `overflow-x auto`; textarea 422/422; button right 166.85 | PASS | `10-mobile-workspace.png` |

The exact 390x844 requirement is **not** claimed. Four techniques were measured and all clamped to 500 CSS px:
`POST /window/rect 390`, launch arg `-width 390 -height 844`, `MOZ_HEADLESS_WIDTH=390`, and
`layout.css.devPixelsPerPx` 1.3 / 1.4 / 2.0 / 3.0. The 500 px results are a lower bound on the small-screen
layout (below the `lg` 1024 px breakpoint, same single-column branch), not a substitute for 390 px.

### 2. Preset flow

| # | Viewport | Action | Observed | Verdict | Screenshot |
| --- | --- | --- | --- | --- | --- |
| 2a-initial-draft | 1440 | real click on nav `New Agent`, read default control state | preset `chat`; environment control **absent** (`null`); adjust `<details open>`; 1 tool checkbox; model option `Deterministic local model` | PASS | none |
| 2b-environment-conditional | 1440 | real click on the `slow-echo` tool checkbox | environment `<select>` appears with options `["Choose environment", "Fixture workspace"]`, value `""`; checked tools `["slow-echo"]` | PASS | `02-new-agent-environment-visible.png` |
| 2c-environment-removed | 1440 | real click to uncheck the same tool | environment control absent again | PASS | none |
| 2d-preset-switch | 1440 | keyboard-select preset `tool-run` (real click + ArrowDown, verified value) | preset `tool-run`; environment control present with value `workspace`; no "Modified" badge; effective-options line `model local; tools slow-echo; environment workspace; authority local` | PASS | none |
| 2e-adjust-preset | 1440 | type a Name | "Modified from preset defaults" badge appears; name value `Tool runBrowser preset agent` (typing appends to the preset default title) | PASS | `03-new-agent-modified.png` |
| 2f-reset | 1440 | real click `Reset to preset defaults` | badge gone; name back to `Tool run`; preset `tool-run`; environment `workspace` | PASS | none |
| 2g-create-with-enter | 1440 | type hostile task text (`<script>alert(1)</script> TOOLS run`), type a name, press **Enter inside the Name input** (implicit form submission) | navigated to `/agents/xh1LuQyhmbljLK6igExh9d21wwOu1Edt`; `Initial input: Input accepted · Navigation: Available`; `Creation identity: web-RMEGPeFz5OhNlSR7JCFvwt7o · nonode@nohost` | PASS | none |

### 3. Real deterministic model → tool → model, second turn, inspector, long output

| # | Viewport | Action | Observed | Verdict | Screenshot |
| --- | --- | --- | --- | --- | --- |
| 3a-tool-activity | 1440 | observe the workspace while the model dispatches the configured tool | 4 entries; entry `Tool call: slow-echo` present; business state `done` after completion. The live activity card was **not** present at this sample instant (0 cards) | PASS | `04-agent-first-turn-activity.png` |
| 3b-first-turn-output | 1440 | wait for the second model completion | `Tool completed` present; `&lt;script&gt;` in serialised HTML; literal `<script>alert(1)</script>` in `pre.textContent`; 5 `pre` blocks each `scrollWidth == clientWidth` (982/982, 970/970), every `right 1339 <= sectionRight 1396`, computed `white-space: pre-wrap`, `overflow-wrap: break-word`; omission line `Omitted entries: 0; activities: 0` | PASS | `05-agent-first-turn-done.png` |
| 8a-hostile-text-no-dialog | 1440 | `GET /session/{id}/alert/text` after rendering the hostile task | `404 no such alert` (no dialog); text escaped in HTML and rendered as literal text; no script execution indicator | PASS | none |
| 3c-second-turn | 1440 | clear + type into `#follow-up textarea`, real click `Send next turn` | `SECOND-TURN-ACK: second turn from the workbench` rendered; 6 entries; state `done` | PASS | none |
| 3d-live-tool-activity | 1440 | real click `Send next turn` with `TOOLS again`, poll the activity section every 0.2 s | live card `tool slow-echo · pending · Turn 2nJ80AMbjw` while `Business state: running` | PASS | `06-agent-live-tool-activity.png` |
| 3d-child-inspector | 1440 | open `/agents/<parent handle>`, real click the activity `<summary>` to expand, real click `Inspect child (observe only)` | 1 activity card (child running); navigated to `/agents/hLshb...?observe=1`; the inspector shows the child's real input `HOLD child task`; 0 `#follow-up` forms, 0 `Stop`, 0 `Close` buttons | PASS | `11-activity-inspector-open.png` |
| 3e-activity-diagnostics | 1440 | real click `Inspect activity diagnostics` inside the expanded card | navigated to `/admin/diagnostics?handle=m2cgh...&activity=Turn+QBBHKVhiol`; `Retained live context` rendered | PASS | none |

`04-agent-first-turn-activity.png` and `05-agent-first-turn-done.png` are byte-identical (163790 bytes): the
2.5 s tool finished before the first screenshot, so they show the completed first turn. The in-flight activity
card is evidenced by `06-agent-live-tool-activity.png` (tool pending) and `17-workspace-running-before-stop.png`
(model pending).

### 4. Scroll behaviour

| # | Viewport | Action | Observed | Verdict | Screenshot |
| --- | --- | --- | --- | --- | --- |
| 4a-scroll-not-forced | 1440 | set region `scrollTop=0` (reader above bottom), then clear/type and real click `Send next turn` | before: `scrollTop 0`, `scrollHeight 1968`, `clientHeight 448`, indicator hidden; after new activity: `scrollTop 0` (unchanged), `scrollHeight 2440`, indicator `hidden=false` (visible) | PASS | `07-scroll-new-activity-affordance.png` |
| 4b-jump-to-bottom | 1440 | real click `New activity — jump to bottom` | `scrollTop 1992 == 2440-448`, `atBottom true`, indicator hidden again | PASS | `08-scroll-jumped-to-bottom.png` |

### 5. Keyboard

| # | Viewport | Action | Observed | Verdict | Screenshot |
| --- | --- | --- | --- | --- | --- |
| 5a-tab-order | 1440 | blur, then two real Tab passes (9 from page top, 12 after focusing the workspace `h1`), reading `document.activeElement` and computed focus styles | order includes `A` (Beamlet, Nodes, Presets, Diagnostics, New Agent…), `SUMMARY`, the conversation region `DIV[tabindex=0]`, tool-call `SUMMARY`, `PRE`, `TEXTAREA[name=text]`, and `BUTTON` (Send next turn, Stop current turn, Close instance…); 19 stops showed a visible outline ring — `outlineStyle:auto; outlineWidth:3px` (UA) and `outlineStyle:solid; outlineWidth:2px` for `.btn`, plus box-shadow rings on buttons | PASS | `16-keyboard-focus-sequence.png` |
| 5b-enter-activates | 1440 | focus the nav `Nodes` link and press Enter | navigated to `http://127.0.0.1:19601/admin/nodes`; focused element had `outlineStyle:solid; outlineWidth:2px` | PASS | none |

Enter-submit is the creation in 2g (implicit submission from the Name field). Enter inside the multi-line task
textarea (newline instead of submit) was not asserted separately.

### 6. Lifecycle

| # | Viewport | Action | Observed | Verdict | Screenshot |
| --- | --- | --- | --- | --- | --- |
| 6a-leave-and-rediscover | 1440 | navigate away to `/admin/nodes`, return to `/`, real click the surviving Agent in `Live Agents` | agent `web-RMEGPeFz5OhNlSR7JCFvwt7o` still discovered; 8 retained entries; `SECOND-TURN-ACK` still present; state `done` | PASS | none |
| 6b-stop-keeps-instance | 1440 | send a `HOLD` turn, real click `Stop current turn (keep Agent)`, then `Discover now` | `Business state: running` → `stopped`; feedback `Request acknowledged; observe actual state. Stop does not undo external effects.`; the instance is still discovered (`child-browser`, `web-RMEG…`, `cli-external-agent`, `parent-browser`) | PASS | `18-workspace-stopped.png` (running frame: `17-workspace-running-before-stop.png`) |
| 6c-close-requires-confirmation | 1440 | real click `Close instance…`, then `Keep instance` | confirmation block `Close this Agent instance? Leaving this page only unsubscribes.`; instance still rendered and still discovered after `Keep instance` | PASS | `19-close-confirmation.png` |
| 6d-close-ends-instance | 1440 | real click `Close instance…` then `Confirm close instance`, then `Discover now` | `Observation unavailable; instance outcome unknown`, `Business state: Unknown / omitted`; after discovery the id is gone (`parent-browser`, `cli-external-agent`, `child-browser` remain) | PASS | `20-workspace-after-close.png` |

Busy rejection across two tabs/observers was not produced in the browser; only running/stopped/unavailable
feedback was observed here (the LiveView busy path is covered by existing tests, not by this walkthrough).

### 7. Read-only management

| # | Viewport | Action | Observed | Verdict | Screenshot |
| --- | --- | --- | --- | --- | --- |
| 7a-admin-nodes | 1440 | navigate `/admin/nodes` and wait for the owned caller read | `Last observation received`; `Read completeness: complete`; `Configured roles: interaction, authority, executor`; `Registered services: runtime: ready, authority: ready, executor: ready, routes: ready`; `Report: fresh · Source receipt age: 898 ms`; `Capabilities: tool.slow-echo, model.provider:fixture · Environments: workspace`; `Available work: 4` (real capacity, reported as available only); no `#PID` anywhere; scope/limits wording present | PASS | `12-admin-nodes.png` |
| 7b-admin-presets | 1440 | navigate `/admin/presets` | entries `chat: Chat only`, `tool-run: Tool run`, `local: Deterministic local model`, `slow-echo: Slow echo tool`, `workspace: Fixture workspace`, `local: This VM`; `Default authority reference: local`; only button `Refresh observation`; no binding/credential/root values (the string "provider" occurs only in the static sentence "No provider probes; online availability unknown.") | PASS | `13-admin-presets.png` |
| 7c-diagnostics-no-handle | 1440 | navigate `/admin/diagnostics` with no handle | `No exact live handle resolved. Open diagnostics from an existing Agent workspace.`; `Display absent / omitted` | PASS | none |
| 7d-diagnostics-handle | 1440 | navigate `/admin/diagnostics?handle=<parent handle>` | `Observe only. Current context, not a complete timeline…`; `Retained live context` with coverage `live_context`; 0 entries (this parent never had a user turn — only a delegated child) and the live `child … running` activity card; 0 textareas, 0 Stop, 0 Close; 1 link `Open observe-only workbench` | PASS | `14-admin-diagnostics-handle.png` |
| 7e-diagnostics-entries | 1440 | navigate `/admin/diagnostics?handle=<cli external agent handle>` | 2 retained entries containing real content (`external CLI first turn`, `Response to: external CLI first turn`, `context line 1 …`); observe-only wording; 0 textareas; 0 Stop; no `#PID` | PASS | `15-admin-diagnostics-cli-handle.png` |

### 8. Security in a real browser

| # | Viewport | Action | Observed | Verdict | Screenshot |
| --- | --- | --- | --- | --- | --- |
| 8b-csp-and-console | 1440 | read the served CSP header (plain HTTP, separate response), snapshot nonce-bearing inline scripts, register `securitypolicyviolation`, append a nonce-less inline `<script>` | header `default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'self'; form-action 'self'; script-src 'self' 'nonce-…'; style-src 'self' 'unsafe-inline'; img-src 'self' data:`; 1 pre-existing inline script with `getAttribute('nonce') == ""` (spec nonce hiding) and a 24-char base64 `script.nonce`; the nonced theme script ran (`data-theme=light`, `data-theme-source=system`); `window.liveSocket` present and `[data-phx-main]` rendered (so `app.js` loaded under `script-src 'self'`); injected nonce-less script **blocked**: `injectedRan false`, violation `{directive: script-src-elem, blocked: inline}`; no other violation recorded | PASS | `21-csp-probe.png` |

The CSP nonce is generated per response, so the header read through a second plain request carries a different
nonce than the document; the document's own nonce is established by the hidden attribute plus the fact that the
nonced inline theme script executed.

**Browser console log API: BLOCKED.** geckodriver 0.36.0 answers `405 HTTP method not allowed` for both
`POST /session/{id}/log` and `GET /session/{id}/log?type=browser`; console entries cannot be retrieved through
this driver. CSP enforcement evidence was therefore collected in-page via `securitypolicyviolation` instead of
console logs.

### Cleanup

| # | Action | Observed | Verdict |
| --- | --- | --- | --- |
| cleanup | `DELETE /session/{id}` | `{"value": null}`, ok | PASS |

Owned processes were terminated with identity checks (`/proc/<pid>/cmdline` compared before signalling, SIGTERM,
no forced kill): the final run's endpoint `125426` and geckodriver `125428`, plus the earlier owned driver
`101782`, second driver `119432` and endpoint `122072`. After cleanup `ss -ltnp` showed **no** listeners on
19601–19603, no `geckodriver`/`firefox` processes remained, `ls -d /tmp/rust_mozprofile* /tmp/mozrunner*`
returned 0 entries, and the owned fixture temp dir was removed. Machine-readable log:
`research/browser-assets/cleanup.json`. No user process was signalled.

## Defects found and fixed

| Defect | Class | Status |
| --- | --- | --- |
| Old fixture rejected at startup with `invalid_web_host_configuration` | fixture (research asset), not product | **Fixed** — root cause was the missing per-profile `:capability` (and Tool not in `allowlist`) in `Beamlet.Node` configuration; corrected fixture boots and serves the workbench |
| Fixture model returned `%{"id" => …}` string-key calls, rejected by `Model.validate_reply/2` → turn ended with no tool call | fixture (mine) | **Fixed** — atom-key call maps, matching `canonical_call/1` |
| Walker compared the document nonce with a header nonce from a *different* response | harness (mine) | **Fixed** — nonce-hiding + executed-script evidence instead |
| Walker's tab pass started at `h1`, so nav links were never reached | harness (mine) | **Fixed** — two passes (page top, then heading) |
| Walker appended follow-up text to an uncleared textarea | harness (mine) | **Fixed** — clear + verify value before typing |

**No product defect was found** in the workbench or management LiveViews during this walkthrough: no layout
overflow, escaped hostile text, no `#PID`/binding/credential leakage, correct conditional environment,
non-forced scroll with a working new-activity affordance, real stop/keep/close semantics, visible focus rings.
Consequently **no product source was changed and no regression test was added**.

## Gates rerun (on the unchanged product tree)

| Gate | Command | Result |
| --- | --- | --- |
| Web tests | `ERL_FLAGS='+S 2:2' mix test apps/beamlet_web/test` | **59 passed, 5 excluded**, exit 0, 32.7 s |
| Formatting | `mix format --check-formatted` | exit 0, no diff |
| Working tree | `git status --short` | no product file modified by this run; the only new files are untracked research assets under `.trellis/tasks/10-17-beamlet-web/research/browser-assets/` |

No stage/unstage/reset/commit/branch/archive/task-pointer operation was performed.

## Artifacts

- `research/browser-assets/endpoint.exs` — owned fixture (documented failure analysis at the top)
- `research/browser-assets/wd.py` — stdlib W3C WebDriver client
- `research/browser-assets/walkthrough.py` — the 35-check journey
- `research/browser-assets/results.json` — machine-readable per-check evidence (viewport, action, observation, verdict, screenshot)
- `research/browser-assets/shots/01…21-*.png` — 21 screenshots
- `research/browser-assets/endpoint.log`, `driver.log`, `driver-mobile.log`, `cleanup.json`
- Reproduction: the fixture needs `FIXTURE_OUT` pointing at a writable owned temp dir (it writes `handles.json`/`port`);
  the walkthrough needs the same directory plus a live geckodriver port.

## Residual gaps (explicit)

1. **390x844 viewport not observed** — Firefox 158.0 clamps windows to 500 CSS px width on this host; the small-screen
   checks ran at 500x758 inner and are a lower bound, not evidence for 390 px (see check 1d).
2. **No browser console log capture** — geckodriver 0.36.0 returns 405 for the log endpoints; CSP evidence is the
   in-page `securitypolicyviolation` probe plus the executed nonce'd script. Violations that occurred *before* the
   listener was installed are not observable.
3. **Busy/multi-observer conflict in the browser** is unverified: only running/stopped/unavailable states were seen;
   a genuinely busy rejection needs a second tab or external input, which was not produced here.
4. **Scope of the environment** — `MIX_ENV=test`, loopback only, deterministic in-VM provider, no paid provider,
   no physical multi-host and no real CLI binary; the "CLI-like" instance was created through the public Agent API.
5. **First-turn live activity card** was missed at the sampling instant (screenshots 04 and 05 are byte-identical);
   the live card is evidenced during the later tool turn and the `HOLD` turn.
6. **Not covered at all**: text zoom / OS font scaling, colour contrast, screen-reader output, touch/tap targets,
   LiveView reconnect after a real network drop, and CSRF rejection driven through the browser.
7. The fixture's 2.5 s tool and 15-minute `HOLD` sleeps are fixture choices for observability; they are not product
   timings.
