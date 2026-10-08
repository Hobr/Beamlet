# Quint architecture verification design

Status: proposed for user review; no Quint logic has been implemented.

## Boundaries and source authority

Model `spec/architecture/` as one composed architecture. The baseline and ADR-008 supplement retain their current review status. Whole-system G01–G08 and an independent observable reference view are the primary verification target, as defined in `research/system-verification.md`. The intake's P01–P22 and R/S mapping diagnose failures and audit omissions.

Use one integrated verification task and one executable composition of gateway, compute, authority, controller/Scope, owners/providers, FIFO input, lifecycle and branches. All their transitions and faults participate in the same `step`; separate source modules do not create disconnected models. Focused configurations are additional evidence and must not substitute for full-composition checking. Review component assumptions/guarantees to detect incompatible or circular contracts.

## Proposed suite layout

```text
spec/quint/
  README.md                   # scope, assumptions, update procedure and commands
  architecture.qnt            # shared state, composed step, global G01-G08 checks
  architecture_test.qnt       # full-system paths, interference and recovery traces
  reference.qnt               # independent observable ledger rules/projection
  runtime.qnt                 # computation/execution transition functions
  runtime_test.qnt            # focused runtime/race diagnostics
  branches.qnt                # boundary/import functions using shared state
  branches_test.qnt           # focused lineage/activation diagnostics
  access.qnt                  # gateway/role functions using shared state
  access_test.qnt             # focused access/refusal diagnostics
  negative_controls_test.qnt  # bad cross-boundary transitions detected globally
  coverage.md                 # supporting source/property/test/evidence index
  verification-report.md      # architecture conclusions under G01-G08
  check.sh                    # composition + focused reproducible checks
```

Component functions operate on the same declared architecture state. Add shared types only as necessary, with a single owner for each state variable. Never instantiate independent runtime copies for access/branches and assume they compose. Concrete analysis modules bind all constants. The reference view contains only external ledger/control/lineage events, not another implementation of all component guards; every detailed transition must project to an allowed reference transition or observable no-change. This projection permits internal events without adding a blanket executable stutter. Scenario tests stay in separate `_test.qnt` files.

## Model structure and communication choice

Plain Quint is appropriate for this abstraction: a single serialized authority state is shared by command transitions, while host evaluation and local execution supply environment transitions. The suite does not implement or exchange Ra/network protocol messages. Choreo becomes appropriate if a later task models the actual distributed message protocol; this task deliberately keeps consensus outside its boundary.

Commands, evaluations, external calls and observations are distinct events even though they share a transition system. Lost responses and duplicate delivery are represented as environment events/reissued immutable requests. Receipt existence is independent of whether a caller has received it. Do not assume delivery, success or stable connectivity.

The authoritative inbox uses an ordered list because FIFO order is a target property. Other history/observation collections may use sets or maps when order is immaterial. A network packet queue is not introduced.

## Reviewable state sketch

The following is a conceptual type sketch, not executable Quint. IDs are opaque integers/binaries; enum labels represent closed state variants. Parameterization starts with one Run/Effect, then adds small finite domains.

```text
Mode = Active | Suspended
Lifetime = Open | Finished | Failed
Progress = Ready | Waiting | FinishedProgress | FailedProgress
EffectPhase = Pending | Executing | Unknown | OutcomeRecorded | Consumed
AttemptPhase = Admitted | UnknownAttempt | ObservationRecorded
InputKind = External | Continuation | Uncertainty | TerminalReply
Disposition = Queued | ConsumedInput | StaleContinuation |
              ObsoleteUncertainty | RunFinished | RunFailed
RecoveryPolicy = NonRepeatable | Idempotent | Deduplicated | RepeatDeclared

RunState = {
  identity, definitionVersion, applicationState,
  stateRevision, historyRevision, hostEpoch, orchestrationEpoch,
  mode, lifetime, progress, inputCursor, nextQueueSeq,
  inbox: List[InputEnvelope], effects: EffectId -> EffectState,
  finishResult, failureReason, retainedBoundaries
}

EffectState = {
  identity, invocationRef, immutableIntent, stableRequestToken,
  capturedPolicy, executionRevision, phase,
  attempts: AttemptId -> AttemptState,
  terminalOutcome, terminalReplyId, unknownEpisode, repeatPermission
}

AttemptState = {
  identity, ownerRef, preciseBinding, originalAdmissionEvidence,
  phase, observations, unresolvedExecutionEvidence
}

OwnerState = {
  incarnation, reachable, alive,
  enteredAttempts: Set[AttemptId], providerCallCounts,
  actualCompletions, locallyKnownObservations
}

HostProposal = {
  runRef, expectedHostEpoch, expectedStateRevision, selectedQueueSeq,
  selectedInputId, evaluatedUnknownContext, proposedStepOrFault
}

AuthorityState = {
  runs: RunId -> RunState,
  receipts: CommandId -> (CanonicalPayload, Receipt),
  inputKeys, observationKeys, committedCommandEvidence
}

ProviderState = {
  scope, configuration, generation, present, dependenciesReady,
  registeredContract, resourceIdentity, dedupDomain, protectionApplicable
}

var authority: AuthorityState
var owners: OwnerId -> OwnerState
var providers: ProviderId -> ProviderState
var proposals: ProposalId -> HostProposal
var environment: { writesAvailable, callerReceivedResponses, uiConnected,
                   callerOperationPermissions, validatedImportCategories }
var audit: { transitions, performedActions, rejectedRequests }
var referenceState: ObservableLedgerState

modelStructure = { dependencyEdges, actionOwners, boundaryPayloadClasses }
```

Optional fields use explicit sum types (None/Some) or total record placeholders with a validity discriminator. Initialize every declared variable and map domain. Independently changing local/provider/environment state stays separate from authoritative records. No PID, closure, application-specific operation name, wall-clock or arbitrary executable callback enters persistent model state.

Branch state includes immutable captured boundary records, selected history prefixes and lineage. Access state includes caller/operation permissions and attempted requests, with authorization before receipt lookup. Both participate in the shared architecture from the start of composition work. The reference state's rules are defined independently from component update functions, and an abstraction relation compares observable authority, execution, input and branch facts. `modelStructure` checks modeled dependency direction/acyclicity, responsibility assignment and boundary payload classes; it does not inspect absent implementation imports. Large audit histories are bounded or replaced with sufficient minimal ghost evidence.

Audit/ghost state records facts needed to inspect transition properties, such as the permission/epoch at admission and the previous outcome. It does not authorize a business transition. Invariants read this evidence independently from command guards. Local call-count evidence tests actual modeled provider entry, not simply the existence of a committed Attempt.

## Transition grain and data flow

| Operation | Atomic grain | Interleaving intentionally exposed |
| --- | --- | --- |
| Start/AppendInput | Validate and commit records, stable keys and receipt together | Lost acknowledgement and identical/conflicting retries |
| Host evaluation | Capture proposal from committed state and FIFO head; no I/O | Result arrival, takeover and suspend before CommitStep/FailRun |
| CommitStep | Guard and atomic state/input/cursor/Effects/continuation/boundary update | Other commands before and after commit; no partial write states |
| FailRun | Guard and atomic terminal fault/dispositions; no new business Effects | Takeover, obsolete unknown input and outstanding authorized work |
| AdmitAttempt | Check lifecycle, orchestration/revision, provider/recovery and commit binding/grant | Competing controllers, suspend, one-use permission consumption |
| Dispatch/precheck/call | Per-owner duplicate suppression and generation/resource check, then irreversible local call entry | Repeated dispatch, owner loss, generation changes after admission |
| External completion | Local actual result may exist without authority knowledge | Loss before observation; old unknown owner can still finish during recovery |
| RecordObservation | Validate original grant/owner/intent; commit evidence, outcome/reply when justified | Epoch change, suspended/failed Run, duplicate/conflicting evidence |
| ResolveInvocation | Revision-guarded audit, settlement or one-use permission | Observation/settlement races and stale/new command IDs |
| Suspend/Resume/ClaimHost/controller change | Commit mode or permissions/epochs | Old grants survive; new proposals are fenced |
| Fork/Import | Capture selected stable prefix; create new suspended identity/queue atomically | Source progresses independently; import validation may refuse |

A confirmed owner death differs from connectivity loss. Connectivity loss cannot erase a live instance's entry marker or prove non-execution. A restarted owner always has a fresh ID. Not-executed evidence applies only to its own Attempt. Unresolved earlier execution survives later precheck rejection or failure.

Record terminal outcome and reply together. Consuming unknown input cannot mark Effect consumed. Only successful terminal-reply handling does so; failed Run records late replies as unprocessed. Finish may consume the last terminal reply within the same commit, but cannot silently discard unresolved Effects.

## Assumptions, domains and bounds

- Trusted registered code, providers and execution-owner references; authenticated callers can still submit unauthorized/invalid requests.
- One authoritative serial history and consistent reads. `writesAvailable` only represents access to that history; it does not prove quorum/replication.
- Recoverable stable keys and evidence persist throughout modeled retries; no unsafe TTL eviction.
- Captured declarations and explicit provider compatibility are inputs, not proofs of implementation equivalence.
- No unconditional availability/fairness promise. G08 classifies expected waiting and tests conditional system progress under explicitly named restored-availability, finite-fault/input and scheduling assumptions; witnesses remain reachability evidence.
- Initial tiny configuration: one Run, one Effect, two owner incarnations and two competing proposals/controllers. Expanded scenarios: two Runs, two Effects, up to three Attempts/owners, two providers/generations and at least four FIFO inputs. Increase queue/domain capacity for mandatory traces that require it.
- IDs are never reused or counters wrapped to remain within a bound. Fresh-ID exhaustion is reported as a finite-domain limitation. State/history/execution counters are monotonic; bounded trace length limits their explored values.
- Begin bounded verification at depth 10, then focused depth 20 when feasible. Seeded simulations start with 10,000 traces and depth 40–100 according to each model's enabled work. Log actual configuration and duration.
- Legitimate quiescence includes open/waiting with no inputs, unknown without recovery permission and a suspended Run. Inspect early-stopped traces. Do not add a blanket stutter action to hide deadlock/domain exhaustion. Model-checker deadlock settings and terminal conditions must be explicitly documented if adjusted.

The chosen domains provide race coverage, not generalization to arbitrary participants or unbounded history.

## Property and scenario design

Begin with global G01–G08 and the reference projection, then use source-linked P01–P22 to localize violations and audit missing clauses. Structural dependency/responsibility checks, state invariants, transition relations, refusal tests and conditional progress obligations are distinct. Each major action has a positive witness false at initialization. Full exploration enables cross-component transitions/faults together and includes multi-Effect and source/branch interference; targeted scenarios supplement this exploration.

The integration gate includes long combined paths such as admission -> disconnect -> takeover -> unknown -> suspend -> provider replacement -> repeat permission -> resume -> recovery -> late-observation/settlement race -> FIFO consumption -> earlier-boundary fork -> independent new work. Review that component guarantees actually supply other components' preconditions, and detect circular or unprovided assumptions. A focused passing test never clears an uncompleted composition gate.

Examples of independent properties:

- An Attempt's owner/binding never changes; a replacement owner's call ledger cannot reference the old grant.
- Call-count per owner/Attempt is at most one; a stable Effect token stays equal to its captured original across recovery.
- Recorded terminal-outcome history contains only one authoritative choice and at most one terminal-reply identity, even if observations conflict.
- A repeat-permission audit entry has at most one admission consumer and cannot be inferred from ordinary evidence.
- A successful business transition records the current epoch and FIFO head; rejected requests leave authoritative business data unchanged.
- Every input before the cursor has a recorded disposition; no queue gap is hidden by a larger cursor.
- A boundary's stored eligibility depends on its captured state, not later completion; a branch cannot perform an inherited Attempt.

Negative controls deliberately weaken a transition in a separate test module, then require the independent property to reject it. Do not modify the production model temporarily and risk leaving a bad guard in place. Include owner inheritance, duplicate terminal reply, stale proposal commit and repeated permit consumption.

## Toolchain and verification artifacts

The installed Nix Quint 0.32.0 package already includes Apalache 0.56.1 and supplies OpenJDK 21 through its wrapper's PATH. A real temporary two-step `quint verify` probe passed in 4951ms. No Java/Apalache installation or `flake.nix` dependency change is needed. See `research/system-verification.md` for package paths, wrapper behavior and the probe. Record the bundled versions and use local CLI help when flags differ from the reference.

Development uses typecheck -> scenario -> sampled run incrementally. Final checks exercise the composed architecture/global/reference properties, supplemented by bounded focused diagnostics. Record actual domains/depths and progress assumptions; timeout/failure is inconclusive. The reference relation is bounded evidence, not an unbounded refinement theorem.

The runner should fail on typecheck/test/invariant errors, retain witnesses and execution metadata, and distinguish simulation from optional backend-dependent bounded checks. Keep machine-generated large logs out of the maintained contract library; retain concise evidence plus reproducible seeds/configuration and counterexample traces when useful.

## Compatibility, changes and rollback

No product migration is involved. Add the formal suite under `spec/quint/` and link it from `spec/README.md`; keep contract behavior and review statuses intact. An intentional behavior change must first resolve its architectural finding with the owner and then update the owning contract, model, tests and coverage.

If a counterexample reflects a model error, fix the abstraction against the cited clause and preserve the explanation. If it reflects conflicting clauses, retain the trace and stop only the dependent semantic change while completing independent checks. The additive suite and index link are the rollback boundary; never discard user changes.
