# D independent check — final cross-layer review

## Disposition

Independent review of the rebuild since `39b85a2`, including D and parent AC1–AC7,
completed with three reproduced defects fixed and an additional named durable
failure-window regression. Final verification results are below. No known actionable
in-scope defect remains. This report does not authorize deployment or a commit.

Loaded D's check.jsonl and curated specs/research, D/parent PRD/design/implementation
plans, the main persistence design, A/B/C implementation and independent-check
handoffs, current durable specs and actual source. Earlier A/B/C integration failures
are historical intermediate states, not silently counted as passing final gates.
Predecessor architecture/design and toolchain edits were left intact.

No nested agent, commit, push, merge, task-status/archive operation, deployment,
automatic old-format conversion or real-data deletion was performed. Fixtures used
real temporary SQLite datasets and the isolated PostgreSQL cluster at
`/tmp/beamlet-storage-a-pg/socket`, port55481; they provision/drop only their own DBs.

## Findings reproduced and fixed

1. **Offline ownership validation was incomplete.** Changing a performed Operation's
   owner and recomputing the operations file hash still returned history_complete=true.
   The red proof is `/tmp/beamlet-d-independent/provenance-red.log`. TraceVerifier now
   binds performed references to the Agent, ordinary result sources to the originating
   Operation owner, and input sources to owner/sequence/preparation cutoff. Inherited
   input matches include original source ownership. Parent event prefixes remain
   unnecessary for inherited closure.
2. **Malformed inheritance could raise during reference traversal.** A scalar closure
   entry, or inherited_result with a scalar reference, passed the pure decoder and
   raised Access errors in offline verification/capture. The red proof is
   `/tmp/beamlet-d-independent/malformed-red.log`. Reducer now checks inherited entry
   and nested reference container shapes before traversal. The regression exercises
   both rehashed offline packages and corrupted stored inheritance; both return safe
   errors. Full manifest/content verification remains in the reference layer.
3. **Receipt evidence was omitted from Agent history/export.** OperationRecords.fetch
   returns Operation/attempt only; D called it as if it also returned evidence.
   History's evidence view and TraceSnapshot now explicitly use Storage.History.evidence.
   Capture includes evidence before writing, traverses its artifacts and charges its
   bytes. Offline verification checks evidence content digests, Operation/attempt/
   executor binding, and presence of the accepted evidence row when one is named.
   Evidence reads probe33 rows against the32-row bound and refuse overflow; they no
   longer silently call that truncated export complete. The regression checks exact32
   and33 boundaries, history reachability, later-receipt isolation, receipt artifacts,
   and a forged receipt body with recomputed file hash. Original red proof:
   `/tmp/beamlet-d-independent/evidence-red.log` (22/24 passed, two failures).

The four added Agent tests raise the ordinary Agent count from100 to104 and the
umbrella count from499 to503. The original39-case durable_agent_test suite remains;
39 focused fork/history/export cases now means15 fork +24 history/export cases.
These are different39-case sets and must not be conflated.

Additionally extended the existing named durable test beyond successful completion:
after actual gateway release and a newer eligible capacity report, a second held
Operation proves remote start_intent before peer loss. Peer shutdown produces an
accepted uncertain outcome; send_claimed persists, resubmission is refused, and no
second Worker-start notification appears. This closes the prior evidence gap between
local durable failure windows and ordinary distributed failure tests. It does not
claim a power cut or externally exactly-once execution. Focused proof:
`/tmp/beamlet-d-independent/peer-loss-probe.log`, one actual named test passed.

## Source review conclusions

- AgentRecords commits input independently before preparation; preparation atomically
  commits Operation/attempt, Agent preparation events, position and command response.
  Acceptance advances only the Operation scope. Consumption checks owner/turn/
  generation/accepted digest and unique consumption identity. Transactions contain no
  network/provider work; unknown write outcomes reconcile by stable identity.
- Reducer is pure, consumes contiguous supported committed events, and stores only
  control/references. Loader fixes through_seq, bounds history/reference traversal,
  compares cache data with a reduced prefix before dereferencing it, carries the
  budget across prefix/suffix, and falls back only for bad caches. Corrupt history or
  content blocks. Replay/inspect requires no provider and performs no execution.
- ContextBuilder materializes original inputs and consumed accepted outputs; prepared
  logical request, catalogue/configuration fingerprint, policy and ordered sources
  remain Operation-owned and fixed. Reversed sibling completion does not change
  ordinal consumption. Executor observations cannot replace accepted output.
- Runtime claims before admit; Gateway journals intent before Worker creation.
  Completion requires bound receipt evidence; authority acceptance precedes normal
  sink delivery. Failed acceptance hides normal Result visibility. Late receipts are
  retained without replacing accepted output or advancing a fork.
- Restore increments generation, pauses, and fences inventoried old local helpers
  through actual DOWN. Explicit continuation adopts only eligible prepared/accepted
  identities. Claimed unknown does not authorize another admit; no retry, memory
  downgrade or implicit provider replay was introduced. Bounds and helper ownership
  are preserved.
- Fork creates independent paused control and a flat immutable manifest. Original
  input artifacts and source-owned Operations/results remain retained. Transactional
  source membership/position validation and PostgreSQL shared source lock remain.
  Child/chained replay/export uses child events, artifacts and Operation streams;
  no recursive parent Agent-event loading. Default shared-environment risk blocks
  execution, explicit acceptance is recorded, inherited usage is not new work.
- History cursors retain their original Agent cutoff. Step/tool outputs require
  consumption by that cutoff; independent evidence is labeled separately. Trace
  capture freezes Agent and per-Operation content before page writes. Missing or
  damaged dependencies and redaction cannot claim completeness. Hashes are integrity
  checks, not authenticity signatures or execution permission.
- Host initialization remains explicit, authority2/journal1. Old authority format
  refuses rather than converting. CLI/Web live APIs and display retain their existing
  memory behavior; production consumers do not parse an old persisted transcript.
  Searches for old prepare_batch/consume_result/accept_seq/fork_messages paths found
  no production compatibility implementation. Disposable in-memory messages and
  assistant projections remain intentional Harness/Server display/execution data.

## Files changed by this independent check

- Agent `reducer.ex`, `trace_verifier.ex`: malformed inheritance/ownership validation.
- Agent `history.ex`, `trace_snapshot.ex`, `trace_export.ex`: captured receipt closure
  and offline evidence verification.
- Storage `history.ex`: explicit evidence overflow instead of silent truncation in
  the evidence reader. Existing bounded legacy audit views are otherwise unchanged.
- Agent `history_export_test.exs`: four behavioral adversarial regressions.
- Runtime `durable_runtime_test.exs`: named start-intent/peer-loss/no-replay assertions
  and observed fresh capacity barrier.
- Agent README, durable-references spec, this report and parent final-acceptance.md.

## Verification and retained evidence

Commands run from umbrella root with OTP29/Elixir1.20.4 and ERL_FLAGS='+S 2:2'.
All tests use seed631927. Evidence root: `/tmp/beamlet-d-independent/`.
Exact scripts: `run-accepted.sh`, `run-accepted-release.sh`; no private cookie is
printed. Full named tests use a fresh random cookie and actual peer VMs.

| Gate | Result | Log under evidence root |
| --- | --- | --- |
| `mix test --seed 631927`, Agent SQLite + Storage SQLite/PG |503 passed,37 excluded |accepted-umbrella.log |
| `BEAMLET_AGENT_TEST_ADAPTER=postgres mix test --seed 631927` |503 passed,37 excluded; Agent104 |accepted-umbrella-pg.log |
| Focused reference suite, real PostgreSQL |39 passed, final exact32/33 assertions |reference-accepted-pg.log |
| Focused reference suite, SQLite |39 passed, final exact32/33 assertions |reference-accepted-sqlite.log |
| Actual named `--only distributed` |35 passed, ordinary cases excluded |accepted-named.log |
| Two independent OS-process durable-e2e |one executed test per phase |accepted-e2e.log |
| Final ordinary Runtime suite after named test extension |66 passed,7 distributed excluded |runtime-accepted.log |
| Format, warning-fatal compile, strict Credo |exit0 |accepted-format-final.log; accepted-compile-final.log; accepted-credo-final.log |
| Sobelow, catalogue drift, existing-PLT Dialyzer |exit0 |accepted-sobelow.log; accepted-catalogue.log; accepted-dialyzer.log |
| Backend warning-fatal compile |exit0 |accepted-backend.log |
| Fresh production default/explicit Server, CLI, Web builds |exit0 |accepted-release-build.log |
| Fresh copied/named releases |exit0 |accepted-release-check.log; accepted-copied/ |
| Whitespace/diff check |exit0 |accepted-diff.log |

Named executed counts are Runtime7 + Node20 + Server2 + Web5 + CLI1 =35; zero
executed tests in other apps are not distributed evidence. The named peer-loss
extension additionally passed in peer-loss-probe.log after the full named suite.
The37 ordinary exclusions
are those35 distributed cases plus two separately executed process-phase cases.
Release checks cover daemon/native start/RPC/pid/stop/actual exit, default/authority/
executor modes, remote Gateway work, invalid host config and missing-dataset
noncreation, CLI foreground reattachment, and Web secret/HTTP/CSS/JS. Production
assets were unchanged; fresh artifacts package the new core beams and copied HTTP
checks serve the existing digested assets. See accepted-release-root for the fresh
artifact directory and accepted-copied/copied-tree.sha256 for its manifest digest.

The source changes after the successful full umbrella runs were test-only capacity
assertions and exact32 evidence-boundary coverage plus behavior-equivalent private
helper placement to group clauses. Fresh focused runs/static gates validate these;
no production behavior changed after the accepted artifact build.

## Earlier runs and limitations

- Initial umbrella command was interrupted by the tool's60s limit; it is incomplete,
  not a pass. Detached bounded gates then completed. umbrella-complete.log and
  final-umbrella.log include tests loaded while adversarial fixes were in progress;
  their failures are retained, not final acceptance.
- accepted-compile.exit and the first accepted-release build record a clause-grouping
  warning introduced during helper extraction. Helpers were grouped correctly;
  corrected warning-fatal compilation and rebuilt artifacts passed. No warning
  suppression was added. The original release failure is retained separately as
  accepted-release-build-grouping-failure.log.
- evidence-credo.log records three findings (alias, complexity, nesting); fixed with
  aliases/helper extraction. accepted-credo-final.log is clean. A transient Mix git
  subprocess :enoent during the first formatting attempt is not a passing check;
  subsequent formatting/compilation completed normally.
- LSP availability was intermittent; no timeout/empty cache is counted as clean.
  Gettext extractor backend-reference warnings and test-support file-filter warnings
  remain visible; catalogue drift itself exits0. Existing negative-control crash/
  lock/connection logs are expected test observations, not silently hidden failures.
- Tests are real adapters and same-host OS processes/peers. Physical-host, paid
  provider, power-loss, external rollback/exactly-once, GC, cross-dataset transfer,
  import authority and unbounded history are outside the accepted scope. Retained
  referenced content and authority data must be backed up together. Local /tmp
  evidence and ignored build artifacts are not permanent archives.
