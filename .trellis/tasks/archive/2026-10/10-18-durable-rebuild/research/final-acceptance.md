# Durable rebuild — final independent acceptance

## Result

Parent AC1–AC7 and D AC1–AC4 are accepted for the agreed scope after independent
cross-layer review and repairs. No known in-scope implementation or verification
blocker remains. This is a code/product acceptance record, not deployment approval,
a commit, a task-status transition or an archive action.

Detailed source findings, changes, retained red proofs, exact commands and practical
limits: [D independent check](../../10-18-durable-reference-delivery/research/independent-check.md).
The review covered the actual rebuild since `39b85a2`, the parent/D artifacts and
accepted main design, current specs, and A/B/C implementation plus independent
handoffs. Historical A/B/C integration failures were resolved by the final candidate;
their old passing counts do not substitute for the final gates below. Predecessor
uncommitted design/toolchain changes were preserved, not rewritten or attributed to
this independent check.

## Parent acceptance criteria

| AC | Decision and concrete evidence |
| --- | --- |
| AC1 — unique business ownership and offline accepted content | Pass. Original input is an Agent event/artifact; fixed logical requests and sources are Operation-owned; accepted output remains authority-owned and readable with executor journal offline. Agent preparation/consumption/cache contain references/control, not transcript copies. Runtime durable tests assert accepted content offline and credentials absent from authority/journal. Fork tests assert unchanged source rows and no execution/command/consumption clones; inherited usage is not new execution. Independent trace repair binds owners and captures bound receipt evidence/artifacts. |
| AC2 — replay/cache/live equivalence, no event holes or replay effects | Pass. durable_agent_test covers live vs full replay, valid checkpoint with nonempty suffix, corrupt/digest-valid malformed/missing cache, fixed earlier cutoff, invalid history and total byte-budget rejection. Loader revalidates the cache prefix and shares prefix/suffix budget; bad history cannot be repaired by a cache. Storage concurrent acceptance/control tests retain continuous committed Agent sequence positions with separate Operation acceptance scopes. Replay/inspect/paused restore asserts zero provider calls. |
| AC3 — immutable requests, ordered joins and transaction windows | Pass. Owned model/Tool preparation is atomic with Agent wait position and one prepared attempt. Full logical request, catalogue/configuration hash, source order and policy metadata are fixed before submit. Changed dependencies refuse; prepared identity binds complete description. Shared Storage rollback/concurrency tests, Runtime reverse/simultaneous sibling completion and single-claim races, Agent accepted/consumed/prepared continuation windows and partial batch restore prove ordinal consumption without duplicate effects. |
| AC4 — real dual-adapter format, unchanged old DB, damaged/foreign/stale references | Pass. Final Storage74 tests execute real SQLite and PostgreSQL, including transactional/CAS and old-format read-only rejection. Authority format2/journal1 is explicit; open/boot never migrate, initialize, repair or convert an existing dataset. Missing/foreign/digest-corrupt references and stale generation refuse. New decoder regressions return safe errors for malformed inherited containers online/offline; trace verification rejects false Operation ownership even after file hashes are recomputed. |
| AC5 — local/named fault windows, honest uncertainty and durable admission | Pass within process/VM scope. Runtime journals start_intent before Worker, commits accepted Result before sink delivery, hides failed acceptance, retains late evidence without replacement, and refuses duplicate/stale claims. Local restart/failure tests prove unknown_after_restart and zero Worker reconstruction. Named durable extension observes remote Worker plus persisted start_intent, stops peer, observes accepted uncertain/send_claimed, refuses resubmit and sees no second Worker start. Capacity is fenced by actual gateway release and a newer executor-clock report. Agent activation fences actual old helper DOWN and remains paused; claimed unknown never implicitly replays. Admission tests distinguish actual write/format probes from Repo/Node readiness and reject keyword/struct bypasses. |
| AC6 — direct reference fork, complete export and existing product/release flows | Pass. Fork15 tests cover paused independent control, default environment risk/recorded acceptance, source immutability, missing content, late output isolation and chained forks after parent event retirement. History/export24 tests cover offline context, fixed cursors/Operation capture, complete logical requests, receipt/artifact closure, corruption/missing/redaction, explicit bounds and performed/inherited provenance. Fresh copied Server/CLI/Web checks and real two-process durable-e2e pass. No parent-event recursion, legacy transcript fallback or graph UI was added. |
| AC7 — final full gates with actual prerequisites | Pass. Both full umbrella adapter runs503; named35; real Storage74 in each umbrella; focused reference39 on each adapter; independent-process phases1+1; format/warning-fatal compile/strict Credo/Sobelow/catalogue/existing-PLT Dialyzer/backend compile; fresh production default+explicit Server, CLI, Web and copied/named native controls. Logs and counts below distinguish earlier failed candidates from accepted runs. |

D AC1 maps to parent AC1/AC5/AC6; D AC2 to AC4/AC6; D AC3 to AC5/AC7;
D AC4 to AC7. Existing local/distributed memory scenarios remain exercised together
with new durable local/remote paths; no physical-host guarantee is inferred.

## Independent fixes and added coverage

Three defects were reproduced before correction: offline false ownership accepted
as complete; malformed inheritance raised raw Access errors; receipt evidence was
omitted from the purported full history/export closure. Fixes stay within D's
Agent/Storage read and verification paths plus the pure inheritance decoder.
Receipt capture now verifies content digest and Operation/attempt/executor binding,
includes referenced artifacts, freezes rows before writing, and refuses evidence
overflow after probing beyond32 rather than silently truncating. The additional
named durable start-intent/peer-loss regression addresses a missing failure-window
proof without changing production Runtime logic.

Four new Agent tests explain the count change **499 →503**. Final Agent suite is
**104**, not39: the original durable_agent_test has39 cases; the final focused
fork/history/export set independently has39 cases (15+24). The implementer's
pre-review full Agent PostgreSQL count100 was correct for its older candidate.

## Final executed gates

Evidence root: `/tmp/beamlet-d-independent/`. Seed631927, OTP29/Elixir1.20.4,
ERL_FLAGS='+S 2:2'. PostgreSQL uses only the isolated local Unix socket cluster at
`/tmp/beamlet-storage-a-pg/socket:55481`; fixtures create/drop their own databases.

| Command / gate | Actual result | Log basename |
| --- | --- | --- |
| `mix test --seed 631927` |503 passed,37 excluded |accepted-umbrella.log |
| Same full umbrella with `BEAMLET_AGENT_TEST_ADAPTER=postgres` |503 passed,37 excluded; Agent104 |accepted-umbrella-pg.log |
| Fork/history/export suites, SQLite then PostgreSQL |39 passed each, final exact32/33 boundary assertions included |reference-accepted-sqlite.log; reference-accepted-pg.log |
| Named `elixir --sname … --cookie <private> -S mix test --only distributed --seed 631927` |35 actual named passes: Runtime7/Node20/Server2/Web5/CLI1 |accepted-named.log |
| Extended durable named peer-loss case |one actual named pass;20 ordinary excluded |peer-loss-probe.log |
| `bash scripts/deployment/durable-e2e.sh` |phase1 one pass; independent phase2 one pass |accepted-e2e.log |
| Format and warning-fatal compile |exit0 |accepted-format-final.log; accepted-compile-final.log |
| `mix credo --strict --all` |206 files, no findings |accepted-credo-final.log |
| Sobelow/catalogue drift |exit0 |accepted-sobelow.log; accepted-catalogue.log |
| `mix dialyzer` |0 errors/skips/unnecessary skips, existing PLT, no refresh |accepted-dialyzer.log |
| Backend dev compile and production builds |exit0 |accepted-backend.log; accepted-release-build.log |
| Fresh copied/named releases |exit0 |accepted-release-check.log; accepted-copied/ |

The37 ordinary exclusions are35 distributed tests and two separately executed e2e
phase cases. A zero executed count in other apps during --only distributed is not
counted as a distributed pass. Total ordinary counts by app are Harness35,
Actions28, I18n15, Storage74, Runtime66, Agent104, Node68, Server15, Web73, CLI25.

Fresh artifact root: `_build/d-independent-accepted.w642a5/` with server,
server-explicit, cli and web. Native copied checks cover actual daemon launch/RPC/
pid/stop/exit, default/authority/executor configurations, authority→executor
bootstrap and deterministic work, nine invalid host cases without sentinel leakage,
missing-dataset noncreation, three CLI stdin/reattachment/close sessions, and Web
secret rejection/native controls/HTTP/CSS/JS. Copied server manifest SHA-256:
`3913bbe06f3565828a137b303f8ace28e4cede6134eff50e1d2c5f6b36ce433e`.
Unchanged digested assets were reused; all new core beams were rebuilt and packaged.
Independent e2e dataset/export directory: `/tmp/beamlet-durable-e2e-hUQf7f`.

Initial interrupted/mid-edit umbrella failures, red regression logs, lint findings
and the helper clause-grouping warning/release build failure are retained separately.
The corrected compile and rebuilt copied artifacts passed. These earlier failures
are not passing evidence; no timeout/cap enlargement, lint suppression, scenario
removal, business retry or compatibility shim was used to reach the final result.

## Limits and remaining actions

No implementation blocker remains for this agreed scope. Parent/task checkboxes,
status/archive/journal changes and commits were intentionally not performed.
This record does not approve publishing or deploying the candidate.

Evidence is real SQLite/PostgreSQL and same-host independent processes/peer VMs,
not physical-host, power-loss, paid-provider or externally exactly-once proof. Local
helper termination is not external rollback. Reference content is retained without
GC and must be backed up with authority data. Package integrity hashes do not sign
or authenticate the full package, and redacted/missing packages grant no restoration
claim or execution authority. LSP timeouts were inconclusive; actual compiler and
Dialyzer results are the static evidence. Logs under /tmp and ignored build artifacts
need deliberate archival if permanent retention is required. The parent subsequently synchronized predecessor design status and the delivery
record with this accepted candidate; current source contracts are in app READMEs
and backend durable specs. Historical stage reports retain their original scope.
