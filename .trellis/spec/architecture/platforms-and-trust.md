# Platforms, Roles and Trust

Status: reviewed target roles/trust. Packaging, toolchains and device/network behavior are unvalidated implementation gates.

## 1. Scope / Trigger

Own cross-platform application edges, client-versus-Run lifetime, node roles and the operator-trusted cluster premise.

## 2. Signatures

~~~text
ApplicationGateway.handle(authenticated_context, command_dto) -> receipt | projection | error
RuntimeBootstrap.start(validated_application_config) -> supervised_roles
ProjectionReader.read(run_ref, query_with_cursor_and_limit) -> revisioned_projection
~~~

Gateway/boot names are target responsibilities, not a new gateway framework. Public commands use [Computation and Effects](./computation-and-effects.md), not direct backend or arbitrary RPC access.

## 3. Contracts

| Surface | Interaction | Computation / execution | Authority participation |
|---|---|---|---|
| CLI / fuelen/owl | Local or connected adapter | Configurable BEAM host roles | Independently configured under storage conditions |
| TUI / agentjido/term_ui | Local or connected adapter | Configurable BEAM host roles | Same rule |
| Desktop / elixir-desktop | Native/Phoenix-based host UI | Configurable host roles | Same rule |
| Android / Mob | On-device Elixir/BEAM UI | Configurable device roles | Same rule, subject to platform validation |
| Web / Phoenix | Browser through authenticated Phoenix edge | Phoenix/other BEAM hosts; independent of LiveView PID | Independently configured |
| Server Node | Headless/application/gateway | Configurable host/resource roles | Stable-host authority candidate |

A node may combine interaction/compute/execute/authority roles. Storage is not replicated on every connected node. Role configuration and required compatible definition/provider code are validated before use.

The browser has no assumed BEAM computation host. UI/view disconnection does not terminate Run identity/history; a connected native app can host computation when configured. Devices can lose processes or connectivity, handled through the same authority/attempt protocol.

A node without an authoritative write path cannot acknowledge new cluster-durable progress. Previously admitted external operations can still finish; disconnect is not cancellation evidence.

### Edge DTOs and Authorization

| Field / boundary | Constraint |
|---|---|
| command_id/input key | Stable binary per logical action; reused with unchanged normalized data |
| run_ref/boundary_ref | Opaque validated references with per-action access checks |
| operation/definition/profile/version name | Binary resolving to registered allowed code/contract |
| payload/options | Validated schema and bounded portable data |
| query cursor/limit | Opaque cursor, positive bounded page size, explicit projection revision |
| resource binding | Validate identity, permission and actual availability |
| response | Shared receipt/error/projection decoder; no independent UI ledger parsing |

Authorize create/input/control, inspect/export, and resource use at their application/provider edges. Validated data is not instruction to load/evaluate modules.

Membership and loaded code are controlled by the user/operator and trusted. Scope isolation selects services; it does not contain malicious code or a malicious admitted node. The authority protocol is not Byzantine consensus.

Use standard secure BEAM distribution and application authentication/authorization as appropriate. No custom cryptographic membership or untrusted-node sandbox product is added to the foundation. Third-party-controlled execution domains require separate isolation/protocol work.

### OTP Lifetime

Use supervisors, registered local computation hosts, task/worker supervisors and provider managers for actual lifetime/concurrency/failure roles. Registry/pg/discovery remain hints. Durable records/epochs/inbox/outbox are authority facts; there is no durable mailbox or process-stack snapshot.

## 4. Validation & Error Matrix

| Condition | Edge behavior |
|---|---|
| Unknown/unauthorized client or Run action | unauthenticated/forbidden; no mutation |
| Invalid schema, arbitrary MFA/module, unsafe term | invalid_data; no execution |
| No compatible installed definition/provider | incompatible_version/unavailable_resource |
| View/terminal connection drops | Reconnect/query by Run identity/revision |
| Compute/execution host disappears | Apply authority recovery/uncertainty, never PID reuse |
| No authority write availability | No false durable receipt |
| Cached projection used to grant ownership/execution | Contract violation |
| Untrusted node treated as a normal member | Outside initial trust scope |

## 5. Good / Base / Bad Cases

Good: mobile UI/compute and desktop provider cooperate through stable server authorities; closing a view does not erase computation history.

Base: server hosts all roles; other endpoints interact through shared DTOs.

Bad: give a browser the distribution cookie, attach Run lifetime to LiveView, or promise a Scope sandbox against node code.

## 6. Tests Required

<a id="s15"></a>
### S15 — Every Endpoint Role

Verify the matrix, independent storage assignment and shared interfaces. In later platform implementation tests, disconnect/reconnect UI, terminate a compute host, lose worker connectivity and verify authority availability/late-outcome behavior. Native packaging, supported OTP/Elixir builds, mobile OS lifecycle and real networking must be tested before claiming platform support.

<a id="s16"></a>
### S16 — Trust and Authorization

Test rejected unauthenticated/unauthorized command, query/export and resource binding requests. Assert external clients cannot become cluster members or execute arbitrary registered/unregistered functions through data. Document that admitted code is trusted and Scope/consensus provides no malicious-member containment claim.

## 7. Wrong vs Correct

~~~text
Wrong: use LiveView PID as durable Agent identity and stop history on disconnect.
Correct: project a stable Run reference through a replaceable view connection.

Wrong: every endpoint must vote/store replicas.
Correct: independently configure authority membership and compute/execute/interaction roles.

Wrong: Scope isolation makes an arbitrary third-party node safe.
Correct: trusted admitted nodes; untrusted execution requires a separate boundary.
~~~
