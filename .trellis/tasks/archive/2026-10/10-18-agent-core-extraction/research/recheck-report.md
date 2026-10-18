# Independent F1–F3 recheck

**PASS — no remaining blocker found in F1–F3 or the surrounding extraction diff.** This is the independent review result, not parent product acceptance. No parent acceptance checkboxes were changed.

## Scope and preservation

Reviewed `/mnt/data/Project/Beamlet`, branch `refactor/agent-core-extraction`, HEAD `a18f3c7488e08c13a4fc324e602e0a75d67e20bf`. Loaded check.jsonl and its referenced specs/research, then prd.md, design.md, implement.md, review-report.md and fix-report.md. The explicit dispatched task path identifies this existing task; no task creation or activation was necessary.

Inspected `git diff HEAD` across all 32 changed paths, including all added Core sources/tests/manifests and the Agent adapters, actual decision call sites, docs/specs and task evidence. `git ls-files --others --exclude-standard` returned no untracked files at both inventories. The review was of working-tree content, not merely the staged snapshot. Existing test files were not weakened or removed. No product/spec/planning files were edited. Only this authoritative external output report and temporary diagnostic files/logs were written. No worktrees, nested agents, stage/commit/reset/checkout/clean operations.

All 32 repository changes were already staged at review start. Index SHA-256 before and after verification: `0af67be5558825eba38c3cf5ead24c4ad2e3c5fd48faf6f2664dd6db96f7f176`. The report's `noStagedFiles: false` records this pre-existing state; it does not indicate staging by this reviewer. The historical fix-report observation of a split index is not the current inventory.

## F1: incremental first-error/read-stop and exact bytes — resolved

ContextBuilder.load_next verifies a single source and immediately calls Core.Context.append before the next iteration. No batch source preloading or second traversal remains. The pure accumulator verifies the next selected occurrence, material domain data, permitted material fields, operation identity and resolution association before conversion. It retains reversed bounded messages, counts a message's JSON once, and adds the enclosing array's two brackets plus one comma for each message after the first. Request/current-catalogue validation occurs only in finish; incomplete tool-pair prefixes are not prematurely validated as complete requests.

Fresh checked-in tests passed for build and materialize: overflow-before-missing/corrupt/valid suffix stops at read 16 with context_limit; invalid historical model reply returns invalid_reply after four verification calls, including the two operation event reads, without reading the missing suffix.

Fresh independent differential probes compile the exact HEAD baseline ContextBuilder under `Beamlet.Recheck.BaselineContext`, without editing checkout. Both facades and baseline return context_limit after exactly 16 reads for 127 valid 65536-byte selected input occurrences plus a missing, corrupt, or valid final occurrence. Thus both first-error and early stopping match, including the original adversarial reproduction.

Additional independent probes compare Core materialization, baseline/current adapter materialization and unchanged Harness.Context.append at **1,048,575 / 1,048,576 / 1,048,577 encoded bytes**, using ASCII, escaped newline and three-byte UTF-8 prefix text. All nine vectors agree: below/exact accepted, one byte over context_limit; accepted output encoding has the asserted exact size. Fixtures use 16 prefix messages and one final message, with each input within 65536 bytes. Baseline/current adapter read counts agree at 17. These checks establish serialized-byte behavior, not a hard RSS bound or hostile-input performance guarantee.

## F2: payload depth and decode/reduce/replay parity — resolved

Core.decode checks the envelope without payload, then validates payload from its own depth-zero root. Replay checks proper list structure without charging its wrapper against each event. Operation fields in context materials are independently validated so material/operation wrappers do not reduce description/result budgets. Improper lists and live/executable values remain rejected by focused tests.

Fresh checked-in boundary tests pass through Storage.Codec and both facade/direct Core APIs. Additional independent vectors cover nested maps **and nested lists inside a map payload**, at depths 31, 32, 33, against the exact baseline reducer, Agent reducer facade and Core reducer. Every decode/reduce/replay combination agrees: depths 31/32 accepted with equivalent reduced/replayed state; depth33 invalid_history. Checked-in context material tests additionally verify description and accepted-result root32 acceptance/root33 rejection.

## F3: normalized inherited sources — resolved

Core's inherited-source decoder now requires exact source/reference/resolution keys, canonical lowercase UUIDs and 64-hex digests, positive integer input/resolution sequences, supported consumption kinds and recorded confirmed_failed/confirmed_executed resolutions. Evidence-resolution consumption and presence of a recorded resolution must agree. Source membership in closure and the existing 128/1024 limits remain. Storage Inheritance's actual manifest construction was inspected for format compatibility.

Fresh tests exercise nonempty input/result/resolved-result inheritance, paused fork risk, empty pending/consumed work and explicit risk acceptance. Independent probes also accept valid tool_result and confirmed_executed evidence_resolution; remove every top-level required field from each source; remove every reference and resolution field; inject an extra source field; vary input UUIDs (including uppercase/raw bytes), digests and nonpositive/noninteger sequences; and test resolution-kind/presence mismatches and malformed decision UUID/sequence/value. Decode, reduce and replay consistently reject malformed entries with invalid_history.

This is pure normalized-shape validation. Artifact existence/content, source ownership, canonical digest equality, immutable preparation/acceptance linkage, recorded resolution provenance and transitive closure coverage remain loader/Storage responsibilities. No bypass of those reads or broadening of pure authority was found. The current Agent full focused run includes unchanged SQLite durable/fork/history/export assertions; final-fix PostgreSQL log evidence was inspected separately below.

## Surrounding regression inspection

Core dependencies remain Harness/Jason, with no Application callback. Forbidden-effect search of Core lib found only an Ecto UUID comment. No Storage/Runtime/Agent/Ecto invocation, reader callback, clock, credential lookup, dispatch or provider call was found. Harness's Req transitive dependency remains explicitly documented.

Agent.Reducer retains Storage.Codec/Events validation, canonical input digest normalization and stored versions/state keys. Decision mappings match replaced Server/Durable expressions and remain called at actual durable reply/resume and fork sites. Persistence transactions, loader/reference traversal, preparation/adoption/consumption ownership and committed-event projection paths are unchanged outside the reviewed facade extraction. Context's historical-catalogue/current-catalogue separation and complete_boundary behavior remain intact.

The earlier bookkeeping blocker is addressed: implement step8 remains pending independent review/final acceptance, step10 remains parent-owned/pending, and reports distinguish initial broad evidence from final-fix evidence. This reviewer did not change those checkboxes.

## Fresh verification

Commands ran from umbrella root, using `ERL_FLAGS='+S 2:2'` for Mix commands:

- `mix test --no-start apps/beamlet_agent_core/test apps/beamlet_agent/test/beamlet/core_adapter_test.exs apps/beamlet_agent/test/beamlet/context_read_order_test.exs --seed 631927`: **Core10 + Agent5 passed**, `/tmp/core-recheck-focused.log`.
- `MIX_ENV=test mix run --no-start /tmp/core-recheck-probes.exs`: **4 independent adversarial/differential tests passed**, `/tmp/core-recheck-probes-final.log`. Script and renamed baseline modules remain in `/tmp/core-recheck-*`.
- `mix test apps/beamlet_agent_core/test apps/beamlet_agent/test --seed 631927`: **Core10 + Agent109 passed**, `/tmp/core-recheck-agent-final.log`. Existing support-file test-pattern warning, deliberate Registry kill log and os_mon shutdown messages did not fail the run.
- `mix format --check-formatted`: passed, `/tmp/core-recheck-format.log`.
- `mix compile --warnings-as-errors`: passed, `/tmp/core-recheck-compile.log`.
- `mix credo --strict --all`: passed, 214 source files / no issues, `/tmp/core-recheck-credo.log`.
- `mix dialyzer`: passed, **0 errors / 0 skipped**, `/tmp/core-recheck-dialyzer.log`; existing PLT analysis, no forced rebuild.
- `git diff HEAD --check`: passed. Branch/HEAD/status/untracked inventories and unchanged index hash verified.

The first temporary exact-byte probe failed because its final synthetic input exceeded 65536 bytes for an escaped/UTF-8 vector. This was a probe-fixture error: adjusted prefix sizes to leave a legal final input and retained `/tmp/core-recheck-probes.log`; all corrected probes pass. No product edits were needed.

## Saved final-fix evidence inspected and limitations

Inspected final log contents cited by fix-report: Core10+Agent109 focused, no-start10+5, isolated Core10, PostgreSQL78, normal/backend warning-fatal compile, format, strict Credo and Dialyzer0 errors/0 skips. Logs are `/tmp/core-fix-{focused,no-start,isolated,postgres,backend,format}-final.log`, `/tmp/core-fix-compile-final-2.log`, `/tmp/core-fix-credo-final-2.log`, `/tmp/core-fix-dialyzer-final-2.log`. Earlier failed diagnostic logs are explicitly superseded rather than claimed as passes.

PostgreSQL was **not restarted or rerun by this reviewer**; its 78-pass final-fix log is saved evidence. The broad initial umbrella/named/release/security/catalogue/two-process e2e suites were not rerun after fixes or during this recheck. Their earlier results remain initial-extraction evidence only. Focused current tests and boundary probes cover the changed risks; no new reason requiring full release/distributed reruns was identified. Same-host peer evidence does not establish physical-host behavior. No paid provider or power-cut validation was performed.

Optional historical-vs-current differing tool-schema coverage remains weak: the named pure historical-catalogue test uses an empty catalogue/text reply. Code still explicitly validates stored replies against the historical catalogue, and this is not a remaining F1–F3 blocker. Existing PLT analysis is not a clean PLT rebuild. No other residual product blocker found.

```acceptance-report
{
  "criteriaSatisfied": [
    {"id": "criterion-1", "status": "satisfied", "evidence": "Independent F1-F3 recheck PASS; current Core10+Agent109 and no-start10+5 pass; four independent differential/adversarial probes pass; limitations documented."}
  ],
  "changedFiles": ["/home/kanade/.pi/agent/sessions/--mnt-data-Project-Beamlet--/subagent-artifacts/outputs/cb73e688-81ea-44ed-bcd2-538f32d06380/.trellis/tasks/10-18-agent-core-extraction/research/recheck-agent-output.md"],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {"command": "mix test --no-start apps/beamlet_agent_core/test apps/beamlet_agent/test/beamlet/core_adapter_test.exs apps/beamlet_agent/test/beamlet/context_read_order_test.exs --seed 631927", "result": "passed", "summary": "Core10 + Agent5"},
    {"command": "MIX_ENV=test mix run --no-start /tmp/core-recheck-probes.exs", "result": "passed", "summary": "4 corrected independent boundary/differential tests"},
    {"command": "mix test apps/beamlet_agent_core/test apps/beamlet_agent/test --seed 631927", "result": "passed", "summary": "Core10 + Agent109"},
    {"command": "mix format --check-formatted", "result": "passed", "summary": "No formatting drift"},
    {"command": "mix compile --warnings-as-errors", "result": "passed", "summary": "Warning-fatal compile"},
    {"command": "mix credo --strict --all", "result": "passed", "summary": "214 files; no issues"},
    {"command": "mix dialyzer", "result": "passed", "summary": "0 errors/0 skips, existing PLT"},
    {"command": "git diff HEAD --check", "result": "passed", "summary": "No whitespace errors"}
  ],
  "validationOutput": ["F1 first-error/read-stop and exact byte vectors agree with baseline", "F2 map/list depth31/32/33 decode/reduce/replay parity", "F3 malformed inherited-source fields rejected across decode/reduce/replay"],
  "residualRisks": ["PostgreSQL final-fix78 inspected, not freshly rerun", "Broad initial release/distributed/e2e suites not rerun after fixes", "Historical/current differing tool-schema pure coverage remains optional and weak", "Existing PLT only; no physical-host/paid-provider/power-cut claim"],
  "noStagedFiles": false,
  "diffSummary": "Read-only product/spec review of complete 32-path working-tree diff; external report only; index hash unchanged",
  "reviewFindings": ["No remaining F1-F3 blockers or new surrounding extraction blocker found"],
  "manualNotes": "All repository changes were staged before review. Index preserved; no product/spec/planning edits or parent acceptance checkbox changes. Initial temporary probe fixture error was corrected outside repository and retained in logs. Parent retains final acceptance/commit authority."
}
```
