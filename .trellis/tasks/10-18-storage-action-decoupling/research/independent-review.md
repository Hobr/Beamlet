# Independent cumulative migration review

Candidate: branch `refactor/storage-action-decoupling`, baseline `a8acffd`. This review includes tracked modifications/deletions and all untracked source/test files in both new persistence applications. No staging, commit, branch, task-status, archive or specification edits were performed.

Verdict: **READY for parent specification synchronization and commit review.** Both findings are fixed and all final applicable gates pass. No unresolved migration blocker or parent product/API decision remains. This is independent quality acceptance, not a claim that parent spec/commit/finish steps are complete.

## Findings

### F1 — P2, valid, fixed: unsafe strict JSON failure in Actions write facades

Location: `apps/beamlet_actions_storage/lib/beamlet/actions/storage/records.ex:23` (rescue boundary; correction at line 27). The Actions `Read` adapter classified strict domain JSON struct-load exceptions for reads, but `Records.transact` did not apply that classifier. Therefore persisted malformed Operation description or attempt budget could escape prepare/claim/accept/evidence as Ecto `ArgumentError` containing field bytes. This violates the safe domain error boundary; Agent's corresponding transaction boundary already handled it correctly.

Reproduction: initialize an Actions-only dataset, prepare an Operation, write `malformed` to its stored description via test-only SQL, call `OperationRecords.prepare` again. On both SQLite and PostgreSQL the new regression raised `cannot load ... as type #Beamlet.Actions.Storage.JSON...` instead of returning `{:error, :invalid_data}`. Original failures are preserved in `/tmp/independent-named.log`, Actions section, two failures. This was an actual executed reproduction, not inference from handoff prose.

Fix: delegate only rescued ArgumentError to the existing domain-local `Read.read` classifier, preserving the original stacktrace. Its exact Ecto struct-load/type/message match converts only the intended corruption error; unrelated programmer exceptions still raise. No transaction participant, API, schema, format, retry, timeout or module ownership was changed.

Regression: `apps/beamlet_actions_storage/test/actions_contract_test.exs:203`, shared on both adapters, checks prepare replay, claim and accept with corrupt description; evidence with corrupt attempt budget; unrelated ArgumentError propagation. All writes remain under the existing rollback boundary. Affected validation: complete Actions owning suite, ordinary/named umbrella, actual Agent PostgreSQL suite, static gates, fresh release checks and durable process-restart E2E.

### F2 — P3, valid, fixed: root formatting skipped the new applications

Locations: missing `apps/beamlet_actions_storage/.formatter.exs` and `apps/beamlet_agent_storage/.formatter.exs`, in conjunction with root `.formatter.exs:4`. Root delegates through `subdirectories: ["apps/*"]`; both new apps lacked a formatter configuration. Thus the ordinary root format gate did not cover their sources/tests even though owners had individually formatted selected files. Added matching Ecto/SQL formatter configurations using the established Storage app input patterns. This is a local verification coverage correction with no runtime/API change. Expanded root format revalidation is recorded below.

No other actionable source finding was identified in the reviewed candidate. Specification synchronization is intentionally parent-owned and pending, not silently treated as completed.

## Source and contract review

- Foundation: inspected Installation, Dataset, migrations, Repo/connection configuration, Host, Admission, Transaction, Codec/JSON and artifact/reference boundaries. Installation validates exact keys, foundation identity, unique component names/migration modules, ordered unique IDs and component ownership before SQLite file creation/Repo startup. Persisted manifests compare exact ordered component/module identities, installed marker and complete migration IDs. Open/verify do not install. SQLite readonly preflight checks legacy format before writable connection startup; PostgreSQL refuses after read-only queries. Old format, identity/profile mismatch, backup and incomplete installation tests inspect unchanged bytes/schema/business content as applicable. Foundation owns no Agent/Operation schema, field, event vocabulary, default profile or reverse app dependency; `journal_mode` is an engine setting, not journal-domain policy.
- Dependency and loading boundaries: inspected all three persistence manifests and Runtime/Agent/Node direct dependencies and root backend app list. New persistence apps and foundation have no Application callback. Actions/Runtime source has no Agent type/table/config/callback dependency (one Profiles doc mentions its composing consumer). Agent Storage has no dependency on Agent/Core/Runtime/Node/host. Neutral artifact content is used by both domains. Descriptors/participants support actual Actions-only and Agent consumers.
- Transactions/dispatch: traced Agent transition through locked Agent, domain source/control validation, Actions participant, association, Agent events, command save and single outer settle/rollback. Same-Repo participant checks `in_transaction?` and never commits. Agent restore rotates scope before CAS/event; claim takes scope SHARE before Operation UPDATE and attempt CAS; reauthorization takes scope then Operation; acceptance acquires no Agent/scope lock. Immutable scope ID plus expected digest/version/scope/epoch is checked again under claim lock. Public Runtime compares actual description, both IDs/versions, executor/boot, state and absent acceptance before starting coordinator. Agent continuation distinguishes accepted association adoption from prepared reauthorization and refreshes identity; claimed unresolved work refuses. Command replay returns stored original responses. No business retries or duplicate effect permission was introduced.
- References/projections: reviewed Agent-owned association and SQL projection migration, Loader/ContextBuilder/History/TraceSnapshot/TraceVerifier changes and Inheritance against baseline. Neutral Operation facts remain Actions-owned. Preparation/accepted events use the separate Operation log. Loader still verifies accepted digest before pending unconsumed results can be used; optional checkpoint corruption falls back. Source ownership/inherited authorization and fixed Agent/Operation capture remain intact. Fork retains flat closure without cloning executions. Trace envelope remains version2 because its exported content contract remains unchanged; dataset container is independently version3. Core diff is empty.
- Host/operator: Node explicitly composes Agent authority and Actions journal profiles; generic Host only owns explicitly opened resources. Admission checks the authority and every additional required resource, including journal. Refused opens retain reasons; stopped Repos fail safely. Interaction-only composition starts no Repo/gate. Operator stops only a Repo acquired by successful initialization, preserving an already-owned Repo on conflict. No boot migration/initialization or no-storage fallback changed.
- Repository references: searched apps/docs/scripts for removed Storage domain facades/schema/Repo/operator identities; no remaining executable caller was found. Old implementation references in `.trellis/spec/backend` are expected inventory for the parent: index/directory structure, database guidelines, runtime, Agent durability/references, backend release and checked quality evidence need synchronization. Existing implementation evidence is preserved unchanged.

## Baseline assertion audit

Compared baseline source directly with migrated tests, not just totals. Full review diff retained at `/tmp/independent-assertion-audit.diff`.

| Baseline suite | Current ownership and audit result |
| --- | --- |
| Storage dataset, 17 tests | Agent Storage dataset retains all17 groups: no-create open, byte-preserving old refusal, PRAGMAs, identity/profile/backup/newer refusal, missing metadata, registered Repo conflict before file access, config/path aliases, concurrent initialize, metadata DDL rollback, exact tables/journal JSON, deferred/immediate locks, busy/timeout cancellation, FK/version/seq/dedupe, Multi rollback/reopen and schema JSON bounds. Old cross-adapter global exclusion is replaced by same registered Repo exclusion, consistent with explicitly named neutral Repo instances. |
| Storage host, 8 tests | Node host retains all8 and adds stopped journal/default admission/owned shutdown and interaction-only cases; operator test also checks existing owner survival. |
| Storage record transactions, 5 tests | Actions journal retains insert-once/unknown restart, first stop, terminal/attachment/receipt/ack replay, malformed attachment rollback and raw/encoded limits. Journal implementation differs from baseline only in namespace/dependency/read boundary. |
| Storage domain contracts | Agent contract retains atomic prepare/accept/consume, sibling rollback, owner/turn/source/digest/generation refusal, body-free optional cache, competing CAS, claim/evidence/artifact constraints, consumption rollback, control/source/credential limits, held restore/accept-before-claim, no accepted first dispatch, foreign control, pagination, concurrent command uniqueness, raw objects and size limits. Independent operation assertions moved to Actions. Installation/connection/reopen assertions remain dual-adapter groups. |
| Explicit continuation | Prepared/accepted adoption and claimed unresolved refusal retained, with new refreshed binding, stale identity refusal, original command replay and failed sibling rollback assertions. Controlled PG claim-first/restore-first orderings additionally exercise real locks. |
| Codec/no-load | Original4 codec groups retained with numeric policy arguments, canonical integer/float spelling, duplicate key/credential/live-data refusal and byte/depth/node bounds. Fresh-VM no-load test retained. |
| Runtime sibling regression | Agent-free Runtime tests now assert neutral scope invariance. Agent domain contract still asserts unchanged Agent CAS on reverse sibling acceptance and actual Agent tests retain ordinal join behavior. This is an ownership transfer, not loss of the unique CAS assertion. |

Reviewed changed Agent tests: corruption targets now address owning base tables and separate logs; no success assertions or helper-lifetime assertions were removed to make them pass. Event count8 becomes Agent6 plus Operation2 explicitly. No timeout inflation, warning suppression, blanket JSON exception swallowing or new test skip was introduced.

## Validation environment and retained evidence

Elixir1.20.4/OTP29.1.2; PostgreSQL18.6 binaries at `/nix/store/4nz2y9q8kdn78axpm4jd7c1phmiygg58-postgresql-18.6/bin`. Private mktemp socket-only clusters, port55491, current OS user; tests create/drop only their temporary databases. `ERL_FLAGS='+S 4:4'`, seed631927; named VM uses independent random cookie. Mix commands run sequentially to avoid consolidated-artifact races. No real business dataset is used. Original and final logs have distinct names outside the repository.

Inspected actual retained `/tmp/integration-{compile-final3,format-final,credo-final,dialyzer-final,closures,check-release,durable-e2e,named,named-storage-final}.log`. They confirm prior reported compile/static/closure/copied-release/E2E results. The original integrated named run had one pre-fix view assertion and is not relabeled as a pass. The independent pre-fix named run deliberately reproduces F1 on both adapters and is also not acceptance.

Exact independent runners: `/tmp/beamlet-independent-validate.sh`, `/tmp/beamlet-independent-final-validate.sh`, `/tmp/independent-final-releases.sh`. Initial results: `/tmp/independent-results`; final results: `/tmp/independent-final-results`. Per-command logs use `/tmp/independent-<gate>.log` and `/tmp/independent-final-<gate>.log`. Cluster paths and lifecycle logs are recorded by the runners.

### Final independently executed gates

All commands below exited0 on the corrected candidate. Per-gate prefix is `/tmp/independent-final-` unless stated otherwise. Exact sequential command scripts above preserve options; named cookie values are intentionally omitted from this report.

| Command | Actual final result | Log |
| --- | --- | --- |
| `mix compile --warnings-as-errors` | pass | `compile.log` |
| `mix format --check-formatted` | pass; repeated after adding both new app formatter configurations, expanding actual coverage | `format.log`, `expanded-format.log` |
| `mix test --seed 631927` | **552 passed, 37 excluded** | `ordinary.log` |
| `elixir --sname independent_validation --cookie <random> --erl '+S 4:4' -S mix test --include distributed --seed 631927` | **587 passed, 2 excluded**; exclusions are the two separately executed E2E phase tags | `named.log` |
| `BEAMLET_AGENT_TEST_ADAPTER=postgres mix test apps/beamlet_agent/test --seed 631927` | **109 passed, zero excluded**, actual isolated PostgreSQL | `agent-pg.log` |
| `mix credo --strict --all` |242 source files, no issues; no suppression | `credo.log` |
| `mix dialyzer` |0 errors,0 skipped,0 unnecessary skips; existing PLT analysis, no forced refresh | `dialyzer.log` |
| `mix sobelow` | scan complete, exit0 | `sobelow.log` |
| `mix gettext.extract --check-up-to-date` |exit0; existing duplicate-backend warnings remain visible | `gettext.log` |
| `mix run --no-start /tmp/independent-closures.exs` | actual Actions-only and Agent Storage dependency startup, forbidden app sets absent, all neutral/domain Repos absent | `closures.log` |
| Fresh Server/CLI/Web releases; `bash scripts/deployment/check-release.sh` | all three rebuilt into fresh generated release directories, copied closure/native named launch/RPC/pid/stop/exit, bootstrap/Gateway execution,9 invalid configurations/no boot dataset creation, CLI independent sessions and Web HTTP/assets/secret gates pass | `release-{server,cli,web}.log`, `prod-compile.log`, `check-release.log` |
| `bash scripts/deployment/durable-e2e.sh` | phase1 one passed/two excluded, seed956393; phase2 one passed/two excluded, seed191027; separate OS processes, format3 persistence/trace2 export/restore/explicit continue/fork | `durable-e2e.log` |
| Copied artifact inventory audit | all three artifacts include all three callback-free storage libraries; removed Storage domain facades/Repos absent from actual beam files | `artifact-audit.log` |
| `git diff --check`; `git diff --cached --name-only` | clean whitespace; staged list empty | direct final inspection |

Final per-app ordinary/named counts, in dependency order: Harness35/35, Actions28/28, i18n15/15, Storage17/17, Core10/10, ActionsStorage17/17, Runtime66/73, AgentStorage64/64, Agent109/109, Node78/98, Server15/17, Web73/78, CLI25/26. Ordinary exclusions: Runtime7, Node20, Server4, Web5, CLI1. Named exclusions: Server2 E2E phases only. These are actual full final runs, not a union of earlier partial successes.

Adapter accounting for owning persistence suites (all executed, none excluded): Foundation10 SQLite foundation +2 PG +4 codec +1 fresh VM; Actions5 SQLite authority +7 PG authority +5 SQLite journal; AgentStorage17 SQLite dataset +23 SQLite domain +24 PG domain. Thus the three owning persistence applications executed65 non-PG cases and33 PG cases. Agent additionally executed109 cases on SQLite in the umbrella and109 on actual PG in its explicit adapter run. Journal intentionally remains SQLite.

Initial `/tmp/independent-named.log` failed only the two newly added F1 regression instances, proving pre-fix behavior. Initial strict Credo reported one repeated-module-prefix suggestion introduced by that regression; fixed with an alias, with final strict run clean. No original failed log was overwritten or relabeled as acceptance. Initial ordinary550 passed; final552 includes both added F1 cases.

Fresh copied release evidence: `/tmp/beamlet-release-logs.tZYW6o` (actual copied manifests/hashes and native controls). Durable process evidence: `/tmp/beamlet-durable-e2e-74kZtu`. Candidate changed-file inventory/hash list: `/tmp/independent-final-source.sha256`; complete baseline assertion transfer diff: `/tmp/independent-assertion-audit.diff`.

Owned clusters `/tmp/beamlet-independent-pg.bUwb0p` and `/tmp/beamlet-independent-final-pg.mIO0fG` both stopped cleanly; each retained `init.log`, `server.log`, `start.log`, `stop.log`. No other cluster or real dataset was touched. Release destinations were moved aside as generated artifacts before rebuilding, never overlaid on old releases.

## Final AC1–AC8 assessment

| Criterion | Assessment and evidence |
| --- | --- |
| AC1 | PASS: explicit source/manifests/dependency and live dependency-loading review; foundation neutral, Actions/Runtime Agent-independent, Agent Storage independent of Agent/Core/Runtime/Node/hosts. Actual copied artifact inventory confirms closures contain correct modules without old facades. |
| AC2 | PASS: Actions-only exact schema assertions and generic durable Handler Runtime prepare/claim/journal/evidence/accept/reopen contracts; ordinary66 and named73 Runtime cases pass. No Agent tables/config required. |
| AC3 | PASS: dual-adapter batch rollback, participant transaction requirement, command replay/changed request refusal, foreign ownership/source refusal and sibling reauthorization rollback. Reviewed outer settle/rollback and same-Repo participant implementation. |
| AC4 | PASS: controlled PG scope SHARE/Operation UPDATE ordering and restore/claim interleavings, Agent generation fence, accepted adoption versus pending reauthorization, stale refreshed binding refusal, late evidence and immutable acceptance. No automatic retry/effect replay. |
| AC5 | PASS: Agent109 on both SQLite and PG includes restore/fork/fixed high waters/optional cache fallback/digest tampering/export/offline verification; Core unchanged and10 tests pass. Reference/source and separate event-log routing reviewed against baseline. |
| AC6 | PASS: fresh dependency startup starts no Repo; Node host/admission tests cover required authority+journal and ownership/loss/refusal; copied host checks prove no dataset creation at boot; non-durable regressions and generic unknown-outcome behavior preserved. |
| AC7 | PASS: explicit format3 descriptors/profiles/migrations and complete-manifest verification; old2/old1, mismatch, backup/incomplete/refusal tests preserve SQLite bytes and PG schema/business content. No open/verify/host migration or real-data conversion. |
| AC8 | PASS within approved same-host/process-restart boundary: clean ordinary552 and named587, actual adapter suites, compile/expanded format/strict Credo/Dialyzer/Sobelow/catalogues, independent no-load closures, fresh copied releases and both E2E process phases. No unavailable adapter counted as a pass. |

The independent-check checkbox in task `implement.md` is now verified/checked. Parent specification/commit/finish checkboxes remain pending. Implementation-owner evidence was inspected and preserved unchanged; this report is at the authoritative output path requested for this run, rather than the earlier suggested research filename.

## Residual risks and parent responsibilities

No physical multi-host, power-cut/fsync failure-injection or paid-provider execution proof is claimed. Same-host named VMs and process-restart E2E do not establish those guarantees. Migration manifests bind module identities, not source hashes; installed migration implementations must remain immutable. Backup marker is an operator fact, not automatic rollback detection. Comprehensive LSP coverage remains inconclusive; actual compiler/tests/Dialyzer are primary evidence.

Parent owns specification synchronization, review of the commit batch and workflow finish. No product/API or module-boundary decision was needed for F1.
