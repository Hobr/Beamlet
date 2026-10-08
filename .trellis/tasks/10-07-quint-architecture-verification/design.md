# Core architecture verification design

Status: revised under the user's explicit core-abstraction steering. Prior detailed plans are preserved under `research/pre-core/`; they are not current implementation gates.

## Modeling principle

Ask a few architectural questions and retain only the distinctions needed to falsify their answers. A model is an abstraction with a stated correspondence, not a partial reimplementation of the target runtime. Do not optimize the detailed model by erasing checks and call it equivalent. Build an intentionally smaller core model with explicit scope.

The core has four conceptual boundaries:

1. **Authority:** one linearizable durable history atomically commits application intent, grants and final result/delivery. Atomicity/durability are premises; permission usage and preservation are questions.
2. **Execution:** an immutable Effect may have successive owner-bound Attempts. The original owner has a monotone local entry marker. Unknown describes authority knowledge, not physical nonexecution.
3. **Computation/control:** evaluation yields a held proposal, a conditional commit consumes the next input once, and suspension/takeover fences new work. Already admitted work remains valid after control changes.
4. **Branch:** a recorded stable prefix is a value; a branch gets independent active-work identity and starts suspended. Historical work and grants do not become executable branch work.

## Retained state sketch

Prefer several small variables or small records over one deeply nested product-shaped State record.

- Run control: existence, active/suspended, open/terminal, monotone epoch and application revision, minimal authoritative FIFO/cursor.
- Effect: Run identity, immutable intent/token (opaque atoms), phase and terminal result, captured retry/failure-applicability declaration, one-use repeat permission.
- Attempt: identity, original owner incarnation, grant, local entered marker/count, locally completed result and authority-known evidence. Preserve earlier unknown separately from later Attempt failure.
- Proposal: evaluated epoch/revision/head and minimal proposed transition, separately held before commit.
- Boundary/branch: selected recorded stable prefix, source state/result value, fresh branch control/input identity and independent new work.
- Minimal prior-state or event evidence for independent assertions. Do not duplicate full state/history for audits, record stamped validity booleans as proofs, or add a second copy of all guards as a reference model.

No command ID maps, DTOs, role sets, ETF flags, whole provider configuration objects or arbitrary application state are needed in the primary core. Binding compatibility/access/portable data are assumed by the interface. Keep an owner identity and, only if needed by a core counterexample, a generation/recovery protection abstraction. Validated interface assumptions must be named, not silently treated as verified.

Begin with one Run, one logical Effect, two owner incarnations and two Attempts. Add the smallest configuration that exposes independent Effects or source/branch work. Do not reuse IDs or wrap counters to satisfy bounds. A small finite supply may explicitly exhaust; distinguish that from a design stall. Plain Quint over a shared logical authority is appropriate; consensus/network implementation is not modeled.

## Critical transition grain

`evaluate -> commitIntent -> admit -> enter -> complete -> record -> consume` has real guarded transitions. Allow suspend/takeover, disconnect/unknown, recovery permission, settlement and competing late evidence between the relevant transitions. An unknown owner may still finish; no clock or disconnect establishes nonexecution.

- Admission atomically consumes any one-use recovery permission and binds a distinct owner when the recovery contract requires it.
- Duplicate dispatch is a named guarded event that does not re-enter. There is no unconditional stutter fallback.
- Final result and one reply become authoritative together; consuming uncertainty is distinct from consuming the terminal result.
- A failure observation only establishes logical failure under a captured applicable declaration and when earlier uncertainty permits it.
- FIFO has only the few inputs needed to show order/obsolescence; it does not require all production envelope fields.
- Stability is recorded at the boundary event and cannot appear retrospectively. Earlier stable prefixes remain selectable during later source work.

## Model organization

Use a primary `spec/quint/core/` entry. The execution/control core can share state and compose in a common `step`; lineage may be a small compatible projection/configuration. Preserve a representative composed interleaving across the boundaries. Focused scenarios diagnose the core properties, not disconnected proofs of all architecture clauses.

Keep the conceptual model, tests and concrete analysis entries separate. Each backend entry imports only its one necessary instance. Compiler research established that Quint 0.32.0 retains metadata for unrelated instances in the same parsed input, inflating serialized structural types beyond Node's string limit. Splitting instance entry files is a supported layout choice. Do not modify Nix packages or introduce a custom compiler as part of this task.

Reuse trustworthy existing pure core logic/regressions if this simplifies the result; do not inherit the entire detailed State/dispatcher/audit system. Keep the large exploratory suite as supplemental evidence with clear scope until a deliberate evidence curation pass; preserve counterexamples and concrete model defects. Primary docs/runner should present the core first and avoid listing every historical log.

## Authorized refinement: one cohesive protocol seam

The new user instruction authorizes clarifying the proposed protocol supplement and checking its executable correspondence. The smallest behavior gap is that broad prose and abstract booleans leave failure applicability, recovery ownership and terminal audit policy too implicit for an implementer. Work lives in the authority/evidence/control protocol, with source correspondence in the computation, capability and lifecycle contracts.

Expected paths: `spec/architecture/authority-and-recovery.md` (result/permission/recovery tables), `capability-composition.md` (captured versioned declaration and provider obligations), `lifecycle-and-archives.md` and `computation-and-effects.md` (failed retained work and conditional progression), `boundaries.md` (responsibility/assumption handoff), `decisions.md`/`index.md` only to attribute the still-proposed clarification, and `spec/quint/core/` model/tests/entries/runner/report as needed. One writer owns this tightly coupled protocol seam; independent review follows serially.

Keep unresolved evidence derived from actual observations and captured operation meaning, independently of the Attempt knowledge tag. Centralize normal result reduction but keep properties independent. A conclusive-failure declaration is an operation-contract assertion with truthful-observation validation, not runtime inference from timeout or a generic provider error. Declare its capture/version correspondence; model only semantic distinctions needed to expose an error.

Distinguish permission roles without introducing unnecessary counters or a permission framework. Assign each recovery action to a module using committed facts, with stable identities and receipt/observation replay. Specify conditions for restored-interface scheduling and reasons for legitimate waiting. Prefer a small executable recovery projection/conditional schedule and useful rank or bounded checks, explicitly scoped; retain the open fault-enabled composition for interaction evidence.

Failed Run semantics remain sealed for new work, but its evidence is retained. An inconclusive failure or permanently unknown Attempt is still unresolved audit information. Late original observations may record one terminal result with an unprocessed reply; neither notification consumption nor terminal input disposition marks the Effect consumed. Settle/allow-repeat continue to require an open Run. Do not add cancellation, garbage-collection loss of evidence, automatic resume or terminal manual settlement.

I1–I4 receive named implementation owners and concrete fault/contract test obligations. There is no runtime application in this repository, so this pass verifies formal protocol use and documents the runtime seam obligations rather than implementing a new runtime or asserting the premises were tested.

A compact symbolic representation or property factoring may be justified by measurement, but preserve all C1–C6 semantics, transition grain, source/branch interaction and detecting mutations. Any focused projection or restricted schedule needs explicit correspondence and scope. Do not erase independent assertions or guards to obtain a solver pass. Use official bundled tools only; preserve older evidence under its hashes and attempt current-source composition depth 10 under a finite budget, reporting timeout as inconclusive.

## Post-repair review boundary

After the repair writer and fresh independent repair checker finish, perform a separate fresh-context technical review of all pending architectural proposals. Start from the architecture index/status inventory, then read the owning contracts and decisions completely. Include ADR-008's original protocol supplement as well as the newest refinements; assess ADR-007 as a conditional implementation candidate, with its unexecuted runtime obligations explicit. Platform, codec and resource assertions receive review of their contract/validation boundary, not an unsolicited runtime implementation.

The reviewer is read-only and produces a source-linked decision/findings inventory with severity, consequence, remedy and verification needs. A subsequent sole writer resolves accepted findings, adjusts related contracts/statuses consistently, and adds only minimal formal regressions when semantics change. A fresh final checker assesses the revised text and affected evidence. No concurrent writers share the protocol/model seam.

Record separate columns for technical design disposition, executed model/source checks and remaining runtime evidence. Status changes follow actual review conclusions and reference a durable review record; preserve the architecture-v1 historical baseline and older counterexamples. Explicit user authorization for reviewing pending content overrides repair-stage status preservation for the reviewed subset. It does not authorize inventing evidence, installing packages or declaring Ra/toolchain/ETF/provider guarantees implemented.

Use existing current-source evidence whenever dependencies are unchanged. Semantic model changes require fresh dependent tests and representative sampling, plus one attributable depth-10 attempt under a finite 240-second budget; allow at most two useful focused 120-second checks for new issues. Report incomplete bounds accurately. Read-only primary-source checks may support conditional external API/version claims; record exact source/version rather than treating documentation as executed runtime evidence.

## Properties and evidence

Define a small set of named properties answering C1–C6 in the PRD. Prefer checking actual pre-state authority/control/grants rather than guard-generated “valid” flags. Selected mutations must show that entry without a grant, stale commit, repeated repeat-permission use, double terminal delivery and inherited branch permission are detectable.

The representative composition's safety is checked with all retained core actions enabled. A deterministic full path and source/branch interference show reachability. The normal step allows environmental faults and therefore does not imply eventual success. If a conditional completion claim is useful, state restored availability/no-new-fault/scheduling assumptions and actual rank/bounded evidence; a witness alone is not temporal progress.

Run typecheck and a minimal real transition immediately, then add cohesive pieces incrementally. Typecheck/tests are not verification results. Final evidence consists of source-bound deterministic traces, >=10,000 seeded sampled traces at a meaningful depth, and attempted/completed depth-10 representative composition BMC. Report limits accurately. Core success does not retroactively resolve all detailed-suite gaps or establish Ra/ETF/security/platform behavior.

## Latest packaging and language authority

All execution evidence is local-only, including the existing compact retained pack. Ignore both complete evidence trees with rooted rules, no whitelist; preserve local captured bytes and correct model/probe pairing. Only models/tests/scripts and authored reports outside evidence are deliverable. Chinese reader/backend reports retain exact source identities, results, commands, limits and stable anchors; required links resolve without evidence. Original raw paths are code text explicitly labeled local-only/Git-ignored. Index-only cleanup is scoped to freshly inspected evidence paths; no unrelated index reset/staging. The735/122-file proposals are superseded and unapproved. No executable/runtime/dependency change or unchanged-source sampling/BMC repeat is part of this packaging refinement.
