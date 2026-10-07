# Authority, Attempts and Recovery

Status: reviewed target contract. Ra is an implementation recommendation with an unresolved validation gate.

## 1. Scope / Trigger

Own canonical state/history, conditional commits, ownership fencing, attempt admission and uncertain external outcomes. Neither distributed membership nor local process registration determines authoritative ownership.

## 2. Signatures

~~~text
Authority.command(domain_ref, envelope) -> {:ok, receipt} | {:error, error}
Authority.read(domain_ref, query, consistency: :consistent) -> {:ok, projection} | error

command.body =
  StartRun | AppendInput | CommitStep | AdmitAttempt | RecordObservation
  | ResolveInvocation | ClaimHost | Suspend | Resume | Fork | Import
~~~

These are closed data variants, not serialized functions or arbitrary database updates. All mutation envelopes include command_id and logical payload; conditional variants also include expected revisions/permissions.

## 3. Contracts

### Configuration

Target application configuration under :beamlet_lib:

| Key | Constraint |
|---|---|
| roles | Configured subset of interaction, compute, execute, authority |
| authority_domain | Stable binary identity shared by this deployment |
| authority_nodes | Operator-selected node identities and persistent locations |
| definition_registry | Registered trusted definition/code/schema references |
| codec_limits | Positive bounded profile configuration from [Lifecycle and Archives](./lifecycle-and-archives.md) |

No new environment-variable protocol is prescribed. Deployment adapters validate any environment translation before application startup.

The one-authority-node/disk-loss profile requires sufficient persistent replicas and independent failure domains; the first Ra target is three voting nodes. A weaker development topology must not advertise that guarantee.

### Atomic Records and Commands

| Body | Preconditions | Records changed together |
|---|---|---|
| StartRun | Valid definition/state/scope and creation key | Identity, initial snapshot/progress, inbox/receipt |
| AppendInput | Run accepts input; valid stable input key/data | Ordered input and receipt |
| CommitStep | Current owner epoch, active/open Run, expected state revision/cursor | State/progress, consumed input, new Effects or continuation, history/boundary |
| AdmitAttempt | Active/open Run; eligible provider; no terminal result; valid repeat conditions | Attempt ordinal, exact binding/admission evidence |
| RecordObservation | Recognized original attempt and matching immutable intent | Attempt evidence and, when justified, canonical outcome plus one reply |
| Suspend/Resume/ClaimHost | Authorized conditional control | Mode/host permission and fencing epoch |
| Fork/Import | Stable source/validated archive, compatible target | New identity/snapshot/lineage/receipt |

State, input consumption and new Effect creation must share a commit. No invocation executes before its intent and attempt permission are committed.

State revision tracks business transitions. History revision also changes for input, outcome/control evidence. They are not interchangeable cursors or backend Ra indexes.

### Epochs and Receipts

Takeover/control changes fence obsolete state/grant proposals. Original attempt authorization remains usable for reporting legitimate observations after host change or suspension.

Stable command IDs deduplicate logical mutations. Compare normalized payloads; changed data under a retained key fails. Keep keys/evidence for every supported retry/recovery path; do not delete them simply because a short TTL elapsed.

A receipt proves commit, not external success. A submitted command without established commit status returns commit_unknown. Re-read its receipt or retry its original key/payload. Do not generate a new creation/action identity to escape ambiguity.

Consistent reads govern recovery/fork/export. Replica-local and ordinary cached/leader views are insufficient permission sources. No correctness dependency on synchronized node clocks is allowed.

### Outcome Rules

Operation declarations permit automatic retry after possible execution only for idempotence, applicable deduplication or explicitly allowed repetition. Preserve request semantics and actual deduplication domain/retention. A declaration alone does not extend a provider's expired guarantee.

Canonical result recording and reply insertion are atomic. Duplicate observations do not deliver a second terminal reply. Conflicts/late evidence remain inspectable; consumed results are never overwritten.

Unknown is distinct from confirmed failure and confirmed non-execution. Timeout, nodedown and retry exhaustion are not non-execution evidence. A later failed attempt does not settle an earlier possible execution.

A durable uncertainty notice may enter the ordinary Reply path without final completion. Explicit evidence/repeat decisions use the invocation reference and are appended conditionally; original intent/evidence stay unchanged.

Workers record through authorities independently of the original host PID. Lost notifications are repaired from authoritative pending work/inbox.

## 4. Validation & Error Matrix

| Condition | Outcome |
|---|---|
| State proposal from obsolete epoch/revision | stale_permission; no state/call changes |
| Grant requested after suspension/terminal state | invalid_transition/stale_permission |
| Missing committed intent or unknown attempt token | invalid_admission |
| Same command key, different payload | key_conflict |
| Duplicate terminal observation | Return existing disposition; no new reply |
| Conflicting late observation | Record conflict evidence; canonical reply unchanged |
| No viable authority path before send | authority_unavailable |
| Commit response lost or mutation submission times out | commit_unknown |
| Retry would change deduplication domain/expired protection | Preserve unknown; no automatic grant |
| Result cannot be validated/recorded after external work | Retain uncertainty; never truncate or claim success |

## 5. Good / Base / Bad Cases

Good: commit an intent, grant an attempt, record result into the authority inbox, then commit its consumption. Losing the host between stages does not lose accepted data.

Base: all roles are co-located but logical identities/receipts remain unchanged.

Bad: cache a PID as ownership, use a fire-and-forget message as durable acknowledgement, execute inside replicated apply/transaction, or call every timeout a failure.

## 6. Tests Required

<a id="s3"></a>
### S3 — Remote Execution with Host Loss

Host A commits an operation for provider B. Terminate A while B executes. B reports to authorities; replacement host C reads/consumes the same canonical result. Assert stable Run/Effect identities and no dependence on A's PID.

<a id="s4"></a>
### S4 — Every Crash Boundary

Inject loss before step commit, after step commit/before notification, after admission, after external operation/before outcome recording, and after recording/before delivery. Assert the allowed pending/unknown/recorded state and that recovery never infers non-execution from transport loss.

<a id="s10"></a>
### S10 — Designated Authorities and Partition

Use only the selected storage subset as voters. Under the supported profile, permanently remove one authority node/disk and recover acknowledged state. Partition the group; assert no conflicting authoritative advancement, no minority grant/false receipt, and safe healing/stale-owner rejection.

<a id="s11"></a>
### S11 — Declared Recovery and Late Evidence

Retry a repeatable operation using the same Effect identity but a new Attempt. For an operation without repeat permission, keep unknown until explicit resolution. Replace a provider/deduplication realm or expire protection; reject automatic retry. Assert late conflicting evidence cannot alter a consumed result or enqueue a second reply.

### Storage Implementation Gate

Ra is proposed, not installed/tested. Pin a supported release and prove compilation on the actual OTP 29/Elixir 1.20 toolchain, follower disk synchronization, quorum application/reply, snapshot/log recovery, receipts, fencing and suspend races before a runtime release.

Public journals/checkpoints remain application records across backend compaction. One authority group/retained-history machine is the initial scalability ceiling; partitioning requires measurements and a revised implementation decision.

## 7. Wrong vs Correct

~~~text
Wrong: node disconnected -> retry action with a new ID.
Correct: retain original Effect/attempt evidence -> declared recovery -> new attempt only when permitted.

Wrong: update state; later send/store its actions.
Correct: conditionally commit state + consumed input + new Effects atomically.

Wrong: new host epoch rejects every old-worker result.
Correct: fence old host advancement, validate observations against original admitted attempts.
~~~
