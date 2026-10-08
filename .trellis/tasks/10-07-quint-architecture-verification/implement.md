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

## 6.2. Elixir / Mix 验证执行器迁移

- [x] 读取当前shell/有界包装器、README、flake与后端规范；确认尚无Mix项目，记录用户已授权的工具迁移范围。先前README-only流程已完成，后续迁移覆盖其命令。
- [x] 唯一writer添加最小无外部依赖Mix入口与一个Elixir执行脚本，迁移核心/补充模式并删除两个check.sh；保持模型、包装器与历史证据。
- [x] 同步当前README/说明/规范与复现入口，区分旧执行器身份和新运行，保留本地证据策略。
- [x] 运行格式/编译、实际核心quick及执行器失败/witness/源变化/超时集成回归；所有新增日志仅/tmp或被忽略目录，假工具结果不是模型证据，不执行昂贵抽样/BMC。
- [x] fresh checker独立检查等价编排、argv/退出/日志/哈希/witness、进程清理、文档与实际测试；父会话综合并按trellis-update-spec保留必要经验。

writer迁移结果：`mix.exs` 薄别名调用唯一 `spec/quint/check.exs`，默认核心/显式supplemental，保留两个套件模式/参数与原Python包装器。最终10项ExUnit集成测试通过（十项witness的20个缺失/零值聚合注入、实际包装器假后端超时清理、不伤无关进程、CLI与argv/日志/哈希），真实核心quick六typecheck/恢复/combined/46测试及hash-validation均exit0。局部执行 `ERL_FLAGS='+S 4:4'`；最终本地证据 `/tmp/beamlet-quint-core-1791428971703335364-2`、`/tmp/beamlet-mix-tests-final.log`。模型/包装器/历史证据不变；无真实抽样/BMC，假工具只是编排证据。新的身份/限制见核心报告 `mix-runner-migration`。fresh checker与最终归属由父会话完成。

fresh checker独立结果：修复核心bounded仍向仓库根写入新`_apalache-out/`的工作目录问题，改用日志目录`depth10.work/`，保留原argv/verify.py并更新timeout产物隔离回归；恢复旧行为的/tmp负控确实失败。独立format/compile/10项集成测试通过（15.2秒、seed33788），真实核心quick再次全部通过，证据`/tmp/beamlet-quint-core-1791429487145356460-4`。两套四模式的8组旧shell/new Mix实际Quint argv逐项一致（假工具），直接脚本在特殊路径/无关cwd运行通过；16模型/包装器、767历史evidence与完整index不变，53文档链接/锚点无需ignored evidence。范围内无剩余阻塞；无真实sampling/BMC、无暂存/提交。报告中新runner身份归属本次修复，旧运行身份保留；最后6.2复合验收checkbox仍留给父会话。

父会话已完整读取恢复writer与fresh checker报告及实际quick/ExUnit日志，接受本轮工具迁移门禁。独立复查最终入口身份、16模型/包装器、767历史证据、完整index/HEAD与53文档链接通过；LSP主动检查仅见Mix动态加载模块的静态未定义警告，实际compile/CLI检查已通过。按trellis-update-spec补齐执行器接口、错误矩阵、工作目录隔离及回归义务，仅规范/任务文字变化，不改已执行依赖。恢复流程8db1e34d-2a86-4f15-b808-f05f4f8d059e的writer2289f816-5f90-41d1-957c-bff74620c5a9与checkerd3f7ed48-7d77-4747-9486-f62914a9d6c2均完成；原HTTP/2中断快照仅本地保留。

本轮提交未批准；不安装依赖、不改flake、不暂存/提交/推送/归档。原始两个shell可从既有提交读取以核对行为，历史捕获逐字保留，撤回时恢复原入口而不删除本地日志。

## 6.3. 执行器中文注释跟进

- [x] 按用户请求说明 Python 包装器/fixture、Mix 阶段与 hash，并仅为四份脚本新增必要中文注释；记录注释前后独立来源身份。
- [x] 唯一 writer 比较 Python AST/token 与递归去位置元数据的 Elixir AST，并完成语法/格式检查；无可执行变化、模型修改或新模型运行。
- [x] 恢复原 writer 的交接后，由 fresh checker 只读复核注释、历史归属和文件保留；父会话接受技术结论，并按 trellis-update-spec 保存注释专属检查及索引/工作树空白检查规则。

恢复流程 `8f3a1739-f477-4732-b157-50dd7c82e13f` 两个子运行完成；四脚本新增28行注释/2行空行，独立 AST/token/语法/五份 formatter 输入检查通过。15份模型、READMEs、767份历史证据保持原字节。原运行因启动后暂存区变化而遭自动验收拒绝，该结论保留；恢复和 fresh check 的18项既有暂存相对各自启动状态保持，不代表暂存区为空。checker 指出恢复报告关于 progress 空白及 acceptance 字段作用域的表述不准确，父会话采用独立检查结论，不重写原报告。父会话修正工作树 progress EOF 并追加验收，保留既有索引。只新增规范/任务文字，无需重复已检查的源码等同性或昂贵模型检查；新提交仍未批准。

## 6.4. 移除源摘要机制与清理公开规范

- [x] 唯一 writer 完整读取公开文档，移除验证执行器/测试/注释与现行说明中的源摘要机制；不改模型或核心验证参数。
- [x] 清理 `spec/` 中的代理过程与本机记录，整理为开发者技术说明；保留契约、设计理由、实质修订与准确结果/限制，修复链接。
- [x] 执行 format、compile、执行器集成测试和真实核心 quick，检查公开内容与字节保留；不重跑抽样/BMC，不修改现有索引。
- [x] fresh checker 独立检查遗漏、技术含义、命令/测试、文档链接与保留；父会话接受综合结论，现行后端规范已同步。

父会话已完整读取实现与独立检查报告，接受6.4清理门禁。独立检查修正Mix/直接Elixir退出码区别与手动恢复检查的工作目录隔离；未改已测试执行器或模型。9项执行器回归、真实核心quick（六typecheck、恢复1、combined1、核心46项测试）通过；178本地链接、15模型、767历史捕获及完整现有索引保留经父会话复查。按trellis-update-spec确认中文开发者文档约定与执行器错误/日志契约已记录，无需重复追加公开过程叙述。完整组合depth10与I1–I4实现验证仍未完成，本轮没有真实抽样/BMC或新提交。

先前6.2/6.3源摘要要求属已被最新请求覆盖的历史。本轮字节基线 `/tmp/beamlet-spec-cleanup-before.json`，包含133项项目文件、767项本地证据及完整index；仅作为本地检查输入，不加入公开规范。用户明确要求“分批提交”，授权按执行器与测试、公开开发者文档、任务与后端规范三批提交当前29文件；不包含本地证据、推送或归档。

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
