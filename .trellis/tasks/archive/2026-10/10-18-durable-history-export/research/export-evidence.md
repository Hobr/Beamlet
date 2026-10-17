# Stage D evidence — durable history queries and bounded trace export

Date: 2026-10-18. Branch `feat/durable`. Prerequisites committed: stage A
`3aefa85`, stage B `11577fb`, stage C `f7be001`. Everything below was run in this
slice against the current worktree; nothing was committed by this sub-agent.

## Callable surface

Read-only, keyed by the persistent locator (`%{repo:, agent_id:}`); no live Agent,
coordinator or Runtime retention is consulted, and no call returns a PID/Ref.

```elixir
# Public Agent facade
{:ok, page} = Beamlet.Agent.history(locator, %{view: :turns})
{:ok, page} = Beamlet.Agent.history(locator, %{view: :facts, after_seq: 0, through_seq: 12,
                                               type: "operation.prepared", turn_id: t,
                                               operation_id: o, origin: :inherited,
                                               limit: 100, max_bytes: 65_536}, cursor)
{:ok, snapshot} = Beamlet.Agent.history(locator, %{view: :context, as_of_seq: 7})
{:ok, steps}    = Beamlet.Agent.history(locator, %{view: :steps})
{:ok, tools}    = Beamlet.Agent.history(locator, %{view: :tools})
{:ok, evidence} = Beamlet.Agent.history(locator, %{view: :evidence, operation_id: o})
{:ok, decisions}= Beamlet.Agent.history(locator, %{view: :decisions})
{:ok, prov}     = Beamlet.Agent.history(locator, %{view: :provenance})

# Export: fix the high-water mark first, then stream; or both in one call.
{:ok, fixed}    = Beamlet.Agent.TraceExport.begin(repo, %{agent_id: id})
{:ok, manifest} = Beamlet.Agent.TraceExport.write(fixed, %{dir: dir, page: 100,
                                                           page_bytes: 1_048_576,
                                                           redaction: :none | :drop_content})
{:ok, manifest} = Beamlet.Agent.TraceExport.export(repo, %{agent_id: id}, policy)
{:ok, report}   = Beamlet.Agent.TraceExport.verify(dir)   # read-only, no execution
# Agent.export(locator, scope, policy) and Agent.history/3 delegate to the above.
```

Storage-level queries live in `Beamlet.Storage.History` (`event_page/3`, `event/3`,
`checkpoint_at/3`, `checkpoint_page/3`, `turns/3`, `operations/3`, `operation/2`,
`evidence/2`); see `apps/beamlet_storage/README.md`.

## Three distinct views

| View | Surface | Source |
| --- | --- | --- |
| Facts recorded at a time | `view: :facts` / `:turns` / `:steps` / `:tools` / `:decisions` | `events`, `operations`, `executions`, `execution_evidence` rows |
| Agent's effective context | `view: :context` with `as_of_seq` | immutable `checkpoints` row at or before that sequence |
| Current runtime observation | **not part of history** | stays in `Beamlet.Runtime.status/1` / `Beamlet.Node.observation/0` |

`view: :context` returns `as_of_seq`, `derived_by: "commit_order"`, the checkpoint
identity/digest/`safe_to_fork`, `messages`, `step`, `pending`, `blocked` and
`source_markers` (index plus `source_agent_id`/`source_event_id` for inherited
messages). A later event cannot rewrite it because checkpoints are immutable.

## Manifest and JSONL schema

`manifest.json` (export version 1):

```json
{"export_version": 1, "format": "beamlet.trace", "exported_at": iso8601,
 "authority_id": uuid, "agent_id": uuid,
 "scope": {"kind": "agent", "id": uuid},
 "ordering": "per_scope_sequence",
 "high_water": {"agent_id": uuid, "history_seq": n, "checkpoint_recorded_at": iso8601},
 "fork": {"forked_from_agent_id": uuid|null, "forked_from_checkpoint_id": uuid|null,
          "history_included": false},
 "files": {"events": "events.jsonl", "checkpoints": "checkpoints.jsonl", "artifacts": "artifacts"},
 "counts": {"events": n, "checkpoints": n, "artifacts": n},
 "page_policy": {"page": n, "page_bytes": n},
 "digests": {"events_sha256": hex, "checkpoints_sha256": hex},
 "artifacts": [{"id": uuid, "digest": hex, "media_type": text, "size": n, "path": "artifacts/<id>.bin"}],
 "oversized_records": [{"kind": "oversized_record", "seq": n | "checkpoint_id": uuid}],
 "missing": [{"kind": "artifact_missing|artifact_corrupt|artifact_unwritable|ancestor_history", ...}],
 "redaction": {"policy": "none|drop_content", "restorable": bool, "dropped_entries": n},
 "provenance": {"performed_entries": n, "inherited_entries": n,
                "inherited_counted_as_execution": false,
                "external": [{"relation": "fork_source", "agent_id": uuid, "checkpoint_id": uuid, "included": false}]},
 "history_complete": bool}
```

`history_complete` = no missing items **and** `redaction.restorable` **and**
exported events == the fixed `history_seq` (per-Agent sequences are contiguous, so
a short count means a committed position was not exported).

`events.jsonl` one line per event, original identity preserved:
`{"scope_id", "seq", "type", "schema_version", "payload", "recorded_at",
"turn_id", "operation_id", "causation_id", "dedupe_key", "source_agent_id",
"source_event_id", "origin"}`. With `redaction: :drop_content` the payload becomes
`{"redacted": true}` and the line carries `"redacted": ["payload"]`.

`checkpoints.jsonl` one line per checkpoint: `{"id", "agent_id", "turn_id",
"continuation", "schema_version", "digest", "safe_to_fork", "recorded_at",
"data"}`; under redaction `data` keeps structure/`continuation`/`step`/`turn_id`
and drops `messages`, `assistant`, `results`, `pending`, `order`, `consumed`,
`decision`, `request_digest`, with `"redacted": [dropped keys]`.

There is no cross-Agent global order: every line keeps its own scope and sequence,
`ordering` is `per_scope_sequence`, and a single export covers one Agent scope.

## Behaviour that the requirements call out

- **Fixed high-water mark.** `begin/2` reads the Agent row once and stores
  `history_seq` plus the newest checkpoint `recorded_at`. `write/2` reads only
  `seq <= history_seq` and `recorded_at <= checkpoint_through`, so concurrent
  appends cannot drift into the range (test appends an input between `begin` and
  `write`).
- **Short transactions.** Each page is one `Repo` read; no transaction spans a
  page, a file write or the whole export. SQLite WAL checkpoints are not pinned.
- **Bounded memory.** Streams write line by line to an open file; page size and
  byte budget are configurable (`page` 1..500, `page_bytes` 4 KiB..4 MiB). A
  record larger than the page budget is written whole on its own line and listed
  in `oversized_records` — never split or silently truncated; it stays bounded by
  the record's own 4 MiB codec limit.
- **Inherited vs performed.** Storage tags each event `origin` from
  `source_agent_id`; the manifest counts `performed_entries` and
  `inherited_entries` and reports `inherited_counted_as_execution: false`. A fork
  source's own history is never assembled recursively: it appears in
  `provenance.external` (and in `missing` as `ancestor_history`).
- **Artifacts.** Only references the Agent definition actually holds
  (`tools.*.artifact_refs`) are exported, as raw bytes under `artifacts/<id>.bin`
  with digest/size/media type in the manifest. Missing, corrupt (`Artifacts.fetch`
  detects a digest mismatch) and unwritable artifacts are reported in `missing`.
- **Verification.** `verify/1` re-reads `manifest.json`, checks shape/version/
  identity, streams both JSONL files to recompute SHA-256, validates each line's
  required keys, scope and strictly increasing sequence, and re-hashes every
  artifact. It parses data only; it never loads code, never restores an Agent and
  returns `execution_authority: "none"`.
- **Redaction.** `:drop_content` drops payload/context content while marking each
  line and sets `restorable: false`, `history_complete: false`.

## Commands actually run

| Command | Result |
| --- | --- |
| `mix format --check-formatted` | exit 0 |
| `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_agent/test/beamlet/history_export_test.exs` | **12 passed, 0 failed** |
| `mix test apps/beamlet_agent/test` | **56 passed** (44 pre-existing + 12 new) |
| `mix test apps/beamlet_storage/test` | **51 passed, 13 excluded** (PostgreSQL contract module excluded, `BEAMLET_PG_*` unset) |
| `mix test` (whole umbrella) | **320 passed, 0 failed, 42 excluded** (harness 35, actions 28, storage 51+13, runtime 52+6, agent 56, node 68+20, daemon 5+2, cli 18+1, web 7) |

SQLite only in this slice (engine shipped with `exqlite` 0.42). Every test creates a
real authority/journal file pair through `Beamlet.Storage.Dataset.initialize/2` in
an isolated temp directory, stops both Repos and removes the directory; no
in-memory database is used. `mix credo` was not run in this slice (advisory only;
repo baseline is unchanged by new code paths).

## Test coverage added (12 tests in `apps/beamlet_agent/test/beamlet/history_export_test.exs`)

- history read with **no live Agent** after `Agent.close/1` (asserts the process is
  dead and `Agent.lookup/2` fails) and with Runtime `expiry_ms: 50`: turns, facts
  (`origin: performed`), and the effective context messages;
- `as_of_seq` returns the context at that point and re-reading after more
  committed evidence returns the identical message list;
- turns, model steps (`model.reply_recorded` + stored reply), tool requests/results
  (ordinal order, accepted Result), execution evidence (attempt + receipt digest)
  and decision/execution-result facts are reachable through the public views;
- export while an event is appended **between `begin` and `write`**: manifest
  `high_water.history_seq` stays fixed, exported events stop at it, a second export
  then reports the appended event;
- JSONL lines parse (every line decoded), artifact digest/size verify, a corrupt
  stored artifact is reported as `artifact_corrupt`, a referenced-but-absent
  artifact as `artifact_missing`, both with `history_complete: false`;
- a 12 KiB context record with `page_bytes: 4_096` produces one
  `oversized_record`, and the exported checkpoint line still carries the full
  content;
- inherited event fixture (`source_agent_id`/`source_event_id` written through
  `Records.event_changeset`): `origin: inherited`, markers preserved in the export,
  `provenance.inherited_entries == 1`, `performed_entries == 2`,
  `inherited_counted_as_execution == false`;
- fork fixture: `provenance.external` reports the source Agent with
  `history_included?: false`, the manifest lists `ancestor_history` under
  `missing` and sets `history_complete: false`;
- the verifier rejects a tampered event line (`:digest_mismatch`), a structurally
  defective line even after the digest is recomputed (`{:missing_line_key, _}`), a
  tampered manifest identity (`:invalid_data`) and an unsupported export version
  (`{:unsupported_export_version, 99}`);
- redaction drops payloads while marking them, no sensitive text reaches the file,
  `restorable: false`, `history_complete: false`;
- keyset paging with `page: 2` exports every event once in strictly increasing
  sequence order.

## Remaining gaps (honest limits)

- **PostgreSQL not run** for the new queries/export (same limit as stages A–C).
  `History` uses portable Ecto queries only (group_by/min/max, keyset comparisons,
  `CAST(? AS TEXT)` for the byte budget), but no dual-adapter test covers it.
- **`as_of_seq` derivation.** `checkpoints` has no `history_seq` column (no new
  column or migration was allowed in this stage). The checkpoint at a cursor is
  derived from commit order (`recorded_at` written in the same transaction as the
  event). A wall-clock jump that reordered commits relative to recorded time could
  pick the neighbouring checkpoint; there is no test for that (a clock cannot be
  manipulated through the facades). A future stage could store the sequence on the
  checkpoint to make the relation explicit.
- **Model-step Operations are not in the Agent scope.** A durable model step is
  committed as an unowned Operation (its own `scope_id = operation_id`, stage C
  limit), so `view: :steps` exposes the `model.reply_recorded` fact plus the stored
  reply/`request_digest` and reports `step_operations: "external"`; the model
  Operation row itself is reachable only by `view: :evidence`/`Storage.History.operation/2`
  with its id. Full model *request payload* per step is therefore not part of the
  Agent-scope export.
- **Artifact references** are only those in the Agent definition
  (`tools.*.artifact_refs`). `OperationRecords.accept_result/2` verifies
  `artifact_ids` in its transaction but stores no reference column, so result
  attachments are not discoverable from the authority rows and are not exported
  (executor journal attachments remain executor-local).
- **Sequence completeness** uses `exported_events == history_seq`. Reserved batch
  accept positions that never committed would make that false and are reported as
  incomplete rather than as a precise gap list.
- **Redaction** is content-dropping only (whole payload / whole context keys), not
  field-level or pattern-based secret scanning; no text secret scanner is claimed.
- Fork/late-evidence interaction is fixture-verified; the real fork path arrives in
  stage E.
- The inherited-event fixture writes through `Records.event_changeset/1` (the
  stage-E writer does not exist yet); that path is a test fixture, not a new public
  write API.

## Parent acceptance (2026-10-18)

The independent review returned "OK with notes": no blockers, two P1 gaps and several P2
notes. The parent fixed them rather than shipping the caveats.

P1 — `verify/1` raised `File.Error` for a missing or non-regular `events.jsonl` /
`checkpoints.jsonl`, which is exactly the truncation/tamper case the verifier exists for.
It now stats the file and returns `{:error, {:missing_file, name}}`; a test deletes the
file and asserts the error.

P1 — the PRD's "usage / local durations" acceptance item had no evidence and no disclosure.
Usage and cost facts are not part of the durable contract: the exported trace supports
durations derived from `recorded_at` and per-scope ordering, but not token or cost
analysis. That bullet is **partially met** and is recorded here and in the task PRD.

P2 fixes: `write_event/2` and `write_checkpoint/2` now return tagged results so a codec
limit or a failed write surfaces as `{:error, reason}` instead of a `MatchError`; the
verifier recomputes `history_complete` from the verified highs, counts, `missing` and
redaction instead of echoing the manifest, and refuses `:inconsistent_manifest` (tested by
hand-editing the flag); artifact references beyond the 64-entry cap are reported as
`artifact_omitted` rather than dropped silently; `:provenance` reports
`inherited.truncated` instead of presenting a capped page as a total; a message carrying
only one source marker is still reported as inherited; the turn/operation views are
documented as row-bounded (only event and checkpoint pages carry a byte budget) and pages
no longer claim an enclosing read transaction; operation pages document their
`(history_seq, id)` tie-break; a cursor round-trip test now covers `Agent.history/3`
paging, and the redaction test also asserts the checkpoint file no longer contains the
dropped prompt.

Parent-run gates:

| Command | Result |
| --- | --- |
| `mix format --check-formatted` / `mix compile --warnings-as-errors` | exit 0 |
| `mix test apps/beamlet_agent/test/beamlet/history_export_test.exs` | **15 passed** (12 implementer + 3 parent) |
| `mix test` (umbrella) | see the final run below |

Remaining gaps unchanged: PostgreSQL is not exercised for the new history/export code;
`as_of_seq` relies on checkpoint-before-event write order; fork export is covered by a
fixture, not by a real stage-E fork; redaction is whole-field only.
