# Implementation and verification plan

Status: planning. Execute only after the user approves the latest scope and state sketch, manifests validate, and `task.py start` sets this task to `in_progress`.

## 1. Planning and activation gate

- [x] Read all architecture documents and current workflow/Quint modeling guidance.
- [x] Inspect existing models and toolchain; verify packaged Quint 0.32.0, Apalache 0.56.1 and OpenJDK 21 through the wrapper, then execute a successful two-step toolchain probe.
- [x] Persist source-linked requirement/scenario coverage and P01–P22 inventory.
- [x] Write converged PRD, technical design and ordered implementation plan.
- [x] Curate and validate `implement.jsonl` and `check.jsonl` with source contracts and both research documents (14 and 13 valid entries, respectively).
- [x] Present the initial planning summary; user clarified that overall architecture verification is required.
- [x] Revise the proposal around one composition, G01–G08, an independent reference view and bundled toolchain evidence.
- [x] Present the revised final summary including shared state/granularity, global properties, bounds and explicit authority assumptions.
- [x] Receive explicit approval of that latest summary and state sketch (user: 批准).
- [x] Run `python3 .trellis/scripts/task.py start .trellis/tasks/10-07-quint-architecture-verification`.

### Implementation ownership

The writer boundary is one tightly coupled formal composition: shared architecture state, reference projection, transitions, scenarios and their evidence under `spec/quint/`. Splitting component writers would overlap the state/identity/inbox/revision contracts and produce artificial handoffs. One `trellis-implement` writer owns this seam, followed serially by a fresh `trellis-check` agent. The parent handles synthesis, acceptance and task lifecycle; no concurrent writer shares this checkout. Child reports use managed output artifacts. No product runtime or architecture behavior change is authorized.

## 2. Toolchain and minimal executable model

- [ ] Load execution-phase guidance and relevant `trellis-before-dev`/Quint syntax, patterns and test references.
- [x] Verify the bundled backend through package inspection and a temporary two-step smoke check outside the repository. No extra Java/Apalache dependency is required.
- [ ] Add `spec/quint/architecture.qnt` with one shared state and a composed `step`; introduce component functions incrementally without disconnected state-machine instances.
- [ ] Add `reference.qnt` with independent observable ledger/control/lineage rules and the abstraction relation.
- [ ] Typecheck declarations before implementing logic. Build one Run/Effect and one real guarded action/witness first.
- [ ] Separate `pure def canX` from `pure def applyX`; actions contain guards/assignments. Bind every constant in concrete analysis modules.
- [ ] Immediately run the first concrete model after initialization/action wiring; do not accumulate unexecuted transitions.
- [ ] Add G01–G08 assertions/reference checks as their shared component state becomes executable. Maintain a boundary assumption/guarantee table and modeled structural responsibility/dependency checks.
- [ ] Keep the expanded full-system configuration as the acceptance target throughout development; local tests provide diagnosis and cannot replace this target.

## 3. Authority and execution contracts

- [ ] Implement stable-key receipt lookup, payload conflicts and admission authorization with separate state/history/execution revisions.
- [ ] Implement host takeover and held proposals, admission, local precheck and provider entry, completion, observation recording and owner loss/connectivity loss.
- [ ] Implement unknown episodes, notifications, preserved earlier uncertainty, captured recovery declaration, deduplication domain/expiry and immutable token/intent.
- [ ] Implement evidence/settle/allow_repeat, one-use consumption and competing controllers/resolution.
- [ ] Add independently evaluated properties P01–P11, P19–P21 and witnesses incrementally.
- [ ] Add deterministic S3/S4/S9/S11/S12/S14 race and refusal tests. Each mandatory matrix row gets its own stable test identifier or explicit runtime-only entry.
- [ ] Typecheck/test/simulate after each cohesive addition; expand to two Effects and multiple owner/proposal identities only after the one-Effect path works.

## 4. Inbox, control and terminal contracts

- [ ] Implement authority FIFO append, separate input/observation/command deduplication, continuous cursor and continuation-at-tail.
- [ ] Separate evaluate from commit so unknown notification obsolescence can invalidate both step and failure proposals.
- [ ] Implement stale continuation/obsolete notification disposition without state revision or business execution.
- [ ] Implement Suspend/Resume, finish with last reply, invalid finish without partial commit, conditional FailRun and late-result/unprocessed disposition.
- [ ] Add P12–P15 and deterministic S2/S5/S19 tests, including both commit orders of suspend/admission, finish/input and takeover/FailRun.
- [ ] Check that already admitted work can start and record after control changes, while new work is fenced.
- [ ] Enable execution, queued-input handling, control, faults and result/settlement transitions together; check global properties/reference consistency on the common composed `step`.

## 5. Branch, activation and access contracts

- [ ] Capture stable eligibility at boundary commit, not recomputed from current Effects; retain earlier stable boundaries during later work/failure.
- [ ] Implement fork/import, selected prefix, fresh branch identity/queue/cursor and read-only inherited history.
- [ ] Exercise ready/waiting/finished imports, explicit open resume and rejected terminal resume; no inherited Attempt or repeat permission.
- [ ] Implement abstract schema/code/resource/data/access validation categories. Explain that these do not execute ETF or authentication mechanisms.
- [ ] Add P16–P18/P22 and formal portions of S1/S6/S10/S13/S15/S16/S17/S18. S1/S6 include two domain-opaque application examples rather than Agent-specific foundation logic.
- [ ] Keep gateway authentication/authorization before duplicate-key receipt queries; test distinct operation permissions and unavailable write paths.
- [ ] Include full-system tests/exploration spanning authorization -> input -> intent -> admission -> disconnect/takeover -> unknown -> suspend -> provider/controller change -> explicit recovery -> late outcome -> FIFO consumption -> earlier-prefix branch -> subsequent work.
- [ ] Include multi-Effect and parent/branch interference with all relevant actions enabled, not only scripted single-component paths.
- [ ] Inspect G08 states for legitimate terminal/quiescent/environment-blocked outcomes versus unintended stalls. Check conditional completion with explicit finite-fault/input, restored-availability and scheduling assumptions; do not infer liveness from witnesses.

## 6. Verification strength and reproducibility

- [ ] Add separate negative-control tests detecting cross-boundary defects through global/reference properties: owner inheritance, duplicate terminal replies, stale proposals and reuse of one-use permission.
- [ ] Typecheck all models/test modules and run all deterministic scenarios.
- [ ] Run the full-composition configuration with G01–G08/reference checks, fixed seeds, at least 10,000 samples and depth 40–100. Supplement with focused configurations. Record witnesses, global outcomes, stalls and early termination.
- [ ] Execute full-composition bounded checks initially to depth 10, supplemented by focused depth 20 checks where feasible. Record actual backend/configuration/property/depth/result/duration for each.
- [ ] If composed checks fail to finish, diagnose state-space size without dropping the interactions under evaluation. Focused results remain supplementary; the uncompleted composition check stays inconclusive.
- [ ] Reduce any counterexample to a deterministic regression and map it to an owning clause. Preserve trace/seed and distinguish model defect from contract defect.
- [ ] Audit the completed suite against Quint C-init, C-step, C-step-complete and invariant/action checks. No vacuous initialization witnesses or blanket stutter fallback.

## Command shapes

Concrete module/property names below are proposed; update this section and the maintained README to exactly match implemented files. Commands are not execution evidence until recorded with results.

```bash
quint --version
quint typecheck spec/quint/architecture.qnt
quint typecheck spec/quint/architecture_test.qnt
quint test spec/quint/architecture_test.qnt --main architecture_test --seed 20261007
quint run spec/quint/architecture.qnt --main architectureAnalysis --invariant architectureSafety --witnesses recoveryConsumedWitness branchNewWorkWitness --max-samples 10000 --max-steps 100 --seed 20261007 --verbosity 1
quint verify spec/quint/architecture.qnt --main architectureAnalysis --invariant architectureSafety --max-steps 10 --backend apalache --verbosity 1
quint verify spec/quint/architecture.qnt --main architectureRaceAnalysis --invariant architectureSafety --max-steps 20 --backend apalache --verbosity 1
```

Quint's Nix wrapper supplies Java and Apalache automatically; `java -version` in the parent shell is not a prerequisite. `architectureSafety` includes independently stated global/reference properties, with actual names recorded after implementation. Conditional progress checks name their environment restrictions and property/configuration separately.

Equivalent typecheck/test/simulation commands cover branches/access/negative controls. Prefer a `check.sh` entry point that checks exit codes and enumerates every maintained model/test. Backend failure and witness gaps must be visible. Commands using custom init/step must be documented with those exact values.

Long backend runs should use progress-aware/background execution so the user receives updates; avoid blocking waits longer than 60 seconds. Do not set random-transitions for a run labeled bounded verification.

## 7. Coverage, report and independent review

- [ ] Finalize `spec/quint/coverage.md`: requirement/scenario/matrix-row IDs, source anchors, model/property/test IDs, evidence link and covered/partial/runtime-only/blocked status.
- [ ] Finalize `verification-report.md` around G01–G08: architectural consistency, cross-boundary authority/causality, reference projection, progress/stalls, exact bounds/results and external assumptions. Present coverage counts as supporting evidence.
- [ ] Link suite from `spec/README.md`, retaining current architecture and ADR status.
- [ ] Have the required independent check agent inspect fidelity, non-vacuity, race granularity, result wording and cross-model consistency, with the active-task prefix and curated context.
- [ ] Resolve model/test/documentation defects and repeat only affected checks; architectural behavior changes await the owner's decision.
- [ ] Validate documentation references and `git diff --check`. Record quality results without claiming implementation/platform verification.

## 8. Finish and rollback points

- [ ] Load phase finish/spec-update guidance; capture modeling conventions and limitations supported by actual work rather than filling template guidance speculatively.
- [ ] Follow repository commit/wrap-up guidance after full-scope checks. Archive only when acceptance is satisfied; unresolved backend or architectural blockers keep the task open with recorded progress.

Rollback boundaries are the additive `spec/quint/` suite and its index link. The bundled toolchain needs no dependency change. Preserve original architecture semantics and unrelated changes. Counterexample artifacts survive semantic triage; never weaken an invariant just to pass a check.
