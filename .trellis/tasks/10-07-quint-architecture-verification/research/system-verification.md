# Whole-architecture verification strategy

Status: revised planning after the user's scope correction. This document complements the clause inventory; the composed system is the primary verification target.

## User clarification

The user explicitly requested verification of the overall architecture, not merely a collection of independent clause checks. The primary deliverable is one executable composition of gateway, application/host, authoritative history, controller/Scope, execution owners/providers, inbox, lifecycle and branch/import behavior. P01–P22 and R/S mappings remain a coverage audit and diagnostic index.

## Primary architecture model

Use a single `architecture.qnt` entry point whose `step` permits interleavings across all component transitions and environment faults. Source decomposition into modules is allowed, but every component participates in the same global state and executable transition system. Access, branches and execution cannot be checked only in isolated scenarios and then assumed compatible.

The observable path is:

```text
Authorized input -> committed inbox -> pure evaluation -> atomic state/intent commit
-> controller/Scope resolution -> Attempt grant -> owner-local entry
-> external observation -> authoritative outcome/reply -> FIFO business consumption
-> recorded stable boundary -> independent suspended branch -> new authorized work
```

Each arrow remains interleavable where the contracts expose it. Simultaneously enabled operations include takeover, suspend/resume, terminal fault, provider replacement, uncertain execution, explicit resolution, duplicate commands/delivery and branch selection from earlier history. Two Runs and two Effects are necessary in the expanded configuration to expose identity, ordering and source/branch interference.

The specification assumes the authority interface provides a single linearizable durable history. Model authority access failures and recovery, while identifying this interface assumption explicitly. This scope verifies architectural use of the storage contract; it does not prove that Ra or actual disks implement it. Provider compatibility, data validation and trusted registration receive the same explicit assumption accounting.

## Global property families

| ID | Architectural question | Global check |
| --- | --- | --- |
| G01 | Can a confirmed logical fact be lost or contradicted by another component? | Committed inputs, intentions, receipts, outcomes and selected history prefixes remain preserved through modeled crashes, control changes and recovery. Projections agree with the canonical committed ledger. |
| G02 | Can any path execute external work without legitimate authority? | Every actual modeled provider entry has a committed matching intent, original owner-bound grant and compatible binding. Replays, branch history, audit, controller replacement and stale proposals cannot create an alternative execution path. Existing grants are retained across control changes. |
| G03 | Can uncertainty be falsely converted into stronger knowledge? | Connection loss and later-attempt failure/precheck do not erase earlier unknown execution; terminal choices have validated observation or explicit settlement provenance. One authoritative result is projected consistently into history, Reply and consumption. |
| G04 | Does end-to-end application state correspond to the ordered authoritative inputs? | Business commits consume exactly the next valid input once, append their Effects/continuations atomically, and never apply an obsolete evaluated proposal. Output order and correlation remain valid under concurrent results and continued inputs. |
| G05 | Do lifecycle and execution protocols remain compatible? | Suspension/terminal state blocks new business work and grants while retaining valid admitted execution and evidence; failed late replies stay unprocessed; finished state cannot contain unresolved logical work. |
| G06 | Does branch/import preserve causality without inheriting live authority? | Captured prefix/state and branch projection agree; parent continues independently; fresh IDs, queues and permissions prohibit historical reexecution or source/branch cross-consumption. Compatibility/authorization failures prevent activation. |
| G07 | Are the documented architectural boundaries sufficient and consistent? | Dependency graph is acyclic, the generic foundation has no Agent dependency/operation-specific branch, and observable boundary payloads do not expose execution/storage internals. Stateful actions are assigned to their documented owner. These are checks on the modeled architecture, not on absent implementation imports. |
| G08 | Can the composed architecture make progress when its stated prerequisites hold? | Classify terminal/quiescent/environment-blocked states and identify unintended states with no legal next transition. Establish full-system recovery-to-consumption and branch-to-new-work paths. Conditional progress checks explicitly restrict fault/input generation and declare availability/scheduling assumptions; witnesses alone do not prove liveness. |

A property family contains several independently stated assertions. It must not be implemented as only a conjunction of local guards. Use retained facts, call ledgers, input dispositions, boundary projections and previous-state audit evidence to express the global obligations.

## Reference view and composition checks

Add a small reference module describing allowed externally observable ledger events: accepted input, committed business step/intent, execution authority, terminal logical outcome, consumed reply, control/terminal boundary and lineage. Define an abstraction/projection from detailed component state to this view.

For every detailed transition, require that its projection corresponds to an allowed reference event or an observable no-change event for internal evaluation/delivery/fault handling. This no-change relation is a proof observation, not a blanket stutter action in the executable model. Reference rules express external guarantees without copying provider/admission/queue guard implementations verbatim.

Check the relation in the composed model, including crashes and branch activation. This is bounded trace/refinement evidence for the abstract architecture; it does not automatically establish an unbounded refinement theorem or implementation correctness.

Maintain an assumption/guarantee table for component boundaries. Where one component's guarantee is used by another, verify the guarantee in the composition or identify it as an external assumption. The review must detect circular assumptions, such as authority assuming that all dispatched workers honor a grant while dispatch assumes any receipt is a new grant, or branch selection assuming current completion retroactively stabilizes a stored prefix.

## Exploration and acceptance evidence

1. Incrementally build the shared composition, then explore the full `step` with faults and operations from all components enabled together.
2. Check G01–G08 and the reference projection in the full-system configuration. Run targeted configurations only as additional evidence or to diagnose counterexamples. If the full composition cannot be checked at the proposed depth, report that limitation and investigate size reduction without deleting the cross-component interactions being checked.
3. Exercise multi-event traces such as: admit -> connectivity loss -> takeover -> unknown -> suspend -> provider replacement -> record repeat permission -> resume -> recovery Attempt -> old observation/settlement race -> ordered consumption -> earlier-boundary fork -> independent subsequent work.
4. Include source/branch and multi-Effect interference, rather than only single-call happy paths.
5. Inject deliberate cross-boundary defects in isolated negative controls and show that global/reference properties detect them even when a weaker local property passes.
6. Report architectural conclusions under G01–G08: confirmed bounded behavior, discovered contradiction, unintended stall, unmet external assumption or resource-limited check. The R/S table explains coverage and diagnosis; completed row counts do not establish whole-system correctness.

## Corrected toolchain evidence

The installed Nix package is `/nix/store/zfx5n91x1m6grl1afzxrhx9a5fysm4w0-quint-0.32.0`.

- Its `bin/quint` wrapper sets `QUINT_HOME` to the package's `share/quint` and prepends bundled OpenJDK to the child-process PATH.
- The package contains `share/quint/apalache-dist-0.56.1/apalache/lib/apalache.jar` and the launcher, plus the Rust evaluator.
- Its closure includes `/nix/store/2cv1b5y6h029cvg07c944pq89fszwbya-openjdk-21.0.12.1+1`; direct `java -version` reports OpenJDK 21.0.12.1.
- The CLI uses the existing distribution if present, otherwise offers a download. It launches the backend process itself. This installation needs no extra Java/Apalache dependency.

An actual temporary toolchain probe was created outside the repository at `/tmp/beamlet-quint-toolchain.dq8mF9/smoke.qnt`. It initializes an integer counter at zero and increments it; the property is `counter <= 2`.

```bash
quint typecheck smoke.qnt
quint verify smoke.qnt --main smoke --invariant safe --max-steps 2 --backend apalache --verbosity 1
```

Both commands exited successfully. Verification output: `[ok] No violation found (4951ms).` Default `init` and `step` were used. This is backend-operability evidence only; no Beamlet model has been implemented or verified. The earlier shell-only dependency conclusion was incorrect and is superseded by this package inspection and executable probe.
