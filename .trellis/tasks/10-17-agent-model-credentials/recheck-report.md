# Fresh independent repair recheck and final integrated validation

Verdict: **READY** for main-session executable-spec synchronization and final workflow review. F1, F2 and F3 are resolved; no remaining actionable blocker or new defect identified in their repair blast radius. This is fresh acceptance of the repaired source candidate, not acceptance of yet-unwritten spec changes or a commit. No optional design cleanup is requested.

Reviewed on `feat/agent-model-credentials`, baseline `18137b1`. Product/source/tests/deployment/spec remained read-only. This report is the only repository file written by this checker; scratch scripts/logs are in `/tmp/beamlet-recheck-631927/`. No staging, commits, branch/task-state/archive mutations, dependency fetches, physical-host or paid/live calls. Historical reports and raw logs were preserved.

## Context and independent coverage

Loaded `check.jsonl`, all nine referenced backend spec/research documents, then PRD/design/implement, ownership, original check-report, all three repair reports, original component handoffs, verification/handoff and diagnostics. Approved task contracts override old specs only for the explicitly migrated Agent binding, invocation credentials, neutral provider/history and local-registration contracts. Existing admission, lifecycle, ownership, complete-envelope, transport and release requirements remain applicable.

The initial independent report supplies whole-diff coverage context. This recheck independently read the repaired Actions validator/tests; Harness Arguments, Catalogue, Model and OpenAI normalization/tests; Agent ModelBinding, Server option/delegation paths and Delegation controller; new independent-peer delegation tests; adjacent Caller/Handler and Operation validation. Inspected current diff/status and copied-release scripts, actual new gate logs, and prior saved Web-secret/Python-fixture evidence. Current tracked diff is 40 files, +1047/-503, plus seven untracked product/test files; task artifacts are separately untracked. This is a repair-focused independent recheck plus fresh full integrated execution, not a claim that every historical finding was rediscovered from scratch.

Independent executable probe: `/tmp/beamlet-recheck-631927/probe.exs`, output `probe.log`. It asserts 66 Actions/Harness agreement vectors: 42 recursive blocked/allowed root-label vectors, seven depth vectors (20..26 nested lists), and 17 strict JSON/count/name/byte vectors. Also asserts exact/over full Operation and neutral/OpenAI 1 MiB envelopes, direct malformed reply rejection, malformed required/enum catalogue rejection and precedence, and unchanged incomplete/unsupported semantic errors. All passed. This probe is independent scratch coverage, not a repository test addition.

## F1 disposition — resolved

`Model.validate_reply/2` and `OpenAICompatible.normalize/2` now normalize FunctionClauseError only inside private `Jason.encode/1` wrappers. The rescue does not cover subsequent semantic validation, adapter callbacks or transport. Malformed improper list tails and nested improper argument/envelope values return `{:error, :invalid_reply}` directly. Unsupported ordinary encoding errors retain the existing safe-error path.

`Arguments.schema?/1` checks proper required/enum lists before enumeration; malformed schema lists now return `:invalid_catalogue` through Catalogue construction/validation and both reply APIs (and neutral request validation). Proper primitive enum/type/schema behavior remains unchanged. Catalogue errors retain precedence over reply encoding, confirmed by passing a malformed catalogue together with an improper wire reply.

Complete encoding remains before size/semantic checks. The repair tests and independent probe both verify exactly 1,048,576-byte neutral and OpenAI envelopes succeed and one byte over yields `:response_limit`, without truncation. Small valid envelopes with length/unknown finish reasons still yield `:incomplete_reply`/`:unsupported_reply`, so the encoding rescue does not collapse those valid semantic error outcomes. Harness35, including all existing TCP/TLS/schema/history/workspace regressions, passed fresh.

## F3 disposition — resolved

Actions now checks `String.downcase(key)` against exact root/workspace_root labels at its existing recursive credential map boundary after UTF-8 validation. This agrees with Harness, including nested maps inside lists. No key rewriting, trimming, substring policy or sibling dependency was introduced. Credential names such as TOKEN, Credentials, authorization, root_token and workspace_root_id remain admissible.

Fresh Actions28 and the independent 66-vector comparison cover strict JSON, proper lists, invalid UTF-8/non-JSON terms, recursive labels, top-level32/33 entries, UTF-8 name128/129-byte boundaries, depth24 boundary, and exact/over16,384-byte JSON including escaped newline accounting. Existing complete 262,144-byte credential-inclusive Operation tests and independent exact/over probe passed. Runtime public and remote gateway reduced-cap tests ran in the ordinary/named suites. Ordinary payload/metadata/Result policy was not changed by the repair.

## F2 disposition — resolved

`ModelBinding.portable?/1` validates exact binding fields, provider ID syntax, common config/credentials and placement through Operation validation. It does not read Registry metadata or call provider adapters. Delegation invokes this predicate through the private option validator; catalogue and Tool-route checks also reject common malformed options before spawning helpers. Actual creation still invokes `ModelBinding.valid?/1`, resolves the creating authority's immutable trusted registry, and safely validates its selected adapter. There is no public bypass flag, module forwarding, provider substitution or credential inheritance.

Target-dependent child creation/validation is reached by `Delegation.run/5` through its bounded controller/worker and target Agent.start, outside the parent's Server command callback. The parent's callback performs only portable/common validation. The target's ordinary creation boundary retains pure adapter checks in start_link/init; those existing creation checks are distinct from synchronous remote work in the parent's callback. No lifecycle or admission algorithm was changed.

Fresh named umbrella execution ran all three new distinct-registry regressions:

- Default-registry parent and independent target registering only child-only: direct target input actually completes, then delegated input completes with the same binding and correlated parent turn. Child/helpers retire and parent binding stays unchanged.
- Parent-only, unknown, and common-valid/adapter-invalid bindings: direct target creation rejects, delegation accepts transport then returns the correlated safe `:authority_unavailable` terminal result. Tracing observes exactly one Agent.start dispatch per case, no parent adapter callback, no retry or later dispatch within the bounded observation window, and no retained target child.
- Malformed binding/provider/config/credentials/placement/catalogue/Tool/options and oversized invocation values reject locally; spawn tracing sees no helper, parent remains idle with empty child/helper maps, target has no child.

Existing explicit-child and independent-peer credential tests ran in Node57. Existing actual-DOWN-before-resume, guarded admission, startup parent authorization, retained slot accounting, late-result/stop freeze, nested cleanup, no fallback/retry/replay assertions remain intact and passed in fresh Runtime/Node ordinary and distributed execution.

## Once-only final integrated gates

All commands ran from root with `ERL_FLAGS='+S 2:2'`. Sequential driver: `/tmp/beamlet-recheck-631927/gates.sh`; exit records: `status`. Each gate ran once, with no retries, source mutation or masked failure. There were **no failed/intermediate gate attempts** in this recheck; historical failed/intermediate/final logs remain separate in their original directories. Logs below are relative to `/tmp/beamlet-recheck-631927/`.

| Actual command | Result | Log |
| --- | --- | --- |
| `mix format --check-formatted` | passed | `format.log` |
| `mix compile --warnings-as-errors` | passed | `compile.log` |
| `mix test --seed 631927` | **161 passed**, 12 distributed excluded | `tests.log` |
| `elixir --sname recheck_credentials_631927 --cookie recheck_synthetic_631927 -S mix test --only distributed --seed 631927` | **12 actually passed**, 161 ordinary excluded | `distributed.log` |
| `mix credo --strict` | 83 files, 69 checks, no issues | `credo.log` |
| `mix dialyzer` | 0 errors, 0 skipped, 0 unnecessary skips | `dialyzer.log` |
| `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_node --overwrite` | rebuilt current backend artifact successfully | `build.log` |
| `bash scripts/deployment/check-release.sh` | copied closure, all7 eval and all7 named startup/RPC/stop, relative-path rejection passed | `release.log` |
| `MIX_ENV=test mix run --no-start --no-compile /tmp/beamlet-recheck-631927/probe.exs` | independent assertions passed | `probe.log` |
| `git diff --check` | passed | `diff-check.log` |
| `git diff --cached --name-only` | empty | `staged-files.log` |

Actual ordinary breakdown: Harness35 + Actions28 + Runtime30 + Agent4 + Node57 + Web7 = **161**. Actual named breakdown: Runtime6 + Node6 = **12**. Per-app no-test notices for distributed-excluded Harness/Actions/Agent/Web are not counted as executions. New Node distributed total includes the three new delegation tests. Web7 ran the full existing CSP/nonce/controller/error assertions. Deliberate gateway/Registry kills and self-signed certificate rejection diagnostics are expected fixture behavior; both suites exited0.

Full `mix dialyzer` checked the existing `_build/dev/dialyxir_erlang-29.1.2_elixir-1.20.4_deps-dev.plt`, reported “PLT is up to date!”, and analyzed the full umbrella with0 errors/skips. No forced PLT refresh/rebuild occurred. This supersedes the focused repair analyses for final integrated acceptance.

The backend build freshly compiled repaired Harness3/Actions1/Agent2 files and assembled `_build/backend/prod/rel/beamlet_node` using backend runtime config. Copied checker inspected shipped .rel/.app/lib closure and excluded Web/Phoenix/Plug/Bandit/WebSock application edges; all seven role subsets passed both eval and named boot/RPC/stop outside the checkout. Named service used19101, control helpers retained port0, and relative BEAMLET_CONFIG explicitly failed. All seven named successes and final relative-path rejection are present in `release.log` and driver recorded exit0. No stale pre-repair artifact was used for final acceptance.

Inspected prior `/tmp/beamlet-integration-631927/web-secret.log`: ordinary production invocation failed with the expected SECRET_KEY_BASE message. Inspected `python-fixture.log`: four local fixture checks passed (tool_calls, stop, malformed length, incomplete-header deadline). Those unchanged gates were not rerun. Fresh Web suite covers CSP. `check-local.sh` wrapper, Sobelow, xref cycles and physical/live execution were not run or claimed.

## Updated AC1–AC8 assessment

| AC | Assessment after repairs |
| --- | --- |
| AC1 | Satisfied within approved synthetic local scope: fresh named Node real HTTP three-role model→workspace Tool→model and later turn; supplied auth/model and no executor key environment assertions pass. |
| AC2 | Satisfied: fresh Node binding/Handler/provider tests and Harness concurrent TCP isolation; two immutable Agents share executor with independently paired config/keys. F2 now proves distinct target authority registry and rejects unknown/adapter-invalid binding at actual creation. |
| AC3 | Satisfied: neutral source seams remain independent of OpenAI wire parsing; independent alternative provider tests pass with different config/nested credentials/tuple protocol. |
| AC4 | Satisfied: F1 direct malformed replies/catalogue lists are safe; exact full1MiB boundaries hold. Ordered history, whole-batch/invalid-sibling zero dispatch and reversed Tool completion regressions pass. |
| AC5 | Satisfied: F3 validators agree recursively and across JSON/depth/count/name/byte boundaries; complete protocol/current deployment accounting and Runtime/Node guarded admission/lifecycle/role tests pass fresh. |
| AC6 | Satisfied within normal generated-projection scope: TCP/TLS/no-retry/redirect/overflow/default isolation and no Tool credential context pass; explicit child/peer independence preserved, F2 target registry isolation now covered. No malicious-provider-echo/admin-memory guarantee. |
| AC7 | Implementation/release/Web/evidence portion satisfied: fresh rebuilt copied release all7 eval/named combinations, closure and config rejection; historical unchanged Web-secret/Python evidence inspected. **Executable-spec synchronization remains required main-session work before final task completion.** |
| AC8 | Satisfied: immutable binding across steps/later turns, distinct independent Agents, unsupported collections/creation fields rejected; successful child does not mutate parent binding. |

## Residual limits and final spec-sync requirements

No remaining code blocker identified. Initial nonblocking adapter documentation ambiguity is resolved (“Agent-owned invocation configuration and credentials”). Duplicated independent credential validators now have matching recursive and boundary evidence; extracting a shared dependency is neither required nor requested. Prior overwritten original Agent/Node/Operation raw failure logs cannot prove their original root causes; this report makes no such claim. Historical failed expanded release log remains historical, not final acceptance evidence.

This checker has no callable LSP diagnostic tool. Existing parent probe is exactly5 files checked,0 returned diagnostics,1 confirmed clean,4 timed-out inconclusive, with individual clean-file identity unavailable. No fresh/full LSP cleanliness is claimed. Full compile/Credo/Dialyzer are separate positive evidence.

Same-host independent VMs/local TCP/TLS/copied release only; no physical multi-host or paid/live provider execution. Supported text/function subset, one immutable binding, matching builds, ephemeral trusted cluster and ordinary plaintext process/message lifetimes remain the approved scope. No secure erasure, persistence/recovery, hostile filesystem confinement, administrator secrecy or malicious-provider echo guarantee. No-late-dispatch checks are bounded observations, not proof about arbitrary future time.

Main must synchronize current executable specs before final task completion, preserving archived historical evidence. At minimum update Operation credentials/context forwarding/full accounting; Harness neutral request/reply/history/Catalogue and explicit invocation/provider callback/registry plus direct malformed error boundaries; Agent immutable binding, model-only credentials and portable delegation versus target adapter validation; Node model_providers/readiness/capabilities/no legacy model profiles; release/runbook migration and actual final gate counts/limits. Keep public guarded submit, actual-DOWN ownership/accounting, callback responsiveness, control port0, complete-envelope limits and single-attempt/no replay contracts intact. Avoid treating old executor-owned keys/OpenAI-shaped generic assistant contracts as current behavior. Spec-only follow-up does not invalidate these completed source gates unless it exposes a substantive implementation contradiction or changes source.

**Final disposition: READY.** Sole checker-written repository file: this report. Main owns spec synchronization and subsequent approved commit/task workflow.
