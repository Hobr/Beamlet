# Architecture verification intake

Status: planning evidence, not verification results. Sources are the current `spec/architecture/` contracts, including the unreviewed ADR-008 supplement. No `.qnt` model has been executed.

## Repository and toolchain evidence

- `spec/architecture/index.md` lists 18 requirements (R1–R6 and R8–R19) and 17 scenarios (S1–S6 and S9–S19). Missing numbers are intentional. R7 from the archived architecture task concerns maintained documentation rather than another runtime scenario.
- A hidden-file-aware repository search found no existing `.qnt` models outside installed skill references.
- `flake.nix` explicitly includes Quint, OTP 29 and Elixir 1.20. Inspection of the selected Nix Quint package confirmed bundled Apalache 0.56.1 and an OpenJDK 21 dependency injected into Quint's subprocess PATH.
- `quint --version` returns `0.32.0`. The shell cannot resolve `java`/`apalache-mc` directly, but the Quint wrapper can launch its packaged backend; shell command discovery is not a dependency-availability test here.
- A temporary counter-model `quint typecheck` and two-step `quint verify` succeeded; verification took 4951ms. No additional installation is needed. Exact wrapper/package/probe evidence is in `research/system-verification.md`.
- Backend guideline files are scaffolding. Do not infer implemented runtime conventions from them.
- The archived architecture PRD confirms stable-boundary branches, immutable intent, declared recovery, external execution control, and suspension retaining admitted work. Current published contracts are the behavioral source of truth.

## System model extracted from the contracts

| Concern | Source | Modeling interpretation |
| --- | --- | --- |
| Authority | `authority-and-recovery.md:41`, `:59` | One logical, serial authority domain; commands commit atomically. A write-availability predicate is an environment input. Actual consensus and durable replication remain assumptions. |
| Compute | `computation-and-effects.md:76`, `:86` | Host evaluation and authority commit are distinct events, allowing takeover, result arrival and suspension between them. Pure application state is opaque. |
| Execution | `authority-and-recovery.md:69` | Admission, local precheck/entry, external completion and observation recording are distinct events. An owner incarnation is never reused. |
| Faults | `authority-and-recovery.md:156` | Lost proposals, lost acknowledgements, repeated delivery, host takeover, owner loss and unavailable writes. Connection loss may coexist with physical execution. |
| Ordering | `computation-and-effects.md:76` | One authority-ordered inbox; explicit sequence and dispositions. The inbox is an ordered list because order is itself a required property. |
| Time | `authority-and-recovery.md:75` | No wall-clock correctness assumption. Deduplication protection is abstracted as applicable/expired within a stable domain, independent of attempts. |
| Trust | `platforms-and-trust.md:36`, `:90` | Trusted runtime code and members; operation-specific external authorization checked before receipt lookup. No Byzantine or malicious-code guarantee. |
| Branches | `lifecycle-and-archives.md:33`, `:37` | Boundary eligibility is captured when committed. Branch-local queue and permissions are fresh; historical work stays read-only. |
| Portability | `lifecycle-and-archives.md:60` | Model validation categories and activation decisions, not ETF bytes or decoder performance. |

## Requirement and scenario coverage plan

This table supports omission detection and source diagnosis. The primary target is the composed architecture under G01–G08 and an observable reference relation, defined in `research/system-verification.md`; row-by-row success is insufficient for architectural acceptance.

Every entry below is **planned**. Full runtime/platform claims remain unverified even when their abstract protocol portion is exercised.

| Requirement | Scenarios | Planned formal coverage | Remaining implementation evidence |
| --- | --- | --- | --- |
| R1 | S1, S6 | Operation-opaque runtime records; two generic application examples using the same transitions | Actual module dependency/API inspection and non-Agent runtime |
| R2 | S1, S2 | Invocation/Reply correlation without Agent-specific transitions | Agent facade and type/API integration |
| R3 | S3 | Host loss, stable identities, result recording and consumption by replacement host | Real remote execution and supervision |
| R4 | S5 | Open/finished/failed lifecycle, takeover, version checks | Actual lifecycle resource behavior |
| R5 | S15 | UI disconnect independent of Run; role/write-availability predicates | Packaging, devices and real networks |
| R6 | S4 | Atomic commits, receipt recovery, unknown and crash boundaries | Storage fsync/replica recovery and real crash injection |
| R8 | S2 | FIFO, input/command deduplication, stale continuation/unknown disposition, finish and FailRun | Pure-step resource budgets and implementation atomicity |
| R9 | S9 | Scope/provider compatibility, dependency availability, generation changes | Cordex resource cleanup and restart behavior |
| R10 | S10 | Unavailable-authority rejection and stale-owner fencing under a single-authority assumption | Ra quorum safety, disks, partitions, snapshots and toolchain |
| R11 | S11 | Recovery policies, deduplication expiry/domain, settlement, late evidence, one-use permission | Provider's real idempotence/deduplication guarantees |
| R12 | S12 | Captured intent unchanged; precise bindings and stable request token across attempts | Resource identity/compatibility declarations |
| R13 | S13 | Earlier recorded stable boundaries, fresh identities/queues, no historical execution | Actual history storage and retained data |
| R14 | S14 | Controller replacement/fencing, no automatic bypass, audit cannot grant execution | External controller UI/persistence and projection APIs |
| R15 | S15 | Independent roles and UI lifecycle at the contract level | BEAM/browser/Android platform integration |
| R16 | S16 | Authentication and operation authorization before mutation or receipt lookup | Authentication mechanism and deployment trust enforcement |
| R17 | S17 | Validation before import, suspended branch, ready/waiting/finished, fresh permissions | Actual archive encoding, registered code and resources |
| R18 | S18 | Invalid/oversized/unregistered-data categories block activation | ETF round trips, malformed bytes, atom safety and decoder resource measurement |
| R19 | S19 | Both admission/suspend orders, old grant retention, delayed results, resume consumption once | Actual restart persistence and execution supervision |

## Priority property inventory

High priority means a core guarantee or ADR-008 race; medium means a supporting contract. Property names are proposed stable identifiers for implementation.

| ID | Priority | Property / obligation | Source |
| --- | --- | --- | --- |
| P01 | High | State change, successful input consumption and new Effects are committed together; failed proposals have no partial application | `computation-and-effects.md:140` |
| P02 | High | Current epoch, state revision and head cursor fence CommitStep/FailRun; execution revision separately fences admission/resolution | `authority-and-recovery.md:41`, `computation-and-effects.md:146` |
| P03 | High | Authorization precedes receipt lookup; an original payload returns its original receipt after lifecycle changes; changed payload conflicts | `authority-and-recovery.md:59`, `platforms-and-trust.md:90` |
| P04 | High | At most one admitted Attempt per Effect; one owner/binding per Attempt; one local provider entry per owner/Attempt | `authority-and-recovery.md:69`, `:156` |
| P05 | High | Owner replacement cannot inherit a grant; loss before/after an unobserved call remains unknown | `authority-and-recovery.md:69`, `:156` |
| P06 | High | Effect intent and request token persist across Scope changes and recovery; generation/resource precheck cannot silently substitute a binding | `capability-composition.md:89` |
| P07 | High | Unknown retry requires applicable declared policy or one-use permission; a changed/expired deduplication domain cannot silently authorize recovery | `authority-and-recovery.md:79`, `:176` |
| P08 | High | Later failed/not_executed attempts do not erase an earlier unknown execution | `authority-and-recovery.md:94`, `:176` |
| P09 | High | Outcome and terminal reply are committed atomically once; conflicting late evidence never replaces the terminal outcome | `authority-and-recovery.md:79`, `:176` |
| P10 | High | Settlement and observation compete by execution revision/order; allow_repeat grants at most one future admission and does not dispatch | `authority-and-recovery.md:104` |
| P11 | High | Suspend, takeover and controller change fence new proposals but retain previously committed grants and valid observations | `lifecycle-and-archives.md:148`, `capability-composition.md:101` |
| P12 | High | Only the minimum unprocessed queue sequence can be handled; cursor advances continuously; continuation cannot overtake existing inputs | `computation-and-effects.md:76`, `:140` |
| P13 | High | Stale continuations/obsolete unknown notifications are explicitly disposed without application execution; evaluated unknown proposals become stale on terminal-result arrival | `computation-and-effects.md:80`, `:84`, `:146` |
| P14 | High | Consuming an uncertainty notification is not final consumption; finish may consume the last terminal reply but cannot abandon unresolved work | `computation-and-effects.md:86`, `:150` |
| P15 | High | FailRun retains last committed state and Effects; terminal Runs cannot resume/advance/admit; late replies remain unprocessed rather than consumed | `computation-and-effects.md:90`, `:152`, `lifecycle-and-archives.md:117` |
| P16 | High | Stable eligibility is recorded at commit and cannot be acquired retrospectively; branch uses only the selected prefix | `lifecycle-and-archives.md:33`, `:130` |
| P17 | High | Fork/import creates suspended fresh Run/queue/permissions; ready rebuilds local continuation, finished remains terminal; old permissions cannot execute | `lifecycle-and-archives.md:37`, `:136` |
| P18 | Medium | Invalid data, versions, resources or access block import before activation and never install code | `lifecycle-and-archives.md:89`, `:136`, `:142` |
| P19 | High | Unavailable authoritative writes create no new durable receipt, state commit or admission; already authorized external work may continue | `platforms-and-trust.md:32`, `authority-and-recovery.md:170` |
| P20 | Medium | Provider dependencies, compatibility and controller route constrain admission; audit/allow_repeat cannot bypass them | `capability-composition.md:42`, `:83`, `:101` |
| P21 | Medium | Observation IDs, input IDs and command IDs have separate deduplication responsibilities; repeated unknown evidence emits no duplicate notification in one unknown episode | `authority-and-recovery.md:79`, `computation-and-effects.md:84` |
| P22 | Medium | Role/UI changes cannot destroy Run identity/history or promote an unconfigured role to storage authority | `platforms-and-trust.md:19`, `:84` |

Implementation must expand every multi-row scenario matrix into individual named scenario tests. This inventory groups properties, not test rows: a single passing property must not mark a whole mixed formal/runtime scenario as verified.

## Interpretation and deferred claims

- Witnesses establish possible reachability, not inevitable progress. A zero sampled count is a coverage gap to investigate, not proof of unreachability.
- No unconditional eventual-success guarantee is stated for unknown non-repeatable work, unavailable providers, suspension or partitions. G08 includes whole-system stall classification and conditional progress checks with explicitly stated availability/fault/scheduling assumptions; fairness cannot be silently assumed.
- Atomic authority commands and absence of conflicting authorities are premises, not conclusions about Ra. Consensus implementation is not being modeled.
- An abstract validation boolean cannot establish ETF safety or actual authorization enforcement. Report this scope explicitly.
- If a counterexample comes from a wrong abstraction, correct the model with evidence. If it exposes a contract inconsistency, preserve the counterexample and request the owner's decision before changing architecture behavior.
