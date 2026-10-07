# Architecture Decisions

Target baseline approved 2026-10-07. Accepted records describe intended behavior, not completed code.

## ADR-001 — Explicit State Progression

Status: accepted.

Use portable state/input transitions and capability invocations. Sequential-function history replay would improve linear authoring but impose broad determinism and code-change restrictions. Explicit stages make restart and boundary semantics visible without serializing BEAM stacks/closures.

Consequences: transitions are pure/re-evaluable; captured continuation is data; external observations enter through durable capability replies.

## ADR-002 — Designated Authority History and Stable Identity

Status: accepted.

Users select storage authorities; other nodes can host computation/resources without replicas. Host-independent Run/Effect identity and conditional authority commands support takeover. Node-local PID/state alone cannot provide the selected single-authority-loss/partition contract.

Consequences: state/input/Effects commit atomically; mode/ownership epochs fence progress/grants; original attempt permissions still validate reports. Membership/discovery is not canonical ownership. Storage receipts do not prove external success.

## ADR-003 — Capability Composition and Policy Boundary

Status: accepted.

Capability/Scope contracts support dynamic implementations, dependencies and lifecycle. Immutable request meaning is captured at creation while providers/resources resolve at execution. Pinning a concrete instance would restrict recovery; resolving current mutable settings would change existing requests.

Execution orchestration can be replaced externally between creation and execution. Approval states/UI/policies remain outside Effect/Durable. There is no automatic bypass when an external controller owns the path.

## ADR-004 — Conservative Uncertainty

Status: accepted.

Possible execution retries follow declared idempotence, valid deduplication or explicitly permitted repetition. Other outcomes remain unknown until explicit resolution. Unconditional retry would repeat unknown external work; forcing every safe operation to wait would sacrifice useful automation.

No Saga/undo or exactly-once claim follows from canonical state/result deduplication. Late evidence stays auditable without rewriting consumed history.

## ADR-005 — Stable Branches and Portable Data

Status: accepted.

Fork/export uses committed settled boundaries. A new Run inherits state/completed history and creates independent future work. Live source attempts/queues, processes, code installation, credentials and external-world snapshots are not implicit archive content.

Use a versioned bounded ETF data profile and registered compatible code/resources. Initially exclude in-flight graph cloning, implicit migrations and compressed/instance-local output. Application graph operations can compose generic primitives explicitly.

## ADR-006 — Trusted Configurable BEAM Hosts

Status: accepted.

Native BEAM endpoints can independently enable compute/execute/interaction and authority roles; Web uses a Phoenix host. User/operator-controlled nodes and installed code are trusted. Untrusted third-party execution needs a separate isolation/protocol architecture.

Client/view process lifetime is distinct from Run lifetime. Standard OTP supervision/distribution and application edge validation earn their roles; new sandbox/membership frameworks are not initial scope.

## ADR-007 — Authority Implementation Target

Status: proposed, gated.

Evaluate a concrete Ra-backed authority module with one group and three persistent voting nodes for one-node-loss tolerance. Do not create a multi-backend framework or implement consensus.

Alternatives: OTP disk_log is a local primitive; Mnesia transactions/majority are a real native option but require an explicit application recovery/ownership contract. Ra directly fits a closed replicated command machine. Application history must survive backend log/snapshot compaction as application data.

[Ra API](https://ra.hexdocs.pm/ra.html#process_command-3) describes applied command replies and majority-related timeout; [consistent_query](https://ra.hexdocs.pm/ra.html#consistent_query-2) supplies the required current-leader read check. [v3.2.0 WAL source](https://raw.githubusercontent.com/rabbitmq/ra/v3.2.0/src/ra_log_wal.erl) synchronizes before written notifications and includes a no-sync path that cannot support the promised profile.

The [v3.2.0 README](https://raw.githubusercontent.com/rabbitmq/ra/v3.2.0/README.md) lists OTP 26/27; project configuration selects OTP 29/Elixir 1.20. Compatibility and end-to-end disk/quorum behavior are unverified. No dependency is installed by this spec publication.

Before adoption: pin/compile/test the actual candidate, verify follower persistence and application acknowledgement, receipt loss/retry, snapshots, node/disk loss, partitions, stale permission, and suspend/admission races. Failure reopens this implementation choice, not the reviewed guarantee.

## Supersession and Validation

Add a new record when an accepted contract changes; link and mark the previous record superseded. Preserve requirement/scenario mappings in the [index](./index.md).

First future implementation: a non-Agent state/capability/authority/worker slice with real faults, then Agent/providers and platform packages. Codec limits, frontend/toolchain/device behavior and resource matching require their corresponding tests. This baseline documents those gates and does not claim they passed.
