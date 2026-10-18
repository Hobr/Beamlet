# Final specification synchronization audit

Documentation-only synchronization after independent Check **READY**, baseline
`a8acffd`, branch `refactor/storage-action-decoupling`. Source/README facts were
read directly; design alone was not treated as evidence. Applied
[trellis-update-spec](../../../../.agents/skills/trellis-update-spec/SKILL.md), including
seven-section executable contracts for changed infrastructure/cross-layer behavior.
No product source, tests, configuration, manifests, scripts or workflow infrastructure
were edited. No formatting mutation, staging, commit, branch/status change, push or
archive operation was performed. Parent retains commit/finish ownership.

## Exact documentation files updated and ownership

| File | Contract or prevention it owns |
| --- | --- |
| `.trellis/spec/backend/index.md` |13-app inventory and routing to current format3/domain contracts; trace2 distinction. |
| `.trellis/spec/backend/directory-structure.md` | Actual apps/direct dependencies, callback-free boundaries, migration placement, Node composition; removes obsolete foundation domain layout. |
| `.trellis/spec/backend/database-guidelines.md` | Canonical seven-section installation/profile/metadata/table/transaction/host/codec contract and refusal matrix. Shared profile facts live here. |
| `.trellis/spec/backend/operation-runtime.md` | Neutral prepare/evidence/accept signatures, Persistence and prepared fields, exact locked binding/epochs, lock order and no replay. |
| `.trellis/spec/backend/agent-durable.md` | Agent-owned tables/projection/log routing, same-Repo batch rollback, accepted adoption versus pending reauthorization/refreshed versions; retained replay/Core limits. |
| `.trellis/spec/backend/durable-references.md` | Reference/projection ownership, fixed high waters and unchanged trace2/offline contracts. |
| `.trellis/spec/backend/backend-release.md` | Updated build/library closure, Node operator/profile/admission composition and fresh copied artifact checks. |
| `.trellis/spec/backend/quality-guidelines.md` | F2 child formatter requirement, F1 link, authoritative final validation accounting and evidence limits. |
| `.trellis/spec/backend/error-handling.md` | Seven-section F1 prevention: own strict JSON errors in BOTH reads/write facades; exact Ecto first-frame/type match; preserve programmer exceptions. |
| `.trellis/tasks/10-18-storage-action-decoupling/design.md` | Approved/implemented/independently checked status; preserves design decisions/constraints. |
| `.trellis/tasks/10-18-storage-action-decoupling/research/boundary-findings.md` | Explicitly historical pre-migration paths/claims; current evidence references. |
| `.trellis/tasks/10-18-storage-action-decoupling/implement.md` | README/architecture/spec-sync and phase3.3 checkboxes completed after docs checks; commit/finish remains unchecked. |
| `.trellis/tasks/10-18-storage-action-decoupling/research/spec-sync.md` | This durable source-anchor/change/verification audit. |

## Source anchors verified

Paths are relative to repository root. Line numbers identify the reviewed candidate
and can move; executable signatures, keys and refusal behavior were checked in the
surrounding implementation. App dependency claims were checked against all affected
child mix.exs and root allowlist; `rg --files apps -g mix.exs` reports13 manifests.

| Source anchor | Verified contract |
| --- | --- |
| `mix.exs:53` | Build allowlist; all13 child manifests counted independently. |
| `apps/beamlet_storage/lib/beamlet/storage/installation.ex:19` | Exact trusted descriptor keys, foundation1/ID1, ordered unique IDs/modules and manifest identity. |
| `apps/beamlet_storage/lib/beamlet/storage/dataset.ex:17` | initialize/open/verify ownership, refusal before writes and metadata/migration checks. |
| `apps/beamlet_storage/lib/beamlet/storage/migrations.ex:6` | Metadata fields, installed=false/true, exact manifest and foundation artifact-only migration. |
| `apps/beamlet_storage/lib/beamlet/storage/codec.ex:21` | Positive numeric bound/default4MiB; canonical bytes and safe limits. |
| `apps/beamlet_storage/lib/beamlet/storage/json.ex:6` | Foundation JSON requires max_bytes. |
| `apps/beamlet_storage/lib/beamlet/storage/transaction.ex:26` | Same-Repo active transaction; no nested commit; safe driver/JSON errors. |
| `apps/beamlet_storage/lib/beamlet/storage/host.ex:17` | Explicit dataset handles/ownership and fresh resource probes. |
| `apps/beamlet_storage/lib/beamlet/storage/admission.ex:51` | Recorded failures plus every required resource gate. |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/profiles.ex:4` | Actions authority1/100 and journal1/200, both foundation1/1. |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/profiles.ex:6` | Agent profile foundation1/1 + Actions authority1/100 + Agent1/300. |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/operation_records.ex:18` | Neutral prepare/participant and exact fields; claim expected_operation recheck; evidence/accept signatures. |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/dispatch_scopes.ex:11` | Scope0, rotation and prepared-only reauthorization; scope-before-Operation locks. |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/records.ex:17` | F1: write facade delegates ArgumentError to local Read with original stacktrace. |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/read.ex:5` | Exact first Ecto struct_load! frame and Actions JSON message/type match. |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/read.ex:5` | Agent boundary recognizes Agent and Actions JSON only, besides foundation classifier. |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/agent_records.ex:87` | Agent batch fields, one transition/rollback, command replay, accepted adoption vs prepared reauthorization. |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/migrations/agent_v1.ex:45` | Agent tables/associations and read-only agent_operation_projections join. |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/operation_records.ex:87` | Agent projection reader routes neutral Operation and attempt facts. |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/history.ex:63` | Separate Operation-event projection for trace readers. |
| `apps/beamlet_runtime/lib/beamlet/runtime/persistence.ex:22` | No owner; required authority/journal/identities plus optional paired scope/epoch. |
| `apps/beamlet_runtime/lib/beamlet/runtime.ex:149` | Stored description/IDs/digest/both versions/executor boot/state/acceptance/scope equality. |
| `apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex:291` | Exact locked claim binding supplied by coordinator. |
| `apps/beamlet_node/lib/beamlet/node/storage.ex:66` | Role/profile composition, default gate includes journal, runtime/status and owned lifecycle. |
| `apps/beamlet_node/lib/beamlet/node/storage/operator.ex:28` | Explicit installation; stops only successfully acquired Repo. |
| `apps/beamlet_node/lib/mix/tasks/beamlet.storage.migrate.ex:29` | Same operator command, now Node-owned. |
| `.formatter.exs:4` | Root delegates apps/*; child formatter presence required. |
| `apps/beamlet_actions_storage/.formatter.exs:2` | F2 Ecto/SQL import and child source/test inputs. |
| `apps/beamlet_agent_storage/.formatter.exs:2` | F2 matching child configuration. |
| `apps/beamlet_agent/README.md:89` | Trace export remains2 independently of dataset3. |
| `apps/beamlet_storage/README.md:1` | Current foundation README cross-check; no installation on load/open. |
| `apps/beamlet_agent_storage/README.md:36` | Current Agent README cross-check, refreshed binding and original response. |
| `apps/beamlet_runtime/README.md:21` | Current Runtime README cross-check against neutral Persistence API. |

## Evidence and history handling

[Independent review](independent-review.md) is the authoritative final evidence:
ordinary552/37 excluded; named587/2 excluded (separately executed E2E tags); actual
Agent PostgreSQL109. It records complete owning adapter accounting (Foundation
10 SQLite+2 PG+4 codec+1 no-load; Actions5 SQLite+7 PG+5 journal; Agent Storage
17 dataset+23 SQLite+24 PG), existing-PLT Dialyzer0 errors/0 skipped, compile/expanded
format/strict Credo/Sobelow/catalogue, fresh three releases and both process E2E
phases. This sync did not rerun these gates or manufacture new passing logs.
F1 and F2 are fixed, with no remaining independent blocker.

[Implementation evidence](implementation-evidence.md) remains unchanged as the
implementation owner's historical record. Its pre-independent pending statements,
earlier counts and failed named/adapter/compile logs are not relabeled final passes.
Boundary-findings deliberately retains old removed paths under an explicit historical
baseline heading. Existing release/quality historical stage results remain labeled
as such. No mechanical trace2-to-dataset3 replacement occurred; Core source is
unchanged by this migration and by this synchronization.

## Documentation verification

- Read existing specs before edits and manually compared current READMEs/source.
- Local Markdown link targets verified with `/tmp/verify-spec-sync.py`; no missing
  targets. Reviewed source anchors above all exist and contain their named API/frame.
- Exact profile/component/migration IDs, metadata fields, prepared/evidence/accept
  payload keys, lock order, error atoms and no-auto-install boundaries match source.
- Stale API scan over owned specs found no removed foundation domain facade, fixed
  authority/journal Repo or old migration-path claim. Foundation JSON and neutral
  Host references are current APIs; old format2/1 appear only as refusal/history or
  independently unchanged trace2 protocol.
- `git diff --check` passes. Tracked diff outside owned documentation matches the
  arrival snapshot `/tmp/spec-sync-before.diff`; staged list remains empty.
- Seven sections retained/added for infrastructure/runtime/Agent/reference contracts;
  shared installation facts are linked rather than repeated as competing contracts.
- Application/release tests intentionally not rerun for Markdown-only edits.

## Residual risks and next responsibility

No unexpected source inconsistency or documentation blocker found. Independent
limitations remain: same-host/process-restart evidence only, no physical-host,
power-cut or provider claims; LSP coverage remains inconclusive. Migration identities
are not source hashes and installed migrations must remain immutable; backup marker
is an operator fact. Parent owns batch review/commit approval and finish. This audit
attests documentation synchronization, not a new execution of application tests.
