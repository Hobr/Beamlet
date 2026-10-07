# Initial Architecture Evidence

Collected on 2026-10-07. Planning evidence, not an approved design.

## Repository

- CodeGraph exploration did not locate an Elixir runtime, effect, or capability implementation. The visible project inventory has no `mix.exs`, `lib/`, or `test/` implementation.
- `README.md` supplies preliminary package names and product descriptions, but no computation recovery contract.
- Backend/frontend spec indexes are unfilled templates and require repository documentation in English.
- The existing `00-bootstrap-guidelines` task concerns actual coding conventions, not runtime semantics.
- Project-scoped `trellis mem search 'durable'` returned this conversation only; that search found no earlier recovery-model decision.

## Primary Sources

- [Elixir GenServer documentation](https://elixir.hexdocs.pm/GenServer.html): GenServer maintains callback state and participates in supervision; `init/1` establishes state at startup. Processes model runtime concerns, while modules organize code.
- [OTP sys documentation](https://www.erlang.org/doc/apps/stdlib/sys.html), together with the GenServer debugging section: suspend/resume controls an existing process, without defining a persistent application recovery format.
- [Temporal workflow definitions](https://docs.temporal.io/workflow-definition#deterministic-constraints): sequential workflow reconstruction uses history replay. Command sequences must be deterministic; external work is separated from replay, and code changes require compatibility/versioning decisions.

## Design Inferences to Evaluate

- OTP supervision and durable computation recovery require separate contracts. Process startup needs a defined way to reconstruct application progress.
- Explicit resumable state and sequential-code replay are candidate programming contracts. Checkpoints and journals can support either; they are not mutually exclusive storage mechanisms.
- Explicit state exposes recovery boundaries but requires applications or an adapter to represent them. Replay offers sequential authoring but introduces determinism and code-version constraints.
- Either candidate must keep Effect representation out of agent business logic and address the gap between external execution and outcome persistence. Neither alone proves exactly-once external execution.

## Capability Composition Research

- [Cordis upstream](https://github.com/cordiverse/cordis) describes a framework for spatiotemporal composability and links its current introductory documentation. This matches the direction named for Cordex in the local README; it does not establish that a full Cordis port is required.
- [Cordis primer linked by upstream](https://deepseek-harness.github.io/deepseek-harness/reference/cordis-primer): plugins publish services through a context, consumers look up services by key rather than import concrete implementations, and declared dependencies determine when plugins can start. Registrations/resources have lifecycle cleanup.
- Cordis `ctx.effect()` concerns registration and cleanup. Beamlet durable Effects concern persisted operations and execution outcomes. These meanings must not be merged or used to imply compensation for external operations.

Options evaluated for Q2 were scoped runtime service composition and fixed module wiring. The user selected dynamic composition (PRD R9) and later selected late provider resolution (PRD R12). Permissions, dependency restart policies, and whether to port particular Cordis APIs remain design work.

## Durability and Partition Research

- The project development shell currently selects Erlang/OTP 29 and Elixir 1.20 (`flake.nix`). It does not configure runtime persistence or replication.
- [OTP disk_log](https://www.erlang.org/doc/apps/kernel/disk_log.html#sync/1): synchronous logging calls alone do not guarantee a disk write; the documentation requires `sync/1` to ensure the contents reach disk. Local disk persistence alone does not create a recoverable copy on another node (design inference).
- [Mnesia transaction contexts](https://www.erlang.org/doc/apps/mnesia/mnesia_chap4.html): transactions provide atomic multi-record updates, while dirty operations lose transaction atomicity/isolation. Transaction functions may be retried, so performing external effects inside them is inappropriate.
- [Mnesia majority and synchronization](https://www.erlang.org/doc/apps/mnesia/mnesia.html#change_table_majority/2): majority configuration can require a majority of table replicas for non-dirty updates. `sync_transaction/3` waits for commit/logging on involved nodes; `sync_log/0` separately documents filesystem synchronization. An eventual implementation must verify the selected acknowledgement path against the actual crash/power-loss guarantee.
- These are existing OTP mechanisms to evaluate, not a selected storage engine or a proof of complete failover safety. Replica placement, authoritative computation ownership, fencing stale writers, disk synchronization, and partition recovery need explicit contracts and failure checks.

The user selected cluster durability with a designated subset of authoritative storage nodes, recorded in PRD R10. Selecting the storage mechanism still requires validating authority replica placement, acknowledgement conditions, and partition/failover safety.

## Uncertain Execution Outcomes

- [OTP erpc documentation](https://www.erlang.org/doc/apps/kernel/erpc.html#receive_response/2): after a timeout or connection loss, it may be unknown whether the remote function was or will be applied. Abandoning an RPC response does not establish that the remote operation did not execute.
- [Distributed Erlang documentation](https://www.erlang.org/doc/system/distributed.html): `nodedown` reports loss of the connection to a node. A lost connection alone is not proof that execution stopped on that node (design inference).
- Design inference: a worker may complete an external operation and then fail before recording its outcome with the storage authorities. Persisted dispatch/attempt metadata must distinguish this uncertainty from proof of non-execution; unconditional retry may repeat the external operation.
- The user selected operation-declared recovery, recorded in PRD R11. Retry limits, late outcomes, and provider binding remain technical design work; the validity of any deduplication guarantee across provider changes must be addressed.

## Provider Binding Decision

The initial request describes Effects as persisted, resolved to capabilities, and then executed; R9 additionally requires runtime capability replacement. Neither establishes how a queued Effect responds to a changed capability implementation.

The following candidate contracts were reviewed:

1. Persist an immutable operation intent, including the relevant arguments, configuration, and matching constraints; resolve an eligible provider/resource when execution is attempted. Replacement implementations can execute queued work only while meeting that saved contract. An uncertain retry additionally has to preserve the repeatability/deduplication guarantee from R11.
2. Bind the Effect to a concrete provider at creation and retain that binding. Recovery requires that provider's version/resources to remain available or an explicit rebinding decision.

The user selected option 1, recorded in PRD R12. Public API shapes remain undecided. Late binding must not mean substituting current mutable model/configuration into an already persisted request, and matching a callable name alone is insufficient evidence that provider semantics or deduplication domains are compatible.

## Fork Boundary Decision

Explicit state progression (R8) provides committed application-state boundaries, but a committed state may still be awaiting outstanding Effects. The original request requires fork without undo or external compensation; it does not specify whether a fork may inherit waiting/running/unknown work.

Reviewed option 1: initially permit forks at committed boundaries with no unresolved Effects associated with that boundary. Preserve the historical prefix and recorded outcomes, and give the new branch independent identity for subsequent work. Source computation activity after the selected boundary continues independently; the fork does not restore an earlier external environment.

Reviewed option 2: additionally permit a fork at an in-flight boundary. This needs explicit rules for whether pending outcomes are shared or independently acquired, how attempt identities differ, and how uncertain external operations are handled under R11.

The user selected option 1, recorded in PRD R13. Stable-boundary recognition and history/lineage representation remain technical design work.

## Review Scope Decision

The initial request includes review alongside fork, export, suspend, and resume. It does not establish whether review is read-only historical inspection or also a gate before external execution. R11's explicit resolution of unknown outcomes is a separate recovery function and does not itself mandate pre-execution approval.

The user selected history/state inspection, recorded in PRD R14. They explicitly require pre-execution review to remain external to the Effect/Durable module and composable after Effect creation and before execution. The design must identify a usable execution-path seam; adding a built-in approval state machine is outside the contract.

## Endpoint Runtime Evidence

- [Mob official site](https://mobframework.com/): mobile application UI and logic run on an on-device BEAM node, including Android; the framework supports OTP supervision and Erlang-distribution development connections. This supports evaluating Android as a runtime/resource host rather than assuming it is only a remote UI.
- [Elixir Desktop upstream](https://github.com/elixir-desktop/desktop): Elixir/Phoenix desktop applications use platform backends; the native desktop backend uses OTP wx/wxWidgets, with other host backends available. Native packaging and UI runtime dependencies need platform-specific validation.
- [Phoenix LiveView documentation](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html): the connected LiveView process and assigns reside on the server, with rendered updates and events exchanged with the browser. The browser can interact through a Phoenix BEAM node; it should not be assumed to host the Elixir computation itself (design inference for this architecture).
- No endpoint implementation exists in the repository. Runtime/package compatibility, mobile OS lifecycle and network behavior, and real-device failover remain validation work. These sources establish framework capabilities, not evidence that Beamlet already runs on those platforms.

The user selected configurable full-node roles on BEAM-hosting surfaces, recorded in PRD R15. Under R10, a node that cannot reach a valid authority write path cannot acknowledge new cluster-durable progress; this does not establish that an external operation already admitted has stopped.

## Cluster Trust Boundary

[Distributed Erlang's security documentation](https://www.erlang.org/doc/system/distributed.html#security) describes cookie-based node admission and warns that ordinary distribution is not cryptographically secure by itself. Its overview warns that exposing an insecure distribution node can expose the whole cluster to control by an attacker.

Design inference: a capability scope is a composition/selection boundary, not a sandbox against malicious code or a malicious BEAM cluster member. The architecture needs a clear product scope: operator-managed trusted cluster members, or additional untrusted execution domains isolated from the shared BEAM cluster. External clients still need validated/authenticated application interfaces in either case.

The user selected the operator-managed trusted cluster scope, recorded in PRD R16. Application-boundary authorization remains necessary; an untrusted third-party execution protocol is outside the initial scope.

## Authority Storage Candidate

[Ra upstream](https://github.com/rabbitmq/ra) provides an Erlang/Elixir Raft implementation for persistent replicated state machines, including leader election, replication, snapshots, and membership changes. It is a candidate for the explicit authority-group contract rather than a reason to replicate storage on all computation/execution nodes.

This is preliminary research, not a selected dependency. The README viewed lists OTP 26/27 support while the project's development shell selects OTP 29; current release support and acknowledgement/disk-synchronization semantics require further verification. Compare the actual R10 contract against this candidate and the previously researched OTP persistence mechanisms before choosing an implementation.

## Export Scope Decision

The request requires export but does not establish whether the exported artifact is inspection-only or a portable computation archive.

Proposed initial portable contract: export a stable committed boundary with its necessary application state, history/completed outcomes, lineage, and contract/code/schema references. A target environment with compatible code and matching resources can import it as a new branch and continue from that boundary without repeating completed historical operations. Live processes and provider credentials are not portable computation state; resource references must be satisfied by the target environment.

The user selected the portable computation archive option, recorded in PRD R17, and explicitly permits using a constrained ETF representation (R18). The inspection-only alternative was not selected. Archive envelope, codec profile, resource matching, and compatibility handling remain technical design work.

## ETF Primary-source Evidence

- [OTP External Term Format](https://www.erlang.org/doc/apps/erts/erl_ext_dist.html): OTP provides term encoding/decoding and also defines a compressed representation. Term interpretation remains application-specific.
- [binary_to_term/2](https://www.erlang.org/doc/apps/erts/erlang.html#binary_to_term/2): `safe` prevents new atoms/external function references but does not validate application semantics; `used` reports consumed bytes, allowing trailing-data rejection.
- [term_to_binary/2](https://www.erlang.org/doc/apps/erts/erlang.html#term_to_binary/2): `local` targets the originating runtime instance. `deterministic` promises stable bytes within an OTP major release, without the same promise across major releases.
- Design inference: portable state needs a bounded data-only profile and stable logical references instead of PID/port/reference/function values. Code/schema compatibility remains an application/runtime contract despite successful ETF decoding. Compression admission needs a resource-bound decision; do not equate a small encoded size with a small decoded allocation.

## Suspension Decision

Stopping new state advancement/attempt admission while accepting outcomes from already admitted work preserves the current durable history without claiming that an external operation was cancelled. Resume can consume those recorded outcomes under the normal state/input contract. A committed suspension cannot retroactively revoke an execution already granted across a network.

The user selected stopping new progress/admission while retaining in-flight outcomes, recorded in PRD R19. Best-effort interruption was not selected and is outside the initial suspension contract.
