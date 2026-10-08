# Systematic Quint verification of architecture contracts

## Goal

Use Quint to verify the overall architecture in `spec/architecture/` as one composed transition system. Evaluate global consistency, end-to-end safety, recovery/progress and cross-component interactions against an independent observable reference view. Preserve requirement/scenario traceability as an omission check and diagnostic aid; a collection of passing isolated clause tests is not the target outcome.

## Background

- The architecture index defines 18 requirements (R1–R6, R8–R19) and 17 scenarios (S1–S6, S9–S19). Baseline contracts and the proposed ADR-008 supplement both belong to the verification target; their review statuses remain distinct.
- The repository has Quint 0.32.0 through `flake.nix`, but no existing architecture `.qnt` model. Package inspection confirmed that the Nix Quint wrapper already supplies OpenJDK 21 and Apalache 0.56.1; an actual two-step `quint verify` smoke probe passed. No additional backend installation is required.
- Current contracts describe a trusted cluster, a single initial authority group, explicit state progression, immutable intentions, declared recovery and stable-boundary branches. Ra, ETF resource behavior and platform support still require implementation evidence.
- Source anchors, a requirement/scenario inventory and P01–P22 are recorded in `research/architecture-intake.md`. The user's clarification, global G01–G08 property families, composition/reference strategy and corrected toolchain evidence are recorded in `research/system-verification.md`.
- Task creation and planning were authorized. Implementation awaits approval of the final scope and state sketch in `design.md`.

## Requirements

### QV0. Overall architecture and composition

Provide one executable architecture model spanning gateway, computation, authority, controller/Scope, execution/provider, input delivery, lifecycle and branch/import. Allow their concurrent transitions and faults to interleave in a common `step`. Evaluate G01–G08 across the full composition and an independent reference projection, including unintended stalls and explicitly conditional progress. Focused models and clause tests support this goal and cannot replace its integration evidence.

### QV1. Traceable coverage

Inventory every requirement and mandatory scenario, including every assertion row in scenario matrices. Map each formal obligation to a model/property/test, and every non-formal obligation to its required runtime evidence. Do not mark a partially modeled scenario as fully verified. Preserve the architecture's stable R/S identifiers.

### QV2. Runtime and execution safety

Evaluate P01–P11, P19–P21 from the intake: atomic state/input/Effect commits, independent revision fencing, receipt recovery and conflicts, precise owner/binding authorization, duplicate dispatch suppression, immutable intent/tokens, recovery eligibility, earlier uncertainty, unique terminal outcomes, settlement races, one-use permission and control fencing. Include both successful paths and rejected or raced commands.

### QV3. Input and terminal behavior

Evaluate P12–P15: FIFO disposition and continuous cursor, stale continuations and unknown proposals, notification versus terminal consumption, finish preconditions, FailRun atomicity, and late-result retention after suspension/failure. A rejected stale proposal must not be reclassified as a definition fault.

### QV4. Branch, import and boundary behavior

Evaluate P16–P18: commit-time stable eligibility, earlier-prefix branches, isolated future identities/queues/permissions, suspended import, ready/waiting/finished behavior, and compatibility/data/resource/access rejection before activation. Keep inherited history read-only and do not activate source Attempts or repeat permissions.

### QV5. Access and deployment contracts

Evaluate the abstract parts of P03, P19 and P22: operation-specific authentication/authorization before receipt lookup, no false durable acknowledgements without authoritative writes, independent roles, and UI/Run lifecycle separation. Distinguish these model properties from actual consensus, credentials, platform packaging or security enforcement.

### QV6. Reachability and evidence quality

Require a reachable witness for every major action and deterministic tests for mandatory races and refusals. Use independent transition/audit evidence where needed so invariants are not merely the same guards restated. Include targeted negative controls demonstrating that selected core properties detect a deliberately weakened transition.

### QV7. Verification and reporting

Provide typechecks, scenario tests, reproducible sampling and bounded model checking of the composed architecture/global properties, supplemented by focused critical-race checks. Record tool/backend versions, domains, depth, seeds, sample counts, witnesses and outcomes. Preserve any counterexample with source mapping and classify abstraction defects, architectural defects and tool limitations separately. Unsuccessful or unavailable checks must remain explicitly blocked/inconclusive.

### QV8. Preserve contract ownership

The existing architecture contracts are the behavioral source. Do not silently change a guarantee, mark ADR-008 reviewed, or weaken a property to eliminate a counterexample. Document the inconsistency and obtain the owner's decision before changing architecture semantics. Linking the suite from the specification index is within scope.

## Acceptance Criteria

- AC0 (QV0): One shared architecture `step` composes all modeled components and faults. G01–G08 and the reference relation are exercised across multiple Effects and source/branch Runs. The report presents system-level conclusions and assumptions; isolated scenario pass counts are insufficient.
- AC1 (QV1): All 18 indexed requirements and 17 scenarios have explicit coverage entries. Every matrix row has a named formal assertion/scenario or a stated runtime-only reason.
- AC2 (QV2–QV5): Executable models cover P01–P22 at the stated abstraction, including both orderings of each mandatory race and negative-path behavior. Omitted or simplified clauses have explicit limitations.
- AC3 (QV6): All major step actions have witnesses reached after initialization, and all mandatory deterministic scenarios pass. Zero sampled witnesses are investigated and resolved or reported as a coverage gap.
- AC4 (QV6): Selected negative controls for owner inheritance, duplicate terminal replies, stale authority proposals and one-use permission are detected by independently specified properties/tests.
- AC5 (QV7): All model and test files typecheck, deterministic tests pass, and final sampling uses at least 10,000 traces per documented configuration with fixed seeds and meaningful depths. Reports include actual counts and early-stop/terminal interpretation.
- AC6 (QV0, QV7): Composed-system bounded checks run against the bundled operational backend, initially at 10 transitions, supplemented by deeper focused checks when feasible. Every run records its domain/depth. Timeout, unsupported translation or backend failure prevents a successful bounded-verification claim for that obligation. Focused checks cannot be reported as successful full-composition checking.
- AC7 (QV7, QV8): Counterexamples are reproducible and tied to source clauses; unresolved architectural findings remain visible rather than being erased by a changed assumption.
- AC8 (QV1, QV7): `spec/quint/` contains models, tests, coverage, reproducible verification instructions and a report separating observed sampling results, completed bounded checks, and remaining runtime validation.
- AC9 (QV8): Architecture review status and product runtime are preserved; the final review includes documented abstraction assumptions and deferred claims.
- AC10 (QV0, QV6, QV7): Full-system completion/recovery and branch-to-new-work paths are reached; unexplained stalls are investigated. Any conditional progress claim states fault, availability and scheduling assumptions and its actual bounded/temporal evidence. Witnesses alone never establish inevitable progress.

## Out of Scope

- Implementing Beamlet runtime, Agent, Cordex, Ra integration, providers or frontends.
- Proving Ra/consensus, replica durability, disk loss tolerance or real network behavior through an assumed atomic authority.
- Implementing/testing ETF encoding, atom safety, decoder resource budgets or platform packaging.
- Byzantine nodes, malicious-code isolation, cancellation/Saga compensation, in-flight cloning or exactly-once external execution.
- Unbounded proof or an unconditional eventual-completion promise. Whole-system reachability, stall analysis and conditional progress with explicitly stated environment/scheduling assumptions are in scope.

## Artifact Status

`design.md` specifies the shared architecture, state sketch, reference projection and granularity. `implement.md` specifies composition-first execution and checks. The two research documents provide source coverage, global properties and toolchain evidence. Refreshed context manifests passed validation (14 implementation and 13 check entries). Implementation awaits approval of this revised whole-architecture proposal.
