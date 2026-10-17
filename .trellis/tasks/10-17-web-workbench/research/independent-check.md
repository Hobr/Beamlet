# Independent workbench review

Recommendation: **source engineering checks pass after the repairs below; withhold complete WA1–WA6 / child acceptance because WA4 actual browser interaction remains outstanding.** This report does not mark child or parent acceptance, change task status, or synchronize shared specifications.

## Scope and preservation

Read the child check.jsonl and every referenced specification/research file, child PRD/design/implementation plan, approved parent PRD/design/plan, implementation-handoff.md, and prerequisite acceptance/contracts. Reviewed all 11 authored paths listed in that handoff, including actual staged/working content and relevant generated JS/static assets. Read public Agent, discovery/Cluster, Presets, Handles and Web adapter implementations; previously accepted host files in the HEAD diff were prerequisites, not attributed to this workbench delivery.

Entry inventory: `/tmp/workbench-review-entry.json`; final inventory: `/tmp/workbench-independent/preservation-final.json`. Each records porcelain status, binary cached-diff SHA256 and source hashes. Entry and final each contain 97 status entries. Exactly five source/test paths changed relative to entry, all listed below. All other inventoried files, including historical Runtime evidence whitespace, shared specs, prerequisite sources, task artifacts and staged static resources, retained their content hashes.

Entry cached-diff SHA256: `a56133f9df8c6b2bb16625a0d91d3703b0f152d5532378e05433144a437a776e`.
Final observed cached-diff SHA256: `021c0ab1755f756f3946b9d4098349e9e3fd0f1dc09a388d98a2cbcee63e3e5e`.
External index updates occurred during review: the initially untracked handoff became staged and reviewed source changes subsequently became staged. These updates were preserved. This reviewer performed no stage/unstage/reset/commit/branch/archive/task-pointer/shared-spec operation and did not restore an earlier index snapshot.

## Findings repaired

1. **Discovery trust and completeness** — `workbench_commands.ex:6`: querying `Node.list(:connected) |> Enum.take(31)` ignored the deployment allowlist and silently omitted excess connected peers. Discovery now uses configured `allowed_nodes` through public `Cluster.connected/1`, excludes the explicit local target from the remote aggregate, and does not truncate the configured set (at most 32). A local `not_authority` is a confirmed local capability absence and no longer incorrectly makes interaction-only discovery incomplete. Other local failures remain explicit and incomplete. The real named test now verifies a connected but unallowlisted authority is excluded, then the allowlisted exact instance is discovered and opened. Local non-authority complete-empty behavior has a permanent test. Completeness covers local plus configured connected discovery scope, not disconnected/unconfigured authorities.

2. **Caller/sink retirement and ordered creation feedback** — `owned_call.ex:6`, `workbench_commands.ex:39`: original guardians could finish after merely sending kill, without observing linked caller/sink termination. Waiting for previous cleanup also occupied the guardian, and a timeout killed the previous guardian without establishing its sink's termination first. Guardians now consume the actual linked EXIT before reporting terminal outcomes or completing retirement. Previous-observer waiting runs in the linked sink, leaving its guardian responsive to owner death; the previous guardian itself bounds sink cleanup at 6 seconds and exits only after sink termination. Replacement subscribes after previous guardian DOWN. Creation identity, confirmed Ref and input outcomes now pass through the same guardian that sends terminal/deadline feedback, preserving order even when a deadline interrupts the worker. New regression checks ordered milestones, actual worker death at terminal delivery, and owner loss during previous retirement with the actual Agent suspended until helper DOWN assertions pass. Existing suspended-admission and 16-second UI-deadline tests still establish no business retry and late idle creation.

3. **Discovery concurrency and stale observer errors** — `workbench_live.ex:78`: repeated refresh could spawn overlapping reads, and discovery failure was silently ignored. One discovery is now admitted per current generation, with explicit incomplete/unavailable feedback on failure. Observation-unavailable messages now match both generation and selected Ref; a failure from another source cannot clear current display. Permanent regression covers the duplicate lock and stale error fence.

4. **Hidden environment remained effective** — `workbench_live.ex:305`: deselecting Tools could hide the environment control while retaining its old effective environment. Draft updates now clear environment when no selected Tool requires it. An actual LiveView creation regression starts with an environment-requiring Tool, deselects it, creates a chat Agent, and checks real public display metadata has no environment and no Tools.

5. **Exact descriptor rejection feedback** — `workbench_live.ex:158`: attach errors were wrapped in `{:attached, error}` and fell through to generic unknown-command feedback. Known stale/not-found/unavailable/timeout/limit/non-authority attachment outcomes now retain their distinct static reason and instruct explicit discovery. The replacement regression preserves an old discovered descriptor, replaces the real same-ID Agent, clicks the old entry and asserts `stale_agent` without opening the replacement.

Changed paths:

- `apps/beamlet_web/lib/beamlet_web/live/owned_call.ex`
- `apps/beamlet_web/lib/beamlet_web/live/workbench_commands.ex`
- `apps/beamlet_web/lib/beamlet_web/live/workbench_live.ex`
- `apps/beamlet_web/test/beamlet_web/workbench_live_test.exs`
- `apps/beamlet_web/test/beamlet_web/workbench_distributed_test.exs`

## WA evidence and qualification

| Area | Independent result |
| --- | --- |
| WA1 | Task-first form, fresh preset reset, modified options, public authority selection, conditional environment and immutable model configuration inspected. Actual creation/duplicate-admission/reset/missing-Presets/hidden-environment cases pass. Confirmed Ref is retained before input/navigation; separate feedback survives navigation failure. Unknown outcomes are not automatically resent. |
| WA2 | Explicit local discovery, allowlisted connected remote discovery, exact descriptor and complete Ref/incarnation checks inspected. Actual external local and named remote instances open; old descriptor and old handle reject same-ID replacement. Complete-empty local non-authority differs from incomplete/unavailable results. Browser shows public authority names, never PID/Ref structures. |
| WA3 | Real deterministic Model → two simultaneously held Tools → Model, then a second turn, executes through public core APIs. Actual delegated child opens with commands hidden and server event guard observe-only by default. Replacement display retains source-derived entry/turn labels, not browser-arrival turn reconstruction. Missing display clears previous content; stale generation/Ref responses cannot repaint it. |
| WA4 | Source projections/output are bounded; truncation is visible; scroll hook and responsive/focusable structure inspected. **Actual desktop/mobile/keyboard/scroll/disconnect browser walkthrough was not performed and remains a blocking acceptance gap.** |
| WA5 | All LiveView callbacks inspected for blocking operations, including catalogue loading, handle opening, discovery and observation switching. Blocking public reads/commands occur in owned workers/sinks, not callbacks. Callers have finite UI deadlines and actual linked exit observation. Duplicate pending commands/generations are fenced. Sink itself subscribes and acks after LiveView consumption; it forwards one snapshot while waiting for consumption, leaving source credit/coalescing bounded (up to 16 outstanding source snapshots). Switching/owner loss retires observation only. Actual busy/stop survival/close confirmation/leave survival and suspended-admission tests pass. No automatic business retry or claimed external rollback. |
| WA6 | Escaped HEEx/plain text; no raw private config, roots, PID/Ref rendering, new transcript store, arbitrary atom decoding, private process reads or business recovery. Preset resolution remains worker-local. CSP nonce/CSRF pipeline, default socket origin behavior, dev-only diagnostics and safe error renderers inspected and regression tests pass. Credential/config/root sentinels absent from inspected final worker and independent logs. Tool/provider content can itself echo sensitive data; no universal erasure promise. |

## Verification and evidence chronology

Authoritative **repaired final candidate** logs and separate exit artifacts are `/tmp/workbench-independent/reviewed-*.log` and `.exit`. Every command below exited 0, using installed Elixir 1.20.4 / OTP 29 with `ERL_FLAGS='+S 2:2'`:

| Command | Final result |
| --- | --- |
| `mix test apps/beamlet_web/test --seed 631927` | **43 passed / 4 distributed excluded** |
| Named `elixir --sname [owned] --cookie [private] -S mix test apps/beamlet_web/test --only distributed --seed 631927` | **4 actual named passed / 43 ordinary excluded** |
| `mix format --check-formatted` | passed |
| `mix compile --warnings-as-errors` | passed |
| `mix credo --strict` | 132 files, 1150 mods/functions, no issues |
| `mix sobelow` | scan complete, no findings |
| `mix dialyzer --no-check` | existing dev PLT; 0 errors / 0 skips; no refresh |
| `git diff --check -- apps/beamlet_web` | passed for working changes |

Five ordinary regressions were added; existing exact-replacement and named tests were strengthened. Earlier independent candidate artifacts remain separate: `web` 42/4 excluded and `named` 4/42 excluded; subsequent `final-web` 43/4 and `final-named` 4/43 preceded the final stale-attach regression extension. Two intermediate strict Credo failures were alias suggestions in newly touched code/tests; fixed without suppression. The `reviewed-*` gates are authoritative for the delivered source.

Inspected retained worker artifacts under `/tmp/workbench-checks`: `web-release` **38 ordinary / 4 excluded**, `named-release` **4 actual named / 38 excluded**, and release compile/format/Credo/Sobelow/existing-PLT Dialyzer/assets-build/assets-deploy all exit 0. `all-verified` sums to **261 ordinary / 33 excluded** across the umbrella; it predates the worker's final Web feedback reset and all independent repairs. It is earlier evidence, not a final repaired umbrella claim. No new umbrella count is inferred. No JS/HEEx/static source changed in this review, so assets were inspected against retained successful build/deploy evidence rather than gratuitously rebuilt. Language-tool availability warnings were inconclusive and are not reported as clean LSP coverage.

Commands ran detached with per-command 240-second caps and separate logs/exits. Named cookies were generated privately and not printed; peer fixtures own their cleanup. No paid provider, physical machine or release rebuild claim.

## Browser blocker and residual risks

The callable tool inventory in this review exposes file/shell and supervisor coordination operations; it has no browser navigation/control tool or tool-discovery interface that can load one. Independently checked executables: Firefox exists, geckodriver and chromedriver do not. Node resolution found Playwright, Puppeteer and selenium-webdriver unavailable. Screenshot-only capability in the parent cannot perform the required interaction. No driver installation, alternate provider, ad-hoc browser CLI workaround or dependent browser acceptance was attempted. WA4 requires a subsequent authorized session with an existing working browser-control capability.

No remaining source blocker was identified after repairs and final gates. Recommend accepting the source engineering review evidence for WA1/WA2/WA3/WA5/WA6 while **keeping overall workbench acceptance pending WA4**. Parent owns final integration, acceptance and any shared-spec updates. Historical Runtime composition100ms failure remains unexplained/nonblocking by prior disposition; these focused runs do not explain it. On recurrence collect correlated outcome/timing facts without timeout inflation, weaker success assertions or business retries. Local queued creation can still complete after caller death; known identity/unknown feedback and explicit discovery are intentional. Same-host named tests do not establish physical deployment, paid-provider behavior or a manual browser journey.
