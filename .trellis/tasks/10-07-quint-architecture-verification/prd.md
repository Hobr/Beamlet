# Verify the core architectural abstractions in Quint

## Goal and current authority

Use small executable Quint models to test the core abstractions and design in `spec/architecture/`. Preserve representative interactions between abstractions; do not reproduce every interface, record, platform and validation rule inside a single model.

This scope follows the user's explicit clarification: “我希望验证本身可以足够优雅, 重点是验证我们的核心抽象与设计, 而不是把一切都拿出来一次性验证”. It supersedes the earlier all-contract completion plan, preserved under `research/pre-core/`. The user previously authorized implementation; this is authorized steering of the same in-progress task, not a new task or a claim that the old exhaustive coverage criteria were met.

## Requirements

1. Make the architectural questions readable: which fact is authoritative, what permission authorizes an external call, what an unknown outcome means, how control changes interact with committed work, and what a stable branch inherits.
2. Model only state that distinguishes correct from incorrect answers to those questions. Treat atomic durable authority, validated/authenticated commands, registered compatible implementations and portable data as named interface assumptions. Verify architectural use of these interfaces; do not model their internals.
3. Retain the critical grain: evaluation versus commit; admission versus local call entry; external completion versus recording; terminal reply versus application consumption. Preserve late work, lost knowledge and repeated dispatch where they affect the questions.
4. Use focused configurations for diagnosis and a small representative composition for interaction evidence. A collection of unrelated clause tests is insufficient, while a product-shaped universal model is unnecessary.
5. State properties independently of transition guards and demonstrate their sensitivity with selected transition mutations. Preserve counterexamples and distinguish model defects, architecture contradictions and tooling failures.
6. Produce actual Quint typecheck, deterministic trace, sampled and bounded-check evidence. Record domains, init/step, property, depth, seed, sample count, source identity and result accurately.
7. Keep architecture baseline/ADR review statuses and product behavior unchanged. Deliberate abstraction is not a change to an architectural guarantee.

## Core questions and acceptance

| ID | Question | Required evidence |
| --- | --- | --- |
| C1 | Do committed intent/grants/results survive ownership and control changes? | Preservation properties and takeover/suspension interleavings |
| C2 | Can an external call happen only under a committed intent and matching owner-bound grant, at most once per Attempt/owner? | Entry/identity properties, repeated dispatch and replacement-owner negative control |
| C3 | Is uncertainty preserved across recovery, later failure and late results, with an explicit one-use repeat decision and one terminal result? | Unknown/recovery/settlement paths, duplicate-reply and permission-reuse mutations |
| C4 | Does application progression consume authoritative inputs once and commit state/effects atomically under current control? | Minimal FIFO/proposal/consumption model and stale-proposal mutation |
| C5 | Do suspension and terminal lifetime fence new work while retaining existing grants and late evidence? | Both suspension/admission orders, late entry/result, terminal control mutation |
| C6 | Does a stable branch copy a selected causal prefix but start with fresh identity, queue and permissions? | Commit-time stability, earlier-prefix branch, independent subsequent work and inherited-grant mutation |

Acceptance requires:

- A concise documented abstraction for C1–C6 and explicit assumptions/non-goals, with source clauses and a justified small state sketch.
- One representative composed execution path and open nondeterministic composition of the retained core actions. Focused checks use compatible abstractions and do not imply full-runtime coverage.
- Meaningful deterministic race/regression traces and selected negative controls. No tests that pass merely by acknowledging an unresolved bad behavior may be counted as repaired acceptance.
- At least 10,000 seeded sampled traces of the final representative core composition at a meaningful depth, with nonvacuous witnesses and transparent coverage gaps.
- Actual bounded checking of the representative core composition initially to depth 10; deeper focused checks where useful and feasible. Every check reports its actual abstraction and bound. Timeout/failure remains inconclusive; a small model's result is not proof of the former detailed suite.
- Independent review of abstraction fidelity, composition, nonvacuity, mutation detection and evidence. Reports distinguish reached paths from inevitable progress and bounded checks from unbounded proof.
- A clear primary entry point and small reproducible runner/report. Historical detailed exploration is marked supplemental/superseded and its defects/evidence remain traceable.

## Authorized design-refinement follow-up

The user asked how to improve the design after verification and then explicitly instructed: “请尝试修复并进行验证”. This authorizes implementing the discussed protocol refinements inside this active task. Earlier prohibitions on architecture edits are superseded for these scoped refinements; reviewed baseline and ADR statuses remain unchanged.

Required outcomes:

1. Make operation-wide versus Attempt-local failure meaning, captured declarations, unresolved evidence and terminal-result selection explicit and executable.
2. Consolidate the authority of current computation/control, orchestration, original Attempt grants, one-use repeat permission and read-only prefixes, without inventing new execution permissions.
3. Specify recovery responsibility from committed facts, availability/scheduling assumptions and legitimate waiting. Exercise representative recovery paths; do not claim general liveness from witnesses.
4. Explicitly preserve the existing failed-Run policy: no business restart or new Attempt, retained unknown and late evidence, unprocessed terminal replies, and no settle/allow-repeat on failed Runs. Long-term unknown is an inspectable audit fact; terminal manual settlement is deferred, not silently introduced.
5. Map I1–I4 to concrete module verification obligations. This repository currently has no runtime implementation; formal protocol checks must not be presented as actual storage/process/provider/codec verification.
6. Add independent regression and mutation evidence for the refinements, rerun source-bound representative sampling, and perform bounded checks with explicit budgets. Preserve the prior inconclusive depth-10 evidence. Focused checking may diagnose a question but does not replace whole-composition checking.

## Authorized post-repair review of pending design

The latest user instruction is: “在完成对现有设计和模型的修复后对未评审内容进行评审、完善、适当进行验证”. Preserve this order: complete the repair and its independent check, then review pending design content. This stage is authorized within the same active task.

Inventory the unreviewed protocol supplement (ADR-008 and associated clauses), proposed implementation decisions such as ADR-007, and their explicitly unvalidated interface/resource/compatibility assumptions. For each item, record its exact source, rationale, alternatives, failure semantics, findings/repairs, appropriate executed checks and residual implementation obligations. Use proportionate focused checks and representative composition; do not restore the superseded whole-contract modeling target.

A successful documented technical review may update the corresponding pending item's review status, with explicit evidence and limitations. This authorization supersedes the earlier blanket status-preservation constraint for those actually reviewed items only; the historical architecture-v1 baseline and existing accepted-decision history stay intact. Keep design acceptance, model evidence and runtime feasibility/validation separate. A conditional implementation candidate does not become verified or production-ready merely through prose review or Quint assumptions. Unresolved items remain qualified/deferred with their reason, rather than receiving blanket acceptance.

## Authorized evidence packaging follow-up

The latest user clarification requires ALL verification evidence to remain LOCAL ONLY, including compact packs, raw captures, metadata, logs, hash records, original model/probe/test snapshots and ITFs under either evidence tree. Preserve every existing local artifact; exclude the complete `spec/quint/evidence/` and `spec/quint/core/evidence/` directories from Git and proposed commits, with no retained exception. Evidence-only index removal is explicitly authorized when newly staged evidence is found; preserve worktree bytes and unrelated index entries. Deliver source-bound result/configuration/limit summaries and reproducible commands in authored reports/readmes outside evidence, with honest disclosure that a fresh checkout cannot inspect the excluded original logs. Translate the six specified reader/backend documents into Chinese; preserve identifiers, commands and captured source/log bytes. The backend index Chinese-default language policy is lasting. This supersedes the never-approved735-file full-raw and122-file compact-pack proposals, without model/test/runner semantics, technical acceptance, runtime/backend/dependency changes or expensive reruns. Subsequent user reply “行” approves the exact54-file,27/27 two-commit plan in research/commit-plan.json; all evidence and15 unrelated dirty paths remain excluded, with no push or archive. Mnesia/disk_log alternatives are explanatory only; Ra remains the conditional candidate.

## Authorized Elixir / Mix verification runner follow-up

用户明确请求：“能不能把.sh改为一个elixir脚本, 相关指令移入mix”。这是当前任务的验证工具迁移，包含此前要求的根README命令说明。仓库尚无mix.exs，因此允许添加无外部依赖、仅承载验证任务的最小Mix项目，将核心与历史补充的两个shell执行器合并为一个Elixir脚本，以Mix命令选择套件和模式。

验收要求：默认核心套件，提供mix quint.quick / quint.simulate / quint.verify / quint以及显式补充入口；保持原模式对应的命令、种子、抽样数量、界限、环境变量、日志/退出/耗时/源哈希与必需witness检查。保留现有Python有界包装器的专用进程组/超时清理；不修改模型、历史捕获、运行时架构、依赖或工具链。证据仍全部仅本地。更新当前命令说明和规范，旧结果和旧执行器哈希明确属于历史运行。

通过实际核心quick和针对执行器的集成回归验证Mix入口、失败退出、witness缺失/零值、源变化与本地证据记录；有界包装器可用隔离的假工具检查超时/清理。测试假的抽样/后端不能算模型验证。不得为此次迁移重跑昂贵抽样/BMC或安装包。此前两次提交批准已经执行完毕，不自动批准本轮新提交、推送或归档。

最新补充要求：“为什么还有python脚本……这些指令的作用都是什么，hash的意义又是什么，请给脚本内必要的地方增加注释”。本轮说明职责并补充中文注释，范围为Mix入口、Elixir执行器、Python有界包装器及假工具fixture；允许包装器的注释改变文件哈希，但不得改变其可执行逻辑。用去位置元数据的语法树比对确认语义未变，保留旧证据的原始哈希，不将新注释身份挂到旧运行。此要求没有要求删除Python或重新设计进程清理，不修改模型、README的用户更新、索引或历史捕获，不运行昂贵抽样/BMC。

## 最新授权：移除验证 Hash 与清理开发者规范

用户要求：“删除所有Hash相关内容。spec目录是给所有开发者读的，删除里面没有意义的Agent留下的内容”。这覆盖先前关于保留源 Hash 检查、表格与注释的要求。当前验证执行器、测试、README、公开 `spec/` 文档及后端现行规范不再生成、校验或要求源文件摘要；删除对应分支、输出与测试，不以另一套源指纹机制替代。

`spec/` 面向所有开发者：保留架构契约、术语、设计决策及理由、可执行模型、使用命令、验证问题、实际结果与限制；删除代理角色/流程 ID/用户指令复述/交接与父会话验收、暂存区事故、一次性迁移/注释验收日记、本机证据路径和重复过程叙述。清理链接与锚点，保持设计和模型语义不变。已忽略的原始历史捕获与依赖锁文件不属于开发者文档，本轮不改写或删除。领域中的 Agent 是产品概念，不因字面匹配而删除。

唯一 writer 先完成清理及相应 runner 测试调整，再由 fresh checker 复核开发者可读性、遗漏、链接和实际行为。运行格式、编译、执行器集成测试与真实核心 quick；不重复昂贵抽样/BMC，不安装依赖，不暂存/提交/推送/归档。保留当前索引与其他现有改动；任务内旧记录作为历史，当前要求优先。

## Deliberate non-goals

Complete command/receipt/key tables, every public API error precedence, DTO/ETF/decoder details, platform/role matrices, complete Scope hierarchy and resource plumbing, two full application Definitions, exhaustive scenario-row execution, actual Ra/storage/authentication/provider implementation, and an unbounded liveness theorem are outside this revised verification target. Command idempotency and data/access checks are interface assumptions here; the core still checks that re-delivery cannot create a second local provider entry or terminal reply.

The existing R/S/P inventory remains a traceability aid, with explicit core/supplemental/out-of-scope attribution. Do not label omitted formal interface behavior runtime-verified, and do not inflate model state to make every row executable.
