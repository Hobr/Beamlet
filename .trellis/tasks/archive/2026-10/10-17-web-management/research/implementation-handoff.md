# Read-only Web management implementation handoff

Implementation is delivered for parent review; this document does not accept the child or parent, change workflow status, or update shared specifications. Browser validation is explicitly deferred by the user's instruction “暂不使用浏览器进行验证”. No browser, driver, browser endpoint fixture, or visual journey was launched. Existing failed/unverified workbench browser research was preserved.

## Source delivery

Repository root: `/mnt/data/Project/Beamlet`. Exactly these eight source/test paths were authored in this run:

- `apps/beamlet_web/lib/beamlet_web/live/management_reads.ex`: trusted target resolution through Cluster; explicit local target; one public Node.observe read with the original 32-target/8-worker/5-second/1-MiB bounds. A 32-remote allowlist plus local is represented as 33 visible scope entries with the excess entry explicitly unread/limit/unknown, rather than a second read or silent truncation.
- `apps/beamlet_web/lib/beamlet_web/live/management_live.ex`: `/admin/nodes`, `/admin/presets`, `/admin/diagnostics` actions, owned 12-second reads, pending lock, generation fencing, source replacement display, receipt timestamps, last-observation retention on failure, read-only event catch-all, and public node/report/catalogue renderers.
- `apps/beamlet_web/lib/beamlet_web/router.ex`: three LiveView routes in the existing protected browser pipeline.
- `apps/beamlet_web/lib/beamlet_web/live/workbench_live.ex`: retains the current opaque browser handle for diagnostic navigation.
- `apps/beamlet_web/lib/beamlet_web/live/workbench_live.html.heex`: navigation to management and current-Agent diagnostics, plus activity diagnostic links through the shared component.
- `apps/beamlet_web/lib/beamlet_web/components/observation_components.ex`: optional opaque diagnostic handle; source activity/operation/attempt identity labels and links. Existing child inspection behavior remains; diagnostics disables its controls and rejects forged events.
- `apps/beamlet_web/test/beamlet_web/management_live_test.exs`: 12 ordinary tests using actual public Node/Agent/Presets/Handles APIs, bounded rendering fixtures, suspended infrastructure, tracing and monitors.
- `apps/beamlet_web/test/beamlet_web/management_distributed_test.exs`: one real named-peer test for connected trusted roles, bounded suspended-source timeout, and disconnected partial results. Reuses the existing reviewed HostPeer fixture.

No core API, manifest/dependency, shared-spec, host startup, CLI/daemon, database, tracing collector, provider, authorization, or release change was made. Asset build/deploy uses existing source tooling. Parent owns independent review, any shared-spec synchronization, and acceptance.

## MA source evidence

| Criterion | Implemented behavior and evidence |
| --- | --- |
| MA1 | Nodes distinguish connection at read entry, explicit local path, configured roles, registration readiness and separate Runtime report coverage/status/age/capabilities/environments/available quantities. Registered readiness is explicitly not provider health. Missing/stale reports do not prove death; totals/utilization remain unknown. Ordinary tests exercise actual authority-only, executor-only, combined, unconfigured and unavailable Runtime trees. The named management test exercises actual remote facts/disconnection/timeout. Missing/stale/fresh report rendering uses explicitly named public-shape unit fixtures, not private-state injection or claimed normal report admission; existing Node observation tests supply underlying public-core coverage. |
| MA2 | Presets uses precisely Presets.describe(), as creation does. Labels/descriptions, preset defaults/references, Tool environment reference compatibility, default authority and trusted-startup source category are rendered. Empty collections and missing facts remain explicit. Online provider availability is unknown; there are no probes or edits. The parity test compares actual public descriptors, checks the private config sentinel is absent, rejects forged writes and confirms the immutable public catalogue. A failed refresh retains the last descriptor set with unavailable/current-unknown feedback. |
| MA3 | Diagnostics fetches an exact opaque Handles token and uses the repaired OwnedCall observer and shared activities component. Source turn/activity/operation/attempt identities are opaque hash labels; there is no executable-term/PID/Ref decode or browser atomization. An activity key selects only a current source identity; stale keys explicitly have no reconstruction. Current retained entries and activity replace prior projections; missing display clears it. Placement remains unknown unless exposed by source. Workbench and activity links carry handles/opaque keys. Tests cover actual handles, stale same-ID replacement, invalid handles, stale activity identity, Agent survival and observe-only forged commands. |
| MA4 | Only refresh performs a management read; all other events are ignored. No admin mutation route, RPC console, terminal, restart/connect/role/config/recovery event exists. A tracing test observes zero Agent start/input/stop/close, Runtime submit or Node.connect calls during node-page reads and forged controls. HEEx escapes text and does not dump private state/config/bindings/credentials/roots. Existing workbench security/CSP/error-page tests remain included in Web and umbrella gates. Navigation explicitly disclaims authorization. CSP nonce, CSRF, origins, production secrets and dev-only debugging/dashboard gates were preserved. |
| MA5 | One read is admitted while pending. Node reads retain the full public target/worker/time/byte limits; local-inclusive scope overflow is explicit. OwnedCall provides a 12-second outer page deadline, owner monitoring and actual linked worker retirement, without business cancellation claims. Tests exercise duplicate slow refresh, stale-generation results, actual page guardian DOWN while Routes remains suspended, and the owner primitive DOWN before source resume. Observation failures keep explicitly labeled last observations, not silent healthy empty data. No persistence/exporter/history subsystem was added. |

The approved prerequisite observation/preset acceptance, workbench acceptance and independent-check, parent design section 6/plan, child manifest/artifacts and before-dev guidance were loaded. No recursive implement/check agent was launched.

## Verification

Authoritative final gates are `/tmp/management-final/*.log` with separate `.exit` artifacts; commands run from the umbrella root with installed Elixir 1.20.4/OTP 29 and `ERL_FLAGS='+S 2:2'`. The runner uses 240-second per-command limits, separate logs/exits, private named cookies and owned peer cleanup. No paid provider or physical-machine test was run.

All final gates exited 0:

| Command | Final result / artifact prefix under `/tmp/management-final` |
| --- | --- |
| `mix format --check-formatted` | `format`; passed. Test-only alias correction was also checked afterward with scoped `mix format --check-formatted apps/beamlet_web/test/beamlet_web/management_live_test.exs`, `format-after-alias` exit 0. |
| `mix compile --warnings-as-errors` | `compile`; passed. |
| `mix test apps/beamlet_web/test --seed 631927` | `web`; **55 ordinary passed / 5 distributed excluded**. |
| `mix test --seed 631927` | `all`; **278 ordinary passed / 34 distributed excluded**: Harness35, Actions28, Runtime43/6 excluded, Agent26, Node68/20 excluded, Daemon5/2 excluded, CLI18/1 excluded, Web55/5 excluded. |
| `elixir --sname [owned] --cookie [private] -S mix test apps/beamlet_web/test apps/beamlet_node/test --only distributed --seed 631927` | `named`; **25 actual named passed**: Node20/68 ordinary excluded, Web5/55 ordinary excluded. Runtime/Daemon/CLI distributed cases are outside this named gate. |
| `mix credo --strict` | `credo`; 136 files / 1185 modules-functions, no issues. |
| `mix sobelow` | `sobelow`; scan complete without findings. |
| `mix dialyzer --no-check` | `dialyzer`; existing PLT, 0 errors / 0 skipped / 0 unnecessary skips; no PLT refresh. |
| `mix do --app beamlet_web assets.build` | `assets-build`; passed from umbrella root. |
| `mix do --app beamlet_web assets.deploy` | `assets-deploy`; passed from umbrella root, minified/digested output generated. Tool auditing emitted blind-write notices for regenerated gzip static resources; these were notices with successful build/deploy exit codes, not failed source mutations. |
| `git diff --check HEAD -- [eight authored paths]` | `diff-check`; passed for staged plus working content of the touched paths. |

Final ordinary and named logs include the reviewed shared workbench and Node suites. Named peers own teardown; no test/browser endpoint was opened. Source hashing and final status capture ran after all final gates. Reporting shell calls that searched absent/not-yet-created logs returned nonzero in earlier status polling; those search exits are not compile/test/source failures. Later reporting enumerates existing artifacts with pathlib. Completed successful gates were not restarted; the test-file format recheck followed the actual alias-only correction.

## Original failures and remedies

Original logs remain separate; none was overwritten to imply an earlier clean candidate:

- `/tmp/management-focused-initial.log`: 7/8 passed; the new diagnostic test supplied a deterministic binding without its required reply. Fixed the fixture to the valid existing provider schema; no production provider/core relaxation.
- `/tmp/management-focused-third.log`: 9/10 passed; the new service-loss fixture used Beamlet.Runtime as the supervisor child ID. The public Runtime child_spec delegates to SharedSupervisor, so the actual ID is Beamlet.Runtime.SharedSupervisor. Corrected that fixture. `/tmp/management-gates/all.log` captured the same fixture failure in the earlier umbrella snapshot (other applications passed; Web 52/53 plus 5 excluded). It is not final passing evidence.
- `/tmp/management-gates/credo.log`: one strict alias suggestion in the new boundary test. Added the local ManagementReads alias; no suppression or behavior change.
- Earlier intermediate focused results: `/tmp/management-focused-second.log` 8 passed; `/tmp/management-focused-fourth.log` 11 passed; `/tmp/management-focused-bounded.log` 12 passed. Earlier Web gate `/tmp/management-gates/web.log` was 51 ordinary/5 excluded, before the later boundary/ownership/zero-dispatch additions.
- The first named snapshot `/tmp/management-gates/named.log` passed Node 20 actual/68 excluded and Web 5 actual/54 excluded. This predates the final ordinary boundary test and is kept distinct from the final named run.

## Preservation and limits

Entry inventory is `/tmp/management-before.status` (103 porcelain entries) and `/tmp/management-before.index` (binary cached diff). Entry cached-diff SHA256 was `021c0ab1755f756f3946b9d4098349e9e3fd0f1dc09a388d98a2cbcee63e3e5e`. Final inventory, source SHA256 values, status and cached-diff SHA256 are recorded in `/tmp/management-final/inventory.json`. Final inventory has 110 porcelain entries (entry103 → final110). Final cached-diff SHA256 is `1346f922ed27cf2a44abe0ee3de4fb7540a14661c5aaf8298fdd8eebb4571e2e`. The delta includes authored new paths and external additions/staging; it was preserved without restoration. External staging occurred during this run, including newly authored source and existing parent/spec/research artifacts. This worker performed no stage/unstage/reset/commit/push/merge/branch/archive/task-pointer operation and did not restore an older index. Shared specs and historical research were not edited by this worker. Entry inventory did not hash every existing working file, so it is not presented as proof of a whole-tree before/after content-hash comparison.

Browser desktop/mobile/keyboard/scroll/disconnect acceptance remains unperformed by explicit user deferral; no visual acceptance is claimed. Named peers are on the same host and prove neither physical multi-host nor paid-provider behavior. LSP analysis was unavailable/timed out and is inconclusive, even though actual compilation/ExUnit resolve ConnCase successfully. The historical Runtime composition 100ms failure remains unknown/nonblocking by prior parent disposition; current passing suites do not explain its historical cause. No business retry, timeout inflation or weakened success assertion was introduced. Source content can itself echo sensitive text; safe projections do not promise universal secret erasure. Registered readiness is only registration presence, available capacity is advisory, and last observations are explicitly historical when a read fails.


```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Eight authored source/test paths and MA1–MA5 source evidence recorded; final 278 ordinary/25 actual named tests and static/assets gates passed; residual limits explicit."
    }
  ],
  "changedFiles": [
    "apps/beamlet_web/lib/beamlet_web/live/management_reads.ex",
    "apps/beamlet_web/lib/beamlet_web/live/management_live.ex",
    "apps/beamlet_web/lib/beamlet_web/router.ex",
    "apps/beamlet_web/lib/beamlet_web/live/workbench_live.ex",
    "apps/beamlet_web/lib/beamlet_web/live/workbench_live.html.heex",
    "apps/beamlet_web/lib/beamlet_web/components/observation_components.ex",
    "apps/beamlet_web/test/beamlet_web/management_live_test.exs",
    "apps/beamlet_web/test/beamlet_web/management_distributed_test.exs"
  ],
  "testsAddedOrUpdated": [
    "apps/beamlet_web/test/beamlet_web/management_live_test.exs",
    "apps/beamlet_web/test/beamlet_web/management_distributed_test.exs"
  ],
  "commandsRun": [
    {
      "command": "mix test --seed 631927",
      "result": "passed",
      "summary": "278 ordinary passed; 34 distributed excluded"
    },
    {
      "command": "named Web/Node --only distributed --seed 631927",
      "result": "passed",
      "summary": "25 actual passed; 123 ordinary excluded"
    },
    {
      "command": "mix test apps/beamlet_web/test --seed 631927",
      "result": "passed",
      "summary": "55 passed; 5 excluded"
    },
    {
      "command": "format / warning-fatal compile / strict Credo / Sobelow / existing-PLT Dialyzer",
      "result": "passed",
      "summary": "All exit 0; no PLT refresh"
    },
    {
      "command": "umbrella-root assets.build / assets.deploy",
      "result": "passed",
      "summary": "Both exit 0"
    },
    {
      "command": "git diff --check HEAD -- [authored paths]",
      "result": "passed",
      "summary": "Exit 0"
    }
  ],
  "validationOutput": [
    "Authoritative final logs/exits: /tmp/management-final",
    "Original fixture failures retained separately in /tmp/management-focused-initial.log, /tmp/management-focused-third.log and /tmp/management-gates/all.log",
    "Original alias suggestion retained in /tmp/management-gates/credo.log"
  ],
  "residualRisks": [
    "Browser/visual/keyboard/scroll/disconnect verification user-deferred; unperformed.",
    "Same-host named peers do not prove physical-host or paid-provider behavior.",
    "LSP unavailable/timeout is inconclusive.",
    "Historical Runtime composition100ms failure remains unexplained/nonblocking by prior disposition.",
    "32-target read limit includes explicit local; excess configured scope remains visible as unread/unknown."
  ],
  "noStagedFiles": false,
  "diffSummary": "Read-only management routes and public projections, bounded owned reads/diagnostic observation, workbench links and focused/public-core/named tests. Existing external staged changes preserved.",
  "reviewFindings": [
    "No source blocker identified by implementer; independent review/acceptance belongs to parent."
  ],
  "manualNotes": "No browser, recursive agent, staging, reset, commit, branch, task-pointer, shared-spec or archive operation. Parent owns independent review/spec synchronization/acceptance. Existing external index updates preserved."
}
```
