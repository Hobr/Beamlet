# Independent integrated check

Verdict: **BLOCKED**. Three P2 findings remain: malformed direct Harness replies raise, delegated child bindings are checked against the wrong authority registry, and the independent credential validators disagree on root-label rejection. No P0/P1 finding identified. Product/source/tests/deployment/spec files were left untouched; this report is the only repository file written by this review.

Review target: entire integrated tracked diff against `18137b1` on `feat/agent-model-credentials`, plus all six untracked product/test files. Approved PRD/design supersede legacy credential sourcing and OpenAI-shaped generic contracts. Planned executable-spec migration is not an implementation defect and remains with main. No staging, commits, dependency fetches, format mutation, branch/task-state/archive changes, physical hosts or paid/live providers.

## Findings requiring disposition

### F1 — P2: direct malformed reply validation raises instead of returning a safe error

Locations: `apps/beamlet_harness/lib/beamlet/harness/model.ex:151` (`Jason.encode(reply)`), and `apps/beamlet_harness/lib/beamlet/harness/models/open_ai_compatible.ex:238` (`Jason.encode(reply)` in public `normalize/2`).

Reproduced with:

```elixir
Model.validate_reply(%{kind: :tool_calls, content: nil, calls: [1 | 2]}, %{})
OpenAICompatible.normalize([1 | 2], %{})
```

Both raise `FunctionClauseError`, rather than returning `{:error, :invalid_reply}`. The first reproducer is an exact outer neutral reply shape containing unsupported call data. Encoding precedes semantic validation and Jason's improper-list path raises; neither public function normalizes that exception. Proper lists containing an improper nested call value can reach the same encoder boundary. PID/tuple/function/URI struct probes return safe errors; the improper-list case is specifically uncovered.

Consequence: direct Harness consumers cannot rely on the documented safe-error validation boundary. New generic Model validation is also used by Agent canonical reply handling, whose former rescue was removed; ordinary Runtime result validation currently rejects improper lists before delivery, so this review does **not** claim an observed remote Agent crash. OpenAI `complete/3` has an outer rescue; its exposed `normalize/2` does not. This is a direct API correctness gap, not evidence of HTTP retry or credential leakage.

Smallest remedy: reject unsupported/improper data before encoding, or normalize encoding/validation exceptions into the existing safe atom at these public boundaries. Keep full envelope accounting and neutral reply semantics. Add direct regressions for improper call lists and nested malformed values; do not merely catch errors at Handler, since that leaves independent Harness broken.

Evidence: `/tmp/beamlet-review-probe.exs`, `/tmp/beamlet-review-probe.log`; command below.

### F2 — P2: explicit delegated binding is validated using the parent's registry

Location: `apps/beamlet_agent/lib/beamlet/agent/server.ex:105`, calling `valid_options?(spec.options)`; that calls `ModelBinding.valid?/1` at line92 and `apps/beamlet_agent/lib/beamlet/agent/model_binding.ex:18` resolves `registry()` on the parent authority.

Independent named two-authority repro:

- Parent authority uses the default built-in registry and a valid deterministic parent binding.
- Target authority explicitly registers `%{"child-only" => Deterministic}`.
- Direct `Agent.start(target, id: "direct-child", model: %{provider: "child-only", config: valid_fixture})` succeeds and returns a live Ref.
- `Agent.delegate(parent, [%{authority: target, options: [id: "delegated-child", model: same_child_binding], input: "x"}])` immediately returns `{:error, :invalid_or_busy_delegation}`.

Consequence: explicit independent child bindings are rejected despite being supported by their actual authority. Trusted per-authority registries need not contain identical providers. The parent acquires an unintended provider-installation requirement from the child, contrary to authority-local registration and explicit child independence. The existing child-isolation test uses the same registry at both authorities and cannot expose this case.

Smallest remedy: separate portable child-option/binding shape and common bounds validation from selected adapter validation. Validate the selected adapter at the actual child authority's creation boundary. Preserve startup parent authorization, current limits, resource ownership, bounded helpers, and cleanup-before-retirement gates. Do not accept unknown providers at actual Agent creation or bypass child authorization.

Evidence: `/tmp/beamlet-review-delegation.exs`, `/tmp/beamlet-review-delegation.log`. This uses a real independent local peer VM, explicit target registry and successful direct target creation; the failure is not inferred from a nonexistent target.

### F3 — P2: Actions and Harness credential root policies disagree

Location: `apps/beamlet_actions/lib/beamlet/actions.ex:34`, case-sensitive root check, versus `apps/beamlet_harness/lib/beamlet/harness/model.ex:80`, `String.downcase(k)` in recursive root rejection.

Reproduced:

```elixir
cred = %{"ROOT" => "x"} # also "Workspace_Root"
Beamlet.Actions.credentials?(cred) # true
Model.validate_invocation(%{config: %{}, credentials: cred})
# {:error, :invalid_invocation}
```

Lowercase `root` is rejected by both. The checks recurse, so mixed-case labels also differ when nested. Strict JSON, entry/name counts and tested depth boundaries otherwise align. Both encoders produced identical JSON for sampled float, Unicode, slash and control-character values.

Consequence: dedicated generic Operations admit credentials that the authority/common Harness validator rejects. This violates the requested aligned reusable credential contract and makes admissibility depend on which entry point is used. This is a policy inconsistency within the approved validators, not a claim of a filesystem escape or a need for new security infrastructure.

Smallest remedy: apply one explicit root-label policy in both independent apps (consistent case normalization is the bounded existing Harness policy), and add matching recursive mixed-case regressions without adding sibling dependencies.

Evidence: `/tmp/beamlet-review-probe.log`, root/ROOT/Workspace_Root rows.

## Source and contract coverage

Read `check.jsonl` and all nine referenced spec/research files, then PRD/design/implementation/ownership, all three component handoffs, verification/handoff and the later `diagnostics.md`. Reviewed the tracked diff (39 files, +968/-491 before this report) and all six untracked source/test files: Agent ModelBinding, Harness Model/model_test, Node model_binding_test and alternate_model/binding support. Reviewed current deployment runbook/example, both release checkers, local-check wrapper and unchanged local HTTP fixture plus its saved Python probe. Read actual implementation rather than adopting handoff conclusions.

- Actions keeps the ordinary `bounded?/2` secret policy; only the dedicated plain JSON credential object bypasses secret labels. Proper lists, UTF-8, top-level32/128-byte names, depth24 and16KiB JSON caps are implemented. Credentials remain in the full262144-byte Operation external-size check. F3 is the identified policy mismatch.
- Runtime remains Actions/OTP-only. Public submit and gateway both invoke `Operation.validate` and enforce current `operation_bytes`; gateway forwards credentials through Worker context. No provider parsing, fallback, retry or placement/lifecycle algorithm was added. Full-envelope protocol/deployment tests cover exact boundaries and remote independent gateway rejection.
- Agent stores the one supplied binding privately; no API mutates it across steps/turns. Caller attaches only model credentials and derived provider capability. Tools retain empty credentials; Handler rejects nonempty Tool credentials and creates a native Context without config/credentials. Model Handler validates trusted registry, exact neutral request, common invocation and adapter invocation before completion. Validation callback exceptions/throws/exits normalize safely; model completion exceptions normalize to provider_failure.
- Trusted registry validation bounds32 portable IDs and locally loaded callback implementations; portable IDs never select/atomize arbitrary modules. Node rejects legacy model profiles, combines Tool/model capability union under32, and calls owning Runtime report configuration validation including reduced report-byte limits. Readiness no longer reads user key environment or calls providers. Workspace readiness is retained.
- Neutral Agent/Handler/Catalogue/Deterministic paths do not parse OpenAI envelopes. Model's built-in registry reference to OpenAICompatible is registration, not a codec. OpenAI owns messages/function calls/argument JSON/auth/choice/finish conversion, explicit credentials, no executor environment fallback, verified TLS, fresh Req construction and single-attempt transport.
- Whole neutral batches validate before executable calls are returned. Ordered pending IDs/history and canonical assistant/tool observations remain intact; F1 concerns safe handling of unsupported direct data. Context limits remain128/1MiB with no eviction, batch8, call args16KiB, model steps16 and complete request/reply limits.
- Child/peer credentials do not inherit implicitly. Explicit child credentials and peer independence are tested, but target-specific child registry independence is missing (F2).

Test migration was compared against baseline, including the entire saved1446-line Agent/Harness/Node test diff. Existing actual-DOWN-before-resume lifecycle assertions, guarded public admission, retained resource ownership, late-result/stop freezes, invalid sibling zero dispatch, reversed Tool completion ordering, no-target/no-fallback and no retry/replay assertions were preserved. No weakening of those assertions found. Old inconsistent wire-derived reply test appropriately became exact neutral extra-field rejection. Missing-provider scheduling fixtures now use a registered adapter plus absent environment, preserving scheduling rejection rather than accidentally testing creation rejection. New test fixtures carry observer node names as ordinary data, resolve only existing connected node atoms and do not atomize config.

## Actual targeted commands and results

Scratch scripts/logs are outside the repository. Deliberate negative cases are successful reproductions, not infrastructure failures. No unchanged broad passing gate was rerun.

1. `ERL_FLAGS='+S 2:2' MIX_ENV=test mix run --no-start /tmp/beamlet-review-probe.exs` — completed successfully; captured F1 and F3, safe PID/tuple/function/struct errors, proper strict invocation rejection and depth22..25 comparison in `/tmp/beamlet-review-probe.log`.
2. `ERL_FLAGS='+S 2:2' MIX_ENV=test mix run --no-start /tmp/beamlet-review-probe2.exs` — completed successfully; sampled OTP/Jason serialization equality, malformed catalogue rejection and initial local parent-registry rejection in `/tmp/beamlet-review-probe2.log`.
3. `ERL_FLAGS='+S 2:2' MIX_ENV=test elixir --sname review_parent_631927 --cookie review_isolated_631927 -S mix run --no-start /tmp/beamlet-review-delegation.exs` — completed successfully; real target direct creation succeeds, same target delegated binding fails; peer and authority supervisor cleaned up. `/tmp/beamlet-review-delegation.log`.
4. `git diff --check` — passed; `git diff --cached --name-only` — empty. No staging performed.

## Saved integration evidence assessed

Inspected actual final logs in `/tmp/beamlet-integration-631927/`, including `tests-final.log`, `distributed-final.log`, `credo-final.log`, `dialyzer-final.log`, `compile-attempt2.log`, `format-final.log`, `build-final.log`, **`release-attempt3.log`**, `web-secret.log`, `python-fixture.log` and provider audit. Read the check scripts to determine what their outputs establish.

- Ordinary final log substantiates138 passing tests: Harness31, Actions9, Runtime30, Agent4, Node57, Web7;9 distributed excluded.
- Named final log substantiates actual Runtime6 and Node3 passing,138 ordinary excluded. Per-app no-tests notices do not replace those executed suites. Node real HTTP fixture assertions check Authorization, no secret in body, model→workspace Tool→model, later turn, wrong environment, held-request stop and executor loss/no replay. Same-host peers only.
- Strict Credo final log:82 files, no issues. Warning-fatal compile and format command evidence is consistent with verification and empty/successful logs. Dialyzer final:0 errors/skips using existing PLT, no refresh.
- Backend build log identifies isolated backend output/runtime configuration. Correct final release log contains shipped dependency closure, seven copied eval successes, seven named role startup/RPC/stop successes and relative-path rejection. `release-final.log` is the failed expanded intermediate attempt; `recheck-status` still contains that intermediate release1 and must not be called final status. `release-attempt3.log` is the later successful evidence.
- Web log shows expected missing SECRET_KEY_BASE failure. Web7 includes existing CSP checks. Python log/script substantiate four actual local fixture checks: tool_calls, stop, malformed length400, incomplete-header deadline.
- Local wrapper itself, Sobelow and xref cycles were not executed by integration; required constituent gates were run individually. No new claim that they ran.

## AC1–AC8 evidence sufficiency

| AC | Assessment |
| --- | --- |
| AC1 | Sufficient local synthetic evidence: actual named three-role HTTP→workspace→HTTP and later turn with no executor key env; fixture asserts supplied auth/model. No physical/live claim. |
| AC2 | Sufficient for covered bindings: two Agents share executor with six independently paired config/key invocations; direct concurrent TCP isolation, unknown IDs/fields/modules and adapter rejection covered. |
| AC3 | Sufficient: neutral source inspection plus alternative config/nested-auth/internal tuple providers in independent Harness and Node Tool/text tests. No OpenAI parsing in generic seams. |
| AC4 | **Incomplete**: complete batches/order/history/limits covered, but direct malformed reply safe-error boundary fails F1. |
| AC5 | Strong protocol/admission/lifecycle evidence, but reusable credential policy alignment needs F3. Full serialized credential-inclusive protocol/deployment caps verified in tests and source. |
| AC6 | TCP/TLS/no-retry/redirect/overflow/default isolation and normal projection/Tool absence covered. Explicit child/peer noninheritance covered; target authority binding independence fails F2. No malicious-provider-echo/admin-memory guarantee. |
| AC7 | Current migration examples/release/Web/Python evidence sufficient for implemented supported subset. Executable spec synchronization remains acknowledged main-session work, not a blocker discovered by this review. Diagnostics limits below apply. |
| AC8 | Sufficient: immutable binding survives steps and later turns, independent Agents retain distinct bindings, collections/extra fields rejected; no switching API introduced. |

## Nonblocking notes and residual limits

- F3 also shows why duplicated independent validators need matching boundary vectors; shared dependency extraction into Actions/Harness would violate app independence and is not requested.
- OpenAI module documentation still says “Executor-local”; invocation config/credentials are now Agent-owned. The adapter runs locally, so this is wording ambiguity only, not a functional blocker.
- Main diagnostic record: active LSP probe checked5 key changed source files, returned0 diagnostics, only1 confirmed clean and4 timed-out inconclusive. It did not identify the individual clean file. This is **not** complete LSP cleanliness. Dialyzer used an existing PLT, not a refresh.
- Early Agent/Node raw failure logs and an early Operation compile log were overwritten. Component narratives/transcript excerpts cannot establish original root-cause proof; this review makes no such claim.
- Existing fixture CLI allows up to64 requests although its default/runbook example is16; this predates the diff and is not a migration blocker. No physical-host or paid/live model execution, streaming/multimodal parity, hostile filesystem confinement, persistence, secure erasure or mixed-version support was verified or promised.
- Synthetic negative probe logs are preserved at the paths above. Broad passing gates remain integration evidence; after repairs rerun affected checks and perform fresh integrated recheck.

**Final disposition: BLOCKED pending F1–F3 repair/disposition and fresh recheck.** No source fixes performed under the initial read-only authority.
