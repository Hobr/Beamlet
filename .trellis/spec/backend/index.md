# Backend Development Guidelines

Beamlet has a six-application Elixir Mix umbrella with implemented generic Actions
contracts, an opt-in distributed Runtime and independent native Harness providers.
Agent implements bounded asynchronous orchestration with one immutable Agent-owned
model binding; Harness owns neutral model/history contracts and explicit provider
invocations. Node composes opt-in roles and trusted local model provider registries.
Node also provides a thin CLI and isolated backend release; cross-physical-host acceptance
was removed by user decision; no physical execution is claimed. Phoenix provides the existing web scaffold.
These English guidelines describe checked-in behavior; source paths below are
relative to the repository root.

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
| [Agent and Node](./agent-orchestration.md) | Explicit authority, bounded orchestration, lifecycle ownership, subscriptions and roles |
| [Backend CLI and Release](./backend-release.md) | CLI bounds, isolated packaging/config, named control ports and deployment evidence |
| [State and Persistence](./database-guidelines.md) | Absence of a database, cookie sessions, configuration and storage pitfalls |
| [Error Handling](./error-handling.md) | OTP startup propagation, status renderers, component feedback and gaps |
| [Quality Guidelines](./quality-guidelines.md) | Formatting, build/test/static-analysis commands, test examples and coverage limits |
| [Logging and Telemetry](./logging-guidelines.md) | Request IDs, formatter, Phoenix/VM metrics, development diagnostics |

Evidence anchors: root `mix.exs`, `apps/*/mix.exs`,
`apps/beamlet_node/lib/beamlet/node/application.ex`, and
`apps/beamlet_web/lib/beamlet_web/application.ex`. Consult the topic files for
concrete source and test examples.
