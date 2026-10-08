# Core verification execution plan

Current packaging authority: ALL verification evidence is LOCAL ONLY and Git-ignored, including `spec/quint/core/evidence/retained/`. Required checkout-readable results/configuration/limits/commands are in the [Chinese core report](../../../spec/quint/core/verification-report.md). A fresh checkout cannot inspect excluded original logs. Historical source hashes and stage dispositions remain attributed; no new model checks are executed during packaging. The old735-file full-raw and122-file compact-pack proposals are superseded, never approved.

This plan supersedes the all-contract plan under `research/pre-core/`, following the user's explicit core-abstraction direction. Task remains in progress; implementation approval persists. Scope reduction is explicit and does not mean the old coverage gates passed.

## 1. Scope and safe handoff

- [x] Stop the previous broad workflow and pause its sole writer before replacing future stages.
- [x] Preserve planning history and partial diff (`research/pre-core/`, `/tmp/beamlet-quint-core-rescope.patch`).
- [x] Rewrite PRD/design around C1–C6 and explicit interface assumptions/non-goals.
- [x] Record completed core fixes in the paused writer checkpoint and resume it under the revised scope.

## 2. Small executable abstraction

- [x] Write/read the minimal state sketch from revised design; start with one Run/Effect and two Attempts/owners.
- [x] Add `spec/quint/core/` conceptual model, separate tests and single-instance analysis entries. Typecheck and execute init plus one guarded transition immediately.
- [x] Implement only the distinctions needed by C1–C6: held proposals/current control, committed intent/grant, local entry and completion, authority knowledge/unknown, final reply/consumption, one-use permission, recorded stable prefix/fresh branch.
- [x] Name and document assumed interface behavior. Do not port full receipts/DTO/roles/Scope/ETF/data validation or a giant State/dispatcher.
- [x] Compose retained actions in a common step; add the smallest source/branch or multi-Effect configuration to expose interference.
- [x] Add independent properties and a few representative deterministic race traces/negative controls alongside the model.

## 3. Actual checks

- [x] Typecheck primary model/entries/tests and run meaningful deterministic traces/mutations.
- [x] Verify no initialization witnesses, unconditional stutter, circular blocked classifier, inherited active grants or uncertainty/failure conflation.
- [x] Run >=10,000 final core-composition sampled traces with meaningful depth and recorded seed/source/domain/witnesses. Investigate zero witnesses; deterministic reachability is labeled as such.
- [x] Compile only the needed analysis instance. Run a nonzero-depth diagnostic, then actual depth-10 representative composition BMC with a reasonable explicit budget and fresh attributable backend evidence.
- [x] Record each result exactly. Timeout/serializer/backend failure is inconclusive; focused or deterministic success cannot stand in for the core-composition bound.
- [x] Preserve counterexamples and owning source clauses. Source contradictions require an owner decision; model corrections preserve the contract.

## 4. Presentation and review

- [x] Make the primary README explain the few architectural questions, state correspondence, assumptions and commands.
- [x] Make the report lead with C1–C6 results and scope, not raw scenario counts. Retain R/S/P mappings only as useful traceability with core/supplemental/out-of-scope labels.
- [x] Mark the large exploratory suite and its unresolved findings as supplemental/superseded. Preserve useful defects/counterexample logs; avoid duplicating all old logs in the primary narrative.
- [x] Provide a compact primary runner, with one clear default path. Detailed-suite checks remain explicitly supplemental.
- [x] Have an independent check agent review the revised abstraction, meaningful composition, properties/mutations, source fidelity and exact evidence. Do not reimpose superseded all-contract requirements.
- [x] Fix accepted defects and rerun only affected checks. Complete whitespace/docs checks.

## 5. Authorized design refinement and verification

User authorization: “请尝试修复并进行验证”, after the concrete evidence/permission/recovery/failed-work/implementation-obligation recommendations. This continues the active task; no new task approval or implementation approval is required.

- [x] Preserve the initial dirty-state snapshot; load current source and manifests before editing.
- [x] Refine the proposed source contracts with result/permission/recovery tables, captured failure meaning, failed retained-work policy and I1–I4 implementation obligations; retain architecture-v1/ADR review statuses.
- [x] Synchronize the minimal executable core and independent properties; centralize evidence reduction without making assertions circular. Preserve transition grain and default open composition.
- [x] Add meaningful failure/unknown/control/terminal and recovery regressions plus detecting transition mutations. Exercise conditional recovery with explicit premises and document evidence strength.
- [x] Typecheck and execute deterministic checks; sample at least 10,000 current-source default-init/step composition traces with actual witnesses, hashes, seed and meaningful depth.
- [x] Run useful focused bounded checks and an actual current-source representative depth-10 composition check with an explicit finite budget. No identical unbounded retry loop; no timeout-as-proof.
- [x] Fresh independent check agent reviews source fidelity, simplicity, mutation detection, conditional progress and exact evidence; fixes accepted issues directly, serially, and reruns affected checks.
- [x] Parent synthesizes findings, updates evidenced durable conventions if needed and records unresolved runtime/bounded obligations. Commit/closure remains parent-owned under the normal gate.

Rollback: retain historical evidence and the scoped dirty diff snapshot `/tmp/beamlet-design-repair-before.patch`; do not reset the index or overwrite unrelated work. No runtime/package installation, architecture review-status promotion, terminal settlement feature or full detailed-suite restoration is included.

## 6. Authorized post-repair architecture review

User steering: “在完成对现有设计和模型的修复后对未评审内容进行评审、完善、适当进行验证”. This follows section 5; do not interrupt or expand the active repair writer/checker midway.

Active dispatch: `/tmp/beamlet-quint-pending-design-workflow.js` passed native validation and launched as async workflow `4f0f34e0-25a0-4970-aba1-43db48a54fe3`, mission `b8e729e3-8b2e-4c4e-92bd-72f08caa4f90`. It serially runs a read-only primary-source auditor, fresh read-only architecture reviewer, sole repair writer and fresh final checker, with managed outputs under `quint/pending-*.md`. The completed repair gate from workflow `9a53b831-2252-4127-829d-08965de4747e` and checker `6e831d58-5f5e-45e1-89df-f75ac4fa0a97` was consumed; its actual independent report is passed as `repairGatePath`. Intake: `research/pending-design-review.md`. Pre-review snapshots: `/tmp/beamlet-pending-review-status-before.txt` and `/tmp/beamlet-pending-review-before.patch`. Native completion notifications govern dependency barriers; no polling/wait loop.

- [x] Consume the repair implementation and independent-check artifacts; inspect current source and attributable evidence before proceeding.
- [x] Inventory pending ADR-008 clauses/refinements, ADR-007's conditional candidacy and unvalidated implementation/interface/resource assumptions; define source-linked review questions and proportionate evidence.
- [x] Fresh read-only reviewer assesses coherence, implementability, alternatives, authority/permission/evidence/lifecycle behavior and validation boundaries across the owning contracts. Preserve findings and per-item dispositions.
- [x] Sole writer resolves accepted findings and records consistent reviewed/pending/conditional/deferred statuses with reasons and a durable technical review record; preserve the historical architecture-v1 baseline.
- [x] Run affected formal or source checks as justified by changes. Reuse unchanged-source evidence; semantic model changes require fresh tests/sampling and one bounded composition attempt (240 seconds), with at most two useful focused checks (120 seconds each).
- [x] Fresh final checker verifies source consistency, addressed findings, review-status attribution and exact evidence; parent synthesizes remaining implementation and bounded-check obligations.

Section6 writer outcome (2026-10-08): fresh audit/review consumed; P1 delayed same-Attempt monitor ordering resolved under parent ticket `b2de24cf-846f-4aa3-a72e-94be9b39e8fa` (durable decision: `research/pending-monitor-supervisor.md`). P2 Ra API citations pinned to v3.2.0 and `wal_sync_method=none` rejected by adoption configuration. Effect/OperationDeclaration/capture tables aligned with the existing captured declaration contract. Chinese durable per-item record: `spec/architecture/protocol-review-2026-10-08.md`; ADR-008 technical design accepted after the scoped clarification, ADR-007 conditional, runtime gates outstanding. Architecture-v1 / ADR-001–006 historical decisions preserved.

Actual model/composition/recovery/runner hashes unchanged and independently matched to prior repair evidence; no semantic model change or expensive repeat. New test typecheck, three focused monitor guard/fact tests and all46 tests (28 positive/18 mutations) pass; future queued distinct-ID payload/audit behavior is explicitly I2/I3, not executed here. Reused10,000 default-composition depth60 samples/seed20261014, ten positive witnesses (consumption5/recovery1); all-actions composition depth10/240s/port8863 timeout124 at State5 remains inconclusive with no lesser bound. Restricted recovery depth14 NoError remains schedule-scoped. New exact commands/hashes/source checks: `spec/quint/core/evidence/pending-design-review/`. Parent-owned decision artifact is preserved. Index fingerprint was observed to refresh externally (initial `d3beae8a…` -> `5ed7da90…`); no child Git mutation or rollback. The writer-stage gate status is historical; the completed final independent check and parent acceptance are recorded below.

This later authorization permits justified review-status changes for actually reviewed proposals; section 5's status-preservation restriction applies to the repair stage only. It does not imply verified runtime implementation or restore exhaustive modeling. No package/runtime installation or terminal settlement feature is authorized.

## 6.1. Authorized LOCAL-ONLY evidence packaging and Chinese documents

Latest user authority: “我认为可以保留, 但不应该git添加验证证据” and “修改后端规范, 使用中文”. This supersedes the compact-pack tracked-eligible proposal; all evidence is local-only, including retained metadata/log/hash/model/probe/ITF copies. No semantics or technical acceptance changes.

- [x] Inspect actual Git/index/HEAD and evidence inventories; preserve every local artifact and unrelated changes/index entries.
- [x] Ignore BOTH complete evidence directories with rooted rules and no retained exception. Only when evidence is freshly found staged, remove its exact index paths, preserving local bytes; stage nothing.
- [x] Preserve local source-bound final evidence and indispensable original defects; keep copied artifacts verbatim. Put concise result/configuration/limit/hash/command summaries in eligible authored reports, without claiming fresh-checkout access to excluded logs.
- [x] Translate core/historical reader README/report/coverage and backend Quint guide into Chinese; enforce the lasting exact backend index policy. Preserve identifiers, commands, source hashes and stable anchors.
- [x] Update architecture review/task/guideline links, PRD/design/manifests and the exact UNAPPROVED commit inventory; no file under either evidence tree may be included.
- [x] Fresh serial checker verifies policy, zero indexed evidence, original bytes/copy identities, source/test/runner hashes, Chinese scope, evidence-free checkout links, inventory and authored whitespace. No expensive unchanged-source rerun.

History: initial index/HEAD contained zero evidence. External staging later appeared; the authorized cleanup removed exactly68 newly added retained evidence paths from index, preserving every local file and all other index entries. Current HEAD and index have zero evidence paths. The original699 raw files and68 compact artifacts remain local; old735-file and122-file inventories were proposed, never approved, and are superseded. The compact packaging report is historical, not the final scope. Actual final counts and checks are recorded in the local-only recovery handoff. No add/reset/clean/stash/commit/push/archive, runtime package/backend change or new simulation/BMC was performed.

Rollback preserves all local artifacts and current unrelated index state. No further index mutation is needed unless fresh inspection finds added evidence. Parent owns independent acceptance and lifecycle; full-composition depth10 and actual I1–I4 runtime validation remain open.

父会话已完整读取恢复 writer 与独立 checker 报告，接受本次全部证据仅本地、指定读者文档中文的包装门禁。独立检查26项通过，修正报告哈希可用范围与5处残余英文；不含证据的投影30份文档/210个链接通过。父会话另行确认当前128个可提交文件与独立检查投影逐字一致，767个证据文件/7,686,426字节全部被忽略，HEAD/index证据均为零，54文件提交清单准确排除15项无关改动。后端中文与本地证据规范已持久记录，无需重复增加相同规范；仅更新任务验收归属，不新增模型执行、Git修改或运行时验收。提交仍待用户批准，任务保持in_progress。

## 7. Finish

- [x] Update durable modeling guidelines with evidenced conventions, following `trellis-update-spec`.
- [x] Obtain user approval for the exact54-file Phase3.4 plan (27/27); user replied “行”. Execute the two approved work commits and verify their exact paths, local evidence and unrelated index/worktree preservation.
- [ ] Archive/record the session after remaining task closure conditions are satisfied. Do not archive if an unresolved core architectural or verification blocker remains; this two-commit approval does not authorize unrelated journal/workspace changes.

One writer owns the tightly coupled core state/properties/tests/primary docs seam. The parent owns task scope and acceptance. Read-only compiler research is complete and preserved through its managed artifact; independent review follows the writer. The initial core pass made no architecture/ADR/product edits. Section 5 authorizes the scoped proposed-contract refinement; section 6 separately authorizes the subsequent pending-design review and justified review-status updates. Runtime implementation and package installation remain excluded.

## Parent repair-gate acceptance and review handoff — 2026-10-08

Parent consumed the completed managed implementation and independent review from workflow `9a53b831-2252-4127-829d-08965de4747e`, inspected the primary report/current managed metadata/final validation and verified all three executable hashes against actual files. The repair gate has no known remaining scoped source/model/runner defect. Three independent findings are addressed: admitted unobserved work blocks terminal failure; original-instance redispatch permits one first entry; and all ten requested sampling witnesses are enforced.

Current model SHA256 is `7d98f1ff5ff4d31a2deb3d365d1b6bb6f4d5e3011d5af571e82eb5ade4044482`. Six typechecks,43 core tests (25 positive/18 detecting mutations), one recovery/rank test and24 executed composed transitions pass. Fresh default composition sampling:10,000 traces,depth60,seed20261014, no sampled counterexample; all ten noninitial witnesses positive. Current-source composition depth10 timed out after240.054s/port8863 while checking State5, exit124; no completed or lesser bound is established. Restricted recovery depth14 completed NoError/port8864 under its explicit schedule only. Final identities/index/cleanup matched; actual I1–I4 runtime validation remains unexecuted.

Parent applied trellis-update-spec to `.trellis/spec/backend/quint-verification.md`: capture admitted-work/retained-evidence result semantics, independent regression/mutation expectations, full witness-list enforcement and source-dependency/schedule limits. These guideline/task-only edits do not change the executed model dependencies or architecture source. Section5 synthesis is complete; section6 is authorized to proceed. This is repair-gate acceptance, not complete bounded safety, full architecture acceptance, commit or task closure. Earlier writer evidence below/above remains historical under its own hashes; current evidence is `spec/quint/core/evidence/design-repair/independent-review/`.

## Parent pending-design gate acceptance — 2026-10-08

Parent consumed all four managed artifacts from workflow `4f0f34e0-25a0-4970-aba1-43db48a54fe3`, read the final finding dispositions and actual source/evidence, independently matched all22 final-check source/test hashes and all7 reusable executable dependencies, and confirmed ADR-001–006 historical text against HEAD. P1/P2 and captured declaration schema correspondence are resolved. Accept the scoped pending-design quality gate and ADR-008 technical design; keep ADR-007 conditional and I1–I4 runtime adoption unexecuted.

Current evidence remains46 checks (28 positive/18 detecting mutations),10,000 default-composition traces atdepth60/seed20261014 with ten positive witnesses and no sampled counterexample, and the24-transition composed path. Full-composition depth10/240s/port8863 timeout124 atState5 remains inconclusive; no lesser bound follows. Restricted recovery depth14 NoError remains schedule-scoped. Monitor tests are guard/fact checks, not queued distinct-ID delivery or audit persistence. Finite domains and sparse consumption5/recovery1 remain explicit.

Applied trellis-update-spec for monotone same-Attempt evidence precedence, distinct-Attempt/local-failure distinctions, guard-versus-delivery validation boundaries, dependency identity and version-pinned source evidence. Parent changed only guideline/task/disposition attribution after the final gate; no executable semantics, test or historical evidence was changed. Commit planning is the next lifecycle step. Do not archive or claim completed bounded/runtime verification on this technical acceptance.

## Evidence status after independent review and longer BMC

Completed activity checkboxes refer to the revised core, not the superseded all-contract plan. Current-source four typechecks,26 tests and10,000 seeded composition samples are preserved in `spec/quint/core/evidence/review/final-v2/`; the independent review and scoped repairs are recorded in progress/report. Parent added the durable Quint guidelines via `trellis-update-spec`; consistency review corrected its Attempt knowledge-field example.

The nonzero-depth diagnostic remains hash-scoped historical evidence. Representative composition depth10 was actually attempted on the repaired source for240s and once more for900s, with all core actions/default init/step/safety and random-transitions false. The longer run ended with exit124 while checking State6; **the requested bound remains inconclusive**, despite the completed attempt/evidence-recording activities. Before/after source/dependency and staged-diff identity passed; all owned processes stopped. No model/properties/domain changes or unchanged-source test/sampling reruns occurred during the extension. Latest evidence: `spec/quint/core/evidence/bounded-900-port8854/`.

Completed depth10 safety is not checked off as established. No further retry was launched. Parent owns closure, commit and archive; no old all-contract omission was reintroduced as a core gate.

## Design-refinement execution evidence — 2026-10-08

Section5 implementation/validation activities completed. Seven proposed architecture supplements now define captured failure meaning, centralized retained-evidence reduction, existing permission roles, recovery responsibility, failed audit retention and I1–I4 module obligations. The supervisor approved qualifying only the contradictory proposed not_executed disposition: it discharges its own Attempt and reduces all retained validated observations; pending requires no admitted/unresolved work or sufficient terminal evidence. Original source/model hash and the13-transition evidence-selection gap remain preserved.

Final executable source: model SHA256 `7e076a320a8d8d52b9050bf7c20155a0939b2ed809c568505fd49741f5e676cb`; six typechecks,36 core tests (19 positive/17 detecting mutations), one14-transition recovery/rank test and the24-transition executed composition pass. Current default composition sampling:10,000 traces,depth60,seed argument20261014, no counterexample; all ten noninitial witnesses reached, consumption5/recovery-consumption1. One depth10 composition attempt,240s/port8861, timed out at State5 (exit124); no completed/partial bound is claimed. One restricted recovery depth14 check,120s/port8862, completed NoError (exit0), covering only its conditional schedule/safety/rank premises.

Evidence: `spec/quint/core/evidence/design-repair/validated/`, `current/`, `regression/`; primary README/report and final hash/correspondence checks describe source timing. After managed before/after identity passed, only the approved proposed-row qualification/attribution and heading links changed; executable dependencies remain identical. All owned processes stopped, both ports closed, index unchanged. Syntax, source documentation links and scoped whitespace pass. Full-composition bounded safety, actual I1–I4 runtime obligations and fresh independent review remain open. No extra backend retry, dependency install, staging or commit. Parent owns review/spec synthesis/closure.
