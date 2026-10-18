# Backend Development Guidelines

Beamlet has a ten-application Elixir Mix umbrella with implemented generic Actions
contracts, an opt-in distributed Runtime and independent native Harness providers.
Agent implements bounded asynchronous orchestration with one immutable Agent-owned
model binding; Harness owns neutral model/history contracts and explicit provider
invocations. Node composes opt-in roles and trusted local model provider registries.
Node is an explicitly supervised library; CLI owns the migrated terminal adapter.
Server is an opt-in host with startup-only authority/executor selection and an
isolated release; CLI is an opt-in fixed interaction host with a foreground standalone session. Agent discovery now provides safe live identity list/lookup and bounded trusted-connected
aggregation through finite local reads/OTP erpc, with query failures isolated from the identity island. The standalone CLI release owns bounded stdin, local Ref aliases and explicit reattachment.
Cross-physical-host acceptance was removed by user decision; no physical execution is claimed. Phoenix provides the web scaffold and disabled-by-default trusted Host/preset/navigation adapters; LiveView workbench and read-only management source are independently checked, and a real local browser walkthrough passed34/35 checks (390px viewport blocked by a Firefox minimum-width clamp). Web and CLI copy is Gettext-translated into `zh_CN` (default) and `en`, with one shared catalogue app plus per-surface catalogues.
These English guidelines describe checked-in behavior; source paths below are
relative to the repository root.

The revised [durable design](../../../docs/architecture/agent-operation-persistence.md)
has format2 Storage/Runtime, event-reduced Agent control and direct reference
fork/history/export integration. See [Event-reduced Agent](./agent-durable.md) and
[Durable references](./durable-references.md). No message-checkpoint/transcript-copy
API or old-format fallback exists. Final independent product acceptance is separate
from the implementation gates recorded in D's handoff.

## Pre-Development Checklist

1. Read the task requirements and [Directory Structure](./directory-structure.md).
   Locate the owning application's source, manifest, and neighboring tests before
   choosing an implementation site.
2. Read [Quality Guidelines](./quality-guidelines.md) for every code change; choose
   checks according to the changed files and available tools.
3. Route by change:
   - State, storage, sessions, or database work → [State and Persistence](./database-guidelines.md).
   - Failures, startup, HTTP error responses, or form feedback → [Error Handling](./error-handling.md).
   - Request diagnostics, metrics, or instrumentation → [Logging and Telemetry](./logging-guidelines.md).
4. Read the [Thinking Guides index](../guides/index.md); follow its conditional
   pointers for reuse and cross-layer changes. Its generic examples are not
   evidence that Beamlet implements those systems.
5. Compare any proposed architecture with actual source. `architecture.md` and
   `architecture_zh.md` explicitly describe the intended system, not an implemented
   product. Archived task snapshots can predate today's code. Implement new
   contracts only within the active task's agreed scope.

Done reading when the owning app, relevant existing behavior, and validation
commands for the change are identified.

## Guidelines Index

| Guide | Read for |
| --- | --- |
| [Directory Structure](./directory-structure.md) | Actual app boundaries, supervision, Phoenix request flow, file placement |
| [Operation Runtime](./operation-runtime.md) | Generic contracts, opt-in supervision, admission, events, limits and failure semantics |
| [Native Harness](./harness-providers.md) | Model/Tool contracts, schema/history validation, HTTP and trusted workspace boundaries |
| [Event-reduced Agent](./agent-durable.md) | Format 2 pure reducer, bounded loader, fixed-source context, paused continuation and C validation |
| [Durable references](./durable-references.md) | Same-authority fork, immutable closure, risk, fixed history/export and offline verification |
| [Agent and Node](./agent-orchestration.md) | Explicit authority, bounded orchestration, lifecycle ownership, subscriptions and roles |
| [Web Management](./web-management.md) | Read-only nodes/presets/diagnostics, bounded refresh and explicit unknown facts |
| [Web Workbench](./web-workbench.md) | LiveView caller/sink ownership, trusted discovery, separate feedback and replacement display |
| [Web Host and Presets](./web-host.md) | Opt-in startup, public selection/private resolution, uncertain creation and ephemeral navigation |
| [Internationalisation](./i18n.md) | Shared vs surface catalogues, locale precedence, default Chinese, extraction and ownership invariants |
| [Live Observation](./live-observation.md) | Opt-in Agent display/metadata, safe report ages, Node readiness and bounded aggregation |
| [Backend CLI and Release](./backend-release.md) | CLI bounds, isolated packaging/config, named control ports and deployment evidence |
| [State and Persistence](./database-guidelines.md) | Stage-A `beamlet_storage` tables/transactions, cookie sessions, configuration and storage pitfalls |
| [Error Handling](./error-handling.md) | OTP startup propagation, status renderers, component feedback and gaps |
| [Quality Guidelines](./quality-guidelines.md) | Formatting, build/test/static-analysis commands, test examples and coverage limits |
| [Logging and Telemetry](./logging-guidelines.md) | Request IDs, formatter, Phoenix/VM metrics, development diagnostics |

Evidence anchors: root `mix.exs`, `apps/*/mix.exs`,
`apps/beamlet_node/lib/beamlet/node.ex`, and
`apps/beamlet_app_web/lib/beamlet_web/application.ex`. Consult the topic files for
concrete source and test examples.
