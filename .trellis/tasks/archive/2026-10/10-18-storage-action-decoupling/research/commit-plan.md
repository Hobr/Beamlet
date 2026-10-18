# Storage decoupling: Phase 3.4 commit review

Status: revised seven-commit batch approved by the user (“行”) and executed in
order. The task is archived; journal recording follows. The file lists below are
the approved historical staging boundaries before archival, not current paths.
The user requested multiple commits in place of the original single work commit.

Branch: `refactor/storage-action-decoupling`; baseline/current HEAD: `a8acffd`.

## Proposed commits in order

1. `refactor(storage): isolate generic dataset infrastructure` — 21 paths.
   Foundation descriptor/install/open/verify, neutral Repo/transactions/codecs/artifacts/Host/Admission, owning foundation tests and README.

2. `refactor(actions): extract neutral persistence library` — 30 paths.
   Actions-owned schemas, migrations, profiles, records, scopes, evidence, acceptance and executor journal, with owning SQLite/PostgreSQL contracts. Pair corresponding old deletions with their destination.

3. `refactor(agent): extract domain persistence library` — 42 paths.
   Agent-owned schemas, associations, atomic composition, read projection, sources/history/inheritance and owning adapter tests/README; remove replaced combined domain helpers/migrations/test fixtures. Register both new libraries in the backend app allowlist.

4. `refactor(runtime): use neutral actions persistence` — 9 paths.
   Runtime Persistence/submit/coordinator/gateway integration, direct dependencies, generic durable execution tests and API README.

5. `refactor(agent): adopt domain storage adapters` — 19 paths.
   Agent facade, durable/restore/context/load/history/trace adapters, direct dependencies and retained regressions; Core is unchanged.

6. `refactor(node): compose domain storage profiles` — 16 paths.
   Node resource/operator composition and moved Mix task, Server host integration, host tests, deployment/release checks and READMEs.

7. `docs(storage): record persistence contracts and verification` — 25 paths.
   Nine backend specifications, architecture contract and this task's approved requirements/design/plan plus implementation, independent-check and spec-sync evidence.

The seven commits partition all 162 dirty paths exactly, without overlap.
Each code area's README and owning tests stay with its implementation. Removed
Actions/Agent source files are grouped with the corresponding new domain library
to make rename detection and review easier. Cross-domain specifications and
task evidence land together in the final documentation commit.

This is an ordered review split of one format/API migration. Existing full-suite
and release evidence applies to the complete final tree; intermediate commits
are not claimed to compile, pass all tests or be independently deployable.
Old/new callers, profiles and schemas must advance together in a deployment.
No compatibility shims or new product edits are introduced merely for splitting
the Git history. Old datasets refuse explicitly without conversion or deletion;
Agent Core remains unchanged and offline trace remains format2.

## Validation

Independent review is READY; AC1–AC8 pass. Recorded final evidence:
ordinary 552 passed/37 excluded; named 587 passed/2 excluded (the two E2E phase
tags ran separately); actual Agent PostgreSQL 109 passed. Compile, expanded
formatting, strict Credo, Sobelow, catalogue, existing-PLT Dialyzer, fresh copied
Server/CLI/Web release checks and two-process durable E2E passed.
See [independent review](independent-review.md) and [spec sync](spec-sync.md).

Final parent pre-commit checks: all 138 reviewed product file states match the
independent-review snapshot (112 present SHA-256 hashes and 26 expected deletions);
75 local Markdown link targets pass; context manifests validate; tracked whitespace
check passes; staged list empty. Subsequent edits only revised this commit-plan
document. Application/release gates were not rerun for documentation-only changes.

LSP remains inconclusive. Evidence is limited to same-host VMs/process restart;
it does not claim physical-host, power-cut or paid-provider execution.

## Exact file lists

`M` means modified, `D` removed and `??` a new file. Git may recognize
moves as renames. These lists are the explicit staging boundaries.

### 1. refactor(storage): isolate generic dataset infrastructure

```text
 M apps/beamlet_storage/README.md
 M apps/beamlet_storage/lib/beamlet/storage/admission.ex
?? apps/beamlet_storage/lib/beamlet/storage/artifact_changeset.ex
 M apps/beamlet_storage/lib/beamlet/storage/artifacts.ex
 M apps/beamlet_storage/lib/beamlet/storage/codec.ex
 M apps/beamlet_storage/lib/beamlet/storage/connections.ex
 M apps/beamlet_storage/lib/beamlet/storage/dataset.ex
 M apps/beamlet_storage/lib/beamlet/storage/host.ex
?? apps/beamlet_storage/lib/beamlet/storage/installation.ex
 M apps/beamlet_storage/lib/beamlet/storage/json.ex
 M apps/beamlet_storage/lib/beamlet/storage/migrations.ex
 M apps/beamlet_storage/lib/beamlet/storage/references.ex
?? apps/beamlet_storage/lib/beamlet/storage/repo.ex
 M apps/beamlet_storage/lib/beamlet/storage/repos.ex
 M apps/beamlet_storage/lib/beamlet/storage/schema/artifact.ex
 M apps/beamlet_storage/lib/beamlet/storage/transaction.ex
 M apps/beamlet_storage/test/beamlet/storage/codec_test.exs
?? apps/beamlet_storage/test/beamlet/storage/foundation_postgres_test.exs
?? apps/beamlet_storage/test/beamlet/storage/foundation_test.exs
 M apps/beamlet_storage/test/beamlet/storage/no_load_side_effects_test.exs
 M apps/beamlet_storage/test/test_helper.exs
```

### 2. refactor(actions): extract neutral persistence library

```text
?? apps/beamlet_actions_storage/.formatter.exs
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/codec.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/dispatch_scopes.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/executor_journal.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/json.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/migrations/authority_v1.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/migrations/journal_v1.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/operation_records.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/profiles.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/read.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/record_changeset.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/records.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/dispatch_scope.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/execution.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/execution_evidence.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/journal_attempt.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/operation.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/operation_event.ex
?? apps/beamlet_actions_storage/lib/beamlet/actions/storage/terminal_artifacts.ex
?? apps/beamlet_actions_storage/mix.exs
?? apps/beamlet_actions_storage/test/actions_contract_test.exs
?? apps/beamlet_actions_storage/test/journal_test.exs
?? apps/beamlet_actions_storage/test/test_helper.exs
 D apps/beamlet_storage/lib/beamlet/storage/executor_journal.ex
 D apps/beamlet_storage/lib/beamlet/storage/operation_records.ex
 D apps/beamlet_storage/lib/beamlet/storage/schema/execution.ex
 D apps/beamlet_storage/lib/beamlet/storage/schema/execution_evidence.ex
 D apps/beamlet_storage/lib/beamlet/storage/schema/journal_attempt.ex
 D apps/beamlet_storage/lib/beamlet/storage/schema/operation.ex
 D apps/beamlet_storage/lib/beamlet/storage/terminal_artifacts.ex
```

### 3. refactor(agent): extract domain persistence library

```text
?? apps/beamlet_agent_storage/.formatter.exs
?? apps/beamlet_agent_storage/README.md
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/agent_records.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/codec.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/events.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/history.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/inheritance.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/json.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/migrations/agent_v1.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/operation_records.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/profiles.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/read.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/record_changeset.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/records.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/agent.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/agent_operation.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/checkpoint.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/command.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/event.ex
?? apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/operation.ex
?? apps/beamlet_agent_storage/mix.exs
?? apps/beamlet_agent_storage/test/beamlet/storage/contract_test.exs
?? apps/beamlet_agent_storage/test/beamlet/storage/dataset_test.exs
?? apps/beamlet_agent_storage/test/support/contract_fixture.ex
?? apps/beamlet_agent_storage/test/test_helper.exs
 D apps/beamlet_storage/lib/beamlet/storage/agent_records.ex
 D apps/beamlet_storage/lib/beamlet/storage/events.ex
 D apps/beamlet_storage/lib/beamlet/storage/history.ex
 D apps/beamlet_storage/lib/beamlet/storage/inheritance.ex
 D apps/beamlet_storage/lib/beamlet/storage/record_changeset.ex
 D apps/beamlet_storage/lib/beamlet/storage/records.ex
 D apps/beamlet_storage/lib/beamlet/storage/schema/agent.ex
 D apps/beamlet_storage/lib/beamlet/storage/schema/checkpoint.ex
 D apps/beamlet_storage/lib/beamlet/storage/schema/command.ex
 D apps/beamlet_storage/lib/beamlet/storage/schema/event.ex
 D apps/beamlet_storage/priv/authority_migrations/2_authority_v2.exs
 D apps/beamlet_storage/priv/journal_migrations/1_journal_v1.exs
 D apps/beamlet_storage/test/beamlet/storage/dataset_test.exs
 D apps/beamlet_storage/test/beamlet/storage/record_transactions_test.exs
 D apps/beamlet_storage/test/beamlet/storage/storage_contract_test.exs
 D apps/beamlet_storage/test/support/contract_fixture.ex
 M mix.exs
```

### 4. refactor(runtime): use neutral actions persistence

```text
 M apps/beamlet_runtime/README.md
 M apps/beamlet_runtime/lib/beamlet/runtime.ex
 M apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex
 M apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex
 M apps/beamlet_runtime/lib/beamlet/runtime/persistence.ex
 M apps/beamlet_runtime/mix.exs
 M apps/beamlet_runtime/test/beamlet/durable_admission_test.exs
 M apps/beamlet_runtime/test/beamlet/durable_runtime_test.exs
 M apps/beamlet_runtime/test/support/fixture.ex
```

### 5. refactor(agent): adopt domain storage adapters

```text
 M apps/beamlet_agent/README.md
 M apps/beamlet_agent/lib/beamlet/agent.ex
 M apps/beamlet_agent/lib/beamlet/agent/context_builder.ex
 M apps/beamlet_agent/lib/beamlet/agent/durable.ex
 M apps/beamlet_agent/lib/beamlet/agent/history.ex
 M apps/beamlet_agent/lib/beamlet/agent/integration/caller.ex
 M apps/beamlet_agent/lib/beamlet/agent/loader.ex
 M apps/beamlet_agent/lib/beamlet/agent/reducer.ex
 M apps/beamlet_agent/lib/beamlet/agent/server.ex
 M apps/beamlet_agent/lib/beamlet/agent/trace_export.ex
 M apps/beamlet_agent/lib/beamlet/agent/trace_snapshot.ex
 M apps/beamlet_agent/lib/beamlet/agent/trace_verifier.ex
 M apps/beamlet_agent/mix.exs
 M apps/beamlet_agent/test/beamlet/context_read_order_test.exs
 M apps/beamlet_agent/test/beamlet/core_adapter_test.exs
 M apps/beamlet_agent/test/beamlet/durable_agent_test.exs
 M apps/beamlet_agent/test/beamlet/fork_test.exs
 M apps/beamlet_agent/test/beamlet/history_export_test.exs
 M apps/beamlet_agent/test/support/reference_fixture.ex
```

### 6. refactor(node): compose domain storage profiles

```text
 M apps/beamlet_app_server/lib/beamlet/server.ex
 M apps/beamlet_app_server/lib/beamlet/server/application.ex
 M apps/beamlet_app_server/test/beamlet/durable_e2e_test.exs
 M apps/beamlet_app_server/test/beamlet/durable_host_test.exs
?? apps/beamlet_node/README.md
?? apps/beamlet_node/lib/beamlet/node/storage.ex
?? apps/beamlet_node/lib/beamlet/node/storage/operator.ex
?? apps/beamlet_node/lib/mix/tasks/beamlet.storage.migrate.ex
 M apps/beamlet_node/mix.exs
?? apps/beamlet_node/test/beamlet/host_storage_test.exs
 D apps/beamlet_storage/lib/beamlet/storage/operator.ex
 D apps/beamlet_storage/lib/mix/tasks/beamlet.storage.migrate.ex
 D apps/beamlet_storage/test/beamlet/storage/host_storage_test.exs
 M scripts/deployment/README.md
 M scripts/deployment/check-named-release.py
 M scripts/deployment/durable-e2e.sh
```

### 7. docs(storage): record persistence contracts and verification

```text
 M .trellis/spec/backend/agent-durable.md
 M .trellis/spec/backend/backend-release.md
 M .trellis/spec/backend/database-guidelines.md
 M .trellis/spec/backend/directory-structure.md
 M .trellis/spec/backend/durable-references.md
 M .trellis/spec/backend/error-handling.md
 M .trellis/spec/backend/index.md
 M .trellis/spec/backend/operation-runtime.md
 M .trellis/spec/backend/quality-guidelines.md
?? .trellis/tasks/10-18-storage-action-decoupling/check.jsonl
?? .trellis/tasks/10-18-storage-action-decoupling/design.md
?? .trellis/tasks/10-18-storage-action-decoupling/implement.jsonl
?? .trellis/tasks/10-18-storage-action-decoupling/implement.md
?? .trellis/tasks/10-18-storage-action-decoupling/prd.md
?? .trellis/tasks/10-18-storage-action-decoupling/research/actions-handoff.md
?? .trellis/tasks/10-18-storage-action-decoupling/research/agent-handoff.md
?? .trellis/tasks/10-18-storage-action-decoupling/research/boundary-findings.md
?? .trellis/tasks/10-18-storage-action-decoupling/research/commit-plan.md
?? .trellis/tasks/10-18-storage-action-decoupling/research/foundation-handoff.md
?? .trellis/tasks/10-18-storage-action-decoupling/research/implementation-evidence.md
?? .trellis/tasks/10-18-storage-action-decoupling/research/implementation-lanes.md
?? .trellis/tasks/10-18-storage-action-decoupling/research/independent-review.md
?? .trellis/tasks/10-18-storage-action-decoupling/research/spec-sync.md
?? .trellis/tasks/10-18-storage-action-decoupling/task.json
 M docs/architecture/agent-operation-persistence.md
```

## Unrecognized dirty files

None. Every product path matches the independent reviewer snapshot; the remaining
paths are this task's nine synchronized backend specs and its planning/evidence
artifacts. The revised plan changes grouping only.

## After confirmation

Stage only each commit's listed paths and execute the seven work commits in order.
Verify the final committed product tree still matches the reviewed candidate.
Then apply the prescribed finish workflow: archive this completed task in
`chore(task): archive 10-18-storage-action-decoupling` and record the session in
`chore: record journal`. Preserve work commits → archive → journal ordering.
No push or amend is part of the plan.

Approval source: `.trellis/workflow.md`, Phase 3.4 step 5, says:
“Present the plan once, ask for one-shot confirmation.”
The user explicitly requested revised grouping and approved the complete revised
batch with “行”; no per-commit confirmation was needed.

## Execution result

1. `ae0668a` — generic Storage infrastructure.
2. `4fb6efb` — neutral Actions persistence.
3. `9ed8227` — Agent persistence.
4. `bb14c6b` — Runtime integration.
5. `182c656` — Agent adapters.
6. `306cb6a` — Node/Server/deployment composition.
7. `e9da8c1` — contracts and verification evidence.

Final committed file states were compared with the approved snapshot; all 162
paths matched, except the deliberate removal of an extra EOF blank line in two
task handoff/review Markdown documents. All 138 reviewed product states remained
unchanged. The working tree was clean before archival.

Archive bookkeeping rebased evidence links and context self-references to the
archive directory and recorded task completion. No product source or tests were
changed by the commit/finish phase, and no runtime gates were rerun solely for
these documentation changes.
