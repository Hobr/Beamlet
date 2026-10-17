# F3 Actions credential policy repair

F3 is repaired in the Actions lane on `feat/agent-model-credentials`, baseline `18137b1`. This writer changed only the two Actions files below and this new handoff. The original `check-report.md`, previous handoffs, sibling apps, deployment/spec files and task state are preserved. No staging, commits, branch/dependency changes or live/paid calls.

## Root cause and exact policy

`Actions.credential_data?/2` compared map keys directly against lowercase `root` and `workspace_root`. The independent Harness validator compares `String.downcase(key)` against those labels. Actions therefore admitted mixed/uppercase labels that Harness rejected, recursively including maps within lists.

Actions now applies `String.downcase/1` after confirming the key is a valid UTF-8 binary, at the existing recursive map boundary. Only normalized exact `root` and `workspace_root` labels are rejected. There is no trimming, substring matching, atomization or mutation of credential keys/values. Non-root credential labels such as `api_key`, `TOKEN`, `Credentials`, `password`, `authorization`, `root_token`, `workspace_root_id` and `rooted` remain valid. Errors remain `{:error, :invalid_operation}` with no credentials included.

The independent validators remain independent: no Harness/Jason/sibling dependency was added to Actions; its tests use only Actions. The optional scratch comparison loads already compiled Harness from root Mix with `--no-compile --no-start`.

## Changed paths

- `apps/beamlet_actions/lib/beamlet/actions.ex`: normalize only the dedicated credential root-label comparison.
- `apps/beamlet_actions/test/beamlet/actions_test.exs`: 18 separately named rejection tests (six lower/mixed/upper root labels times top/nested/list locations), plus one allowed-label test covering 24 vectors at those same locations. Rejected vectors exercise `credentials?/1`, `Operation.new/1` and direct `Operation.validate/1`; accepted vectors also verify unchanged credentials.
- `.trellis/tasks/10-17-agent-model-credentials/repair-actions.md`: this report.

The rejection labels are `root`, `Root`, `ROOT`, `workspace_root`, `Workspace_Root`, `WORKSPACE_ROOT`. Nested/list vectors include intervening `session` and `credentials` containers so recursion is exercised beyond a single level.

## Verification and preserved logs

All Mix commands used `ERL_FLAGS='+S 2:2'`. Logs are separate and were not overwritten. Scratch script: `/tmp/beamlet-actions-repair-probe.exs`.

| Directory | Command after ERL_FLAGS | Actual result | Log under `/tmp/` |
| --- | --- | --- | --- |
| Actions app, before source repair | `mix test --only credential_root_policy --seed 631927` | Expected failure: 7/19 passed, 12 failed, 9 excluded; all mixed/uppercase root cases accepted incorrectly | `beamlet-actions-repair-prefixed-tests.log` |
| Root, before source repair | `MIX_ENV=test mix run --no-compile --no-start /tmp/beamlet-actions-repair-probe.exs` | Expected failure: 12/42 vectors disagreed; Harness rejected all blocked labels, Actions admitted the mixed/uppercase ones | `beamlet-actions-repair-prefixed-probe.log` |
| Actions app, after repair | `mix test --seed 631927` | **28 passed**, no exclusions; 9 existing tests plus 19 new tests | `beamlet-actions-repair-tests.log` |
| Root, after repair | `MIX_ENV=test mix run --no-compile --no-start /tmp/beamlet-actions-repair-probe.exs` | **42 vectors, 0 failures**: 18 blocked and 24 allowed; both validators agree with expected policy | `beamlet-actions-repair-probe.log` |
| Root | `mix format --check-formatted apps/beamlet_actions/lib/beamlet/actions.ex apps/beamlet_actions/test/beamlet/actions_test.exs` | Passed | `beamlet-actions-repair-format.log` |
| Actions app | `mix compile --warnings-as-errors` | Passed, exit 0 | `beamlet-actions-repair-compile.log` |
| Root, initial Credo invocation | `mix credo --strict --files-included 'apps/beamlet_actions/{lib,test}/**/*.{ex,exs}'` | Passed, but flag did not narrow scope: scanned 82 files; not claimed as focused evidence | `beamlet-actions-repair-credo.log` |
| Root, corrected focused invocation | `mix credo --strict 'apps/beamlet_actions/{lib,test}/**/*.{ex,exs}'` | Passed: 5 Actions source/test files, 69 checks, no issues | `beamlet-actions-repair-credo-focused.log` |
| Root | `git diff --check` | Passed | `beamlet-actions-repair-diff-check.log` |
| Root | `git diff --cached --name-only` | Empty; no staged files | `beamlet-actions-repair-staged.log` |

A SHA-256 preservation check compared 273 pre-existing files outside the two repair source/test paths and this handoff against a snapshot taken before edits: zero changes. This includes the initial review report and other owners' existing changes. Evidence: `/tmp/beamlet-actions-repair-preservation.json` and `/tmp/beamlet-actions-repair-preservation.log`.

## Bounds and ordinary policy preservation

The only production change is the dedicated credential map-key comparison. Strict JSON type/UTF-8/proper-list checks, 32 top-level entries, 1..128-byte top-level names, depth24 and complete 16,384-byte JSON accounting remain unchanged. The existing suite passed count/name/depth boundaries and exact/over JSON byte cases, including escaped newlines. Full credential-inclusive 262,144-byte Operation accounting remains unchanged; its exact-limit/one-byte-over test passed.

`Actions.bounded?/2` and its ordinary secret/root policy are unchanged, including their existing case behavior. Payload/metadata and Result rejection of ordinary credentials still pass. Runtime's generic dependency direction, progress validation and configured Operation/Result/progress caps are unchanged; no Runtime file was touched. The existing full Result cap test also passed. Normal output projections were not changed and generated errors retain safe atoms; this repair makes no malicious-provider-echo or memory-erasure promise.

## Remaining work and residual risks

No remaining F3 blocker identified. F1 is already handed off in `repair-harness.md`; F2 remains the next serial Agent/Node owner's work. Main owns fresh independent integrated recheck, subsequent integrated gates and spec synchronization. Historical integration evidence is not fresh final acceptance. No Harness suite, umbrella suite, distributed, release, Dialyzer/PLT or complete LSP gate was rerun or claimed for this bounded Actions repair. The initial Credo scope mistake above performed read-only analysis only. No physical-host or live-provider validation was performed.
