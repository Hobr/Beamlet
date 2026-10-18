# D implementation handoff — reference fork, history/export, product gates

Implementation candidate on `refactor/durable-rebuild`. **Not independent check or
final product acceptance.** No nesting/subagents, commits, pushes, merges, task
status/archive actions or deployments. A/B/C and pre-existing design/spec work
remain in the shared tree; `git diff HEAD` is the combined rebuild, not D alone.
Only task-owned temporary datasets/artifacts were initialized/removed. No real
user database was deleted, migrated, converted or repaired.

## 1. Delivered contract / public APIs

Detailed current APIs: `apps/beamlet_agent/README.md`, Storage README and
`.trellis/spec/backend/durable-references.md`. Prior document-only design artifacts
were left intact rather than rewriting their historical status statements.

```elixir
Agent.fork(%{repo: repo, agent_id: source_uuid,
             source: %{environment: :confirmed_stopped}},
           selected_committed_seq, current_source_version, command_uuid)
# {:ok, %{agent_id:, locator:, version: 0, generation: 0, through_seq: 3,
#         source: %{agent_id:, through_seq:}, risk: nil | "unconfirmed"}}
# command_uuid is also the stable child UUID

Agent.history(locator, %{view: :facts, limit: 100}, previous_next_cursor)
# {:ok, string_keyed_page}; next_cursor fixes view/through_seq/after_seq
Agent.history(locator, %{view: :context, as_of_seq: seq}, nil)
Agent.history(locator, %{view: :evidence, operation_id: operation_uuid}, nil)

TraceExport.begin(repo, locator) # {:ok, fixed_capture}
TraceExport.write(fixed_capture, dir: fresh_empty_directory, page: 100,
                  page_bytes: 1_048_576, redaction: :none)
TraceExport.export(repo, locator, dir: fresh_empty_directory)
TraceExport.verify(directory) # offline; no repo/provider/executor required
# :drop_content is the alternate redaction policy, not a restorable package
```

`AgentRecords.fork(repo, attrs)` is the transaction boundary. attrs include stable
`command_id`, source `position`, child `id`, selected `through_seq`, validated
`timeline`, flat `inheritance`, recorded `resolutions`, `risk`, and normalized
`fork_request` (through_seq, expected_version, source confirmation). Source position,
reference membership and uncertainty decisions are checked again inside the write
transaction; PostgreSQL holds a shared source-row lock. Source rows are not updated.
Exact command replay returns the original response even after **both** Agents
advance; changed request parameters conflict. Unknown write outcomes read the
recorded command response, never reissue business work.

### Fork semantics

- Child control starts paused/await_input, generation/version0, with exactly
  created/forked/context.inherited events. No inherited pending work, command dedupe,
  consumption, provider session, Operation/Execution/attempt clone or new billing.
- Sources are direct ordered inherited_input/inherited_result refs and a flat
  closure. Original input payloads become authority-local digest-deduplicated
  immutable JSON artifacts retaining event/seq/digest/source Agent identity.
  Results retain their original accepted reference and description digest.
- Child replay and chained fork need their own events, immutable content, and
  Operation streams, **not parent event prefixes** or recursive Agent loading.
  Source facts remain retained; there is no GC. Deleting retained content blocks.
- Selected boundary must be complete/safe with no pending work or blocker, and
  within native context bounds. Already registered source refuses. Local sender
  groups are fenced without pretending to prove remote termination.
- Omitted environment assertion defaults to unconfirmed, including idle sources.
  Optional source is exactly `%{environment: :confirmed_stopped | :unconfirmed}`;
  legacy `freeze:` is not a supported API. Read/export/restore grant no execution.
  Explicit `%{"risk" => "accepted"}` continuation records acceptance; stale and
  repeated decisions refuse. A source's inherited unconfirmed risk stays gated.
- Request preparation/control references can use only owned or precisely validated
  inherited sources in the same dataset. Source Operations remain source-owned.

### History/export semantics

- Views: facts, turns, context, steps, tools, evidence, decisions, provenance.
  Context is event-reduced at as_of_seq, never a message checkpoint. Facts/turns
  retain their original cursor high water across appends. Steps/tools expose fixed
  logical requests; accepted output appears only when consumed by the cutoff.
  Evidence is explicitly an independent Operation snapshot, not an Agent-seq claim.
- Trace format2 contains manifest plus events/inputs/operations/definition JSONL
  and binary artifacts. begin captures Agent and per-Operation high waters before
  write pages; later appends, acceptance and receipts cannot alter that capture.
  It traverses request sources, accepted output, evidence, definition and artifact
  closure. Optional control caches are unnecessary for supported reconstruction.
- File SHA-256/counts, event/request/accepted/source/artifact digests and envelope
  shapes are checked offline. Missing/damaged dependencies are listed explicitly
  with history_complete=false; no hash-as-body fallback. Redaction removes input,
  request, result, definition, evidence and artifact content, marks lines and never
  claims restoration. Output directories must be empty to avoid stale plaintext.
- No graph UI, import/execution authority, signature/authenticity guarantee against
  coordinated whole-package rewriting, automatic retry or external exactly-once.
- Bounds: native128 messages/1MiB; history100000 events/32MiB; capture32MiB,
  1024 Operations,5s reference deadline; manifest128 ordered sources/1024 closure
  entries plus existing codec caps. Artifacts retain the existing16MiB allowance.
  Page1..500 and byte policy4096..4MiB preserve/mark oversized whole records.
  Oversize traversal refuses rather than truncating context or silently dropping
  content. Retention is not a promise of unbounded executable context.

## 2. D-owned files and integration

- Agent public fork route; durable fork/replay/risk handling; reducer inherited
  control; Loader source verification; ContextBuilder inherited materialization and
  complete historical Tool pairing (no validation against a newer catalogue).
- New Storage `inheritance.ex`; fork/source/control changes in `agent_records.ex`;
  bounded through_seq in Storage history; artifact ID collection in references.
- Replaced Agent history/trace_export; new trace_snapshot/trace_verifier.
- Replaced obsolete fork/history_export tests with35 format2 behavioral tests and
  shared `test/support/reference_fixture.ex`, selectable for real SQLite/Postgres.
  A/B/C's existing durable contract/fault-window/call-count/lifecycle tests remain.
- Server durable_e2e fixture now uses actual dataset UUID, event/control assertions,
  complete restore→idle without another model call, committed-seq reference fork,
  unsafe historical-boundary refusal, and offline inherited trace verification.
  Independent-process script comments now describe initialization/reference fork.
- Narrow Node observation named-fixture fix, explained below; no production Node
  change. Existing CLI/Web/Host production wiring already uses the new adapter;
  their unchanged functionality was exercised through umbrella/named and rebuilt
  copied artifacts. No second adapter, old transcript fallback or graph UI added.
- Agent/Storage/root README, deployment README, backend index/database/Agent specs
  synchronized. New durable-references spec has signatures/contracts/error matrix,
  good/base/bad examples, required tests and wrong/correct rules.

## 3. Actual final verification

All following gates were actually executed. Logs reside locally under `/tmp`, with
release artifacts under ignored `_build`; they are not committed evidence archives.
Random private distribution cookies were generated in the shell, not printed.
Test fixtures use fresh isolated datasets, never an existing user DB.

Common test settings:

```sh
export ERL_FLAGS='+S 2:2'
export BEAMLET_PG_SOCKET_DIR=/tmp/beamlet-storage-a-pg/socket
export BEAMLET_PG_PORT=55481
# Real local PostgreSQL, not a SQLite/mock substitute.
```

| Gate | Actual result | Evidence |
| --- | --- | --- |
| SQLite fork/history/export |35 passed | `/tmp/beamlet-d-ref-seventh.log` |
| Final umbrella, Agent SQLite + Storage real SQLite/PG |499 passed;37 distributed/process-phase exclusions | `/tmp/beamlet-d-final-umbrella.log` |
| Entire Agent suite on real PG |100 passed | `/tmp/beamlet-d-final-agent-pg.log` |
| Final full umbrella with `BEAMLET_AGENT_TEST_ADAPTER=postgres` |499 passed;37 exclusions | `/tmp/beamlet-d-final-umbrella-pg.log` |
| Named `--only distributed` |35 executed passes: Runtime7/Node20/Server2/Web5/CLI1 | `/tmp/beamlet-d-final-named-second.log` |
| Two independent OS-process durable-e2e |phase1 one pass, phase2 one pass | `/tmp/beamlet-d-final-two-process-second.log`; dataset/export `/tmp/beamlet-durable-e2e-0h6o5G` |
| Format check |exit0 | `/tmp/beamlet-d-final-format-second.log` plus final repeated check |
| Warning-fatal compile |exit0 | `/tmp/beamlet-d-final-compile.log` |
| Strict Credo `--strict --all` |206 files, no issues | `/tmp/beamlet-d-final-credo.log` |
| Sobelow |scan complete, exit0 | `/tmp/beamlet-d-final-sobelow.log` |
| Catalogue `gettext.extract --check-up-to-date` |exit0 | `/tmp/beamlet-d-final-catalogue.log` |
| Dialyzer |0 errors/skips/unnecessary skips; passed using existing PLT | `/tmp/beamlet-d-final-dialyzer.log` |
| `git diff HEAD --check` |exit0; repeated after final docs | `/tmp/beamlet-d-final-whitespace.log` |
| Backend dev/prod warning-fatal compiles |both exit0 | release logs below |
| Default/explicit Server, CLI and Web releases; Web compile/assets/digest |all exit0 | release logs below |
| Fresh copied/named release check |exit0, all checks below | release `check.log`, `copied/` |
| Named release cleanup tests |6 passed | release `cleanup-tests.log` |
| Real CLI PTY vectors |5 valid, invalid bytes rejected, options restored | release `pty.log` |

Full test commands were `mix test --seed 631927` (without and with Agent PG selector),
`BEAMLET_AGENT_TEST_ADAPTER=postgres mix test apps/beamlet_agent/test --seed 631927`,
and `elixir --sname <unique> --cookie "$cookie" -S mix test --only distributed
--seed 631927`. Other apps explicitly report zero executed tests in that last
command; they are **not** counted as distributed passes. The37 umbrella exclusions
are35 distributed tests plus the two independent-process phase tests, run separately.

Fresh release root:
`/mnt/data/Project/Beamlet/_build/d-final-release.gXXRfS/{server,server-explicit,cli,web}`.
Logs: `/tmp/beamlet-d-final-release.mKVaIq/` (individual backend-dev/prod,
server-default/explicit, cli, web-compile, tailwind, esbuild, digest, web logs).
Backend builds set `BEAMLET_BACKEND_BUILD=1`; prod builds set `MIX_ENV=prod`.
`BEAMLET_CHECK_LOG_DIR=<logs>/copied bash scripts/deployment/check-release.sh
<server> <cli> <web>` checked the copied closures, native daemon/RPC/pid/stop,
default/authority/executor named modes, authority→executor deterministic turn,
9 invalid host configurations without sentinel leakage, missing-dataset noncreation,
three independent CLI stdin sessions/reattachment/close, and Web secret rejection,
native controls, HTTP and CSS/JS serving. Copied manifest hash:
`31aa57e730a063ae0f083b61790437dfa6f0058ef6f3a930dc727fb5a6741212`.

Relative-link checks covered11 updated documentation files with no missing local
targets; `bash -n scripts/deployment/durable-e2e.sh` passed. LSP was intermittently
unavailable/timed out: **not counted as a clean gate**. Real compiler/Dialyzer and
strict checks above are the recorded static evidence. No tool exclusions or warning
suppressions were introduced.

## 4. Failures retained and corrected (not called passing)

- Earlier focused28-test SQLite/PG passes preceded the last adversarial additions;
  final35/100/full-umbrella results supersede them.
- `/tmp/beamlet-d-ref-sixth.log`:25/35 after replay hardening, caused by retaining
  an atom environment in the JSON fork_request. Fixed through strict normalized
  source shape/string value; final35 pass on both adapters. No Records codec
  weakening or atom-leaking fallback. Server fixture dropped obsolete freeze key.
- Earlier umbrella obsolete Server e2e failure was corrected by new event-based
  expectations and zero-repeat completed continuation; final two umbrellas pass.
- `/tmp/beamlet-d-final-format.log` failed on missing blank lines; formatted, then
  repeated format/compile/static gates passed. Initial static chain stopped there;
  it is not evidence that later checks passed.
- `/tmp/beamlet-d-final-named.log`:34/35; Node observation expected peer A to remain
  after disconnecting B in a visible triangle. OTP global's overlapping-partition
  prevention explicitly disconnected A. This is an **implicit topology assumption**,
  not a durable execution failure. Three minimized runs passed assertions but each
  logged the delayed extra disconnection (`/tmp/beamlet-d-topology-before-{1,2,3}.log`),
  explaining the race rather than resolving it by rerun.
- Fixture now uses explicit hidden peers and asserts both initial hidden connections
  and A's retained connection after B disconnect. Same negative assertion/partial
  response checks remain; no sleep, retry, relaxed bound or production change.
  Three minimized after-runs pass without the partition warnings, then the full
  named run passes35. Recorded in durable-references spec to prevent reintroduction.
  Other full visible routing/release tests were not converted or weakened.

## 5. AC mapping and remaining work

- D AC1/R1/R2: fork_test covers unchanged source rows, independent paused control,
  no cloned work/dedupe, exact replay after both Agents advance, missing/deleted
  content, forged omitted/foreign source, late evidence isolation, provenance/usage,
  environment gate/stale decision, retired parent events and chained fork/export.
- D AC2/R3: history_export_test covers offline reads, old cutoff, full requests,
  evidence/tools/provenance, concurrent later acceptance/appends, fixed cursor,
  long tiny-page histories, artifact/digest corruption, source-digest tampering even
  after file/Result hashes are recomputed, redaction/completeness, nonempty-dir
  safety, >4MiB artifact and malformed highwater. Context closure is content-backed.
- D AC3/AC4/R4/R5: actual full dual-adapter, named, process-window, independent OS
  process, strict/static/catalogue, backend and copied-release gates above. Existing
  memory/local/distributed functionality and A/B/C guarantees are exercised, not
  replaced by new D-only tests. No old-format migration or memory fallback added.
- **Main agent still owns independent review and parent AC1–AC7 acceptance.** D has
  not created an independent-check result or marked any task complete/archived.
- No known failing implementation gate remains in the final candidate. Boundaries
  remain intentional: no physical-host/power-cut/paid-provider acceptance, external
  side-effect rollback/exactly-once, old-format/API compatibility, graph UI, GC,
  import authority or unbounded context. Retained content must be backed up along
  with authority data. Capture hashes are integrity evidence, not signatures.
- Local temp logs/artifacts are present for review. No claim is made about their
  availability after `/tmp` or build cleanup; copy selected evidence deliberately
  if a permanent archive is needed. Do not delete actual databases to reproduce.
