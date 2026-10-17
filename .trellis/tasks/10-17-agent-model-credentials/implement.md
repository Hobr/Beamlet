# Extensible Model Providers — Execution Plan

## Status

Implementation approved ("批准") at baseline dev18137b1. Task creation and the
complete final design, including compatibility migration, are approved. Provider
extensibility supersedes the earlier key-only plan. The user accepted one immutable
active binding per Agent; design.md specifies the approved interfaces.

## Planning

- [x] Inspect key sourcing, Agent dispatch and Runtime worker context.
- [x] Inspect provider coupling in Agent.Server, Integration.Handler,
  Catalogue.batch and Deterministic.
- [x] Record revised requirements and proposed provider-neutral seam.
- [x] Resolve first-release cardinality: one immutable active binding per Agent.
- [x] Specify exact neutral request/reply/history, provider invocation/registry,
  credential data limits and migration contracts.
- [x] Converge PRD/design/plan and refresh context manifests.
- [x] Present revised final summary and obtain implementation approval ("批准").

## Execution After Approval

- [x] Create feature branch feat/agent-model-credentials and set task metadata.
- [x] Activate task; dispatch serial component writers per ownership.md.
  A single writer owns the checkout at any time, followed by independent check.
- [x] Extract neutral Harness request/reply/history and Tool batch validation;
  preserve supported text/Tool identities, order, bounds and error behavior.
- [x] Update OpenAI-compatible adapter to own all wire conversion and invocation
  config/credential validation. Migrate deterministic provider to neutral data.
  Initial focused evidence: harness-handoff.md (31 tests); accepted after repairs below.
- [x] Introduce bounded generic Operation invocation credentials and Runtime
  handler forwarding; maintain whole-envelope accounting and ordinary data rules.
  Initial focused evidence: operation-handoff.md (9 Actions,30 Runtime,6 distributed);
  accepted after repairs below.
- [x] Add Agent-owned model binding, model-only credentials and neutral loop;
  migrate executor provider registration/readiness and integration adapters.
  Initial focused evidence: agent-node-handoff.md (4 Agent,57 Node,3 distributed);
  accepted after repairs below.
- [x] Update fixtures/examples and add alternative-provider seam tests.
- [x] Run full-scope acceptance and publish actual verification/handoff.
  Integration evidence: verification.md/handoff.md (138 ordinary,9 distributed,
  static/release/Web/fixture gates), superseded by final repaired evidence below.
- [x] Dispatch independent trellis-check; repair and freshly recheck F1-F3.
  Main accepted recheck-report.md READY: 161 ordinary and12 actual named distributed
  tests, format/warning-fatal compile/strict Credo/full existing-PLT Dialyzer,
  rebuilt copied closure/all7 eval/all7 named startup/RPC/stop and independent probes.
  Initial BLOCKED report and repair handoffs remain historical evidence.
- [x] Synchronize executable specs via trellis-update-spec: neutral provider/history,
  dedicated credential bounds/forwarding, immutable binding, distinct-authority
  delegation validation, registry/capabilities and current deployment migration.
  Markdown/link/path/whitespace checks recorded in spec-sync.md.
- [x] Present exact five scoped work batches plus archive/journal; user approved "ok".
  Commit work per commit-plan.md, then run prescribed finish-work archive/journal.
  Final bookkeeping outcome is recorded in the session journal.

## Required Acceptance Evidence

- OpenAI model -> concurrent Tools -> model on independent interaction/authority/
  executor VMs with no executor user credentials; subsequent turns retain binding.
- Two Agent bindings/configurations/keys on one executor without contamination.
- Test-only non-OpenAI provider using different config/auth fields and internal
  reply encoding completes neutral text/Tool flow. Generic code must not call
  OpenAI parsers. No real second external provider is required.
- Provider validation owns required fields and rejects unknown/unsupported
  configuration. No environment fallback, dynamic executable module selection or
  provider/model substitution on scheduling failure.
- Neutral malformed/oversize/history/batch errors; ordered joins; ordinary and
  new invocation full byte caps; no credentials in normal outputs/Tools.
- Explicit child configuration/no automatic inheritance; existing peer,
  lifecycle-retirement, guarded-submit, stop/loss/capacity/no-fallback tests.
- Direct Harness TCP/TLS wire/auth/body/no-retry/redirect/overflow/global-default
  isolation; copied named backend release/closure/RPC/stop and Web secret/CSP.
- One binding stays fixed across turns; unsupported model collections/switching
  options fail. Different Agents retain independently configured bindings.
- Registry startup/readiness performs no provider network calls and advertises
  only supported adapters. Preserve combined report/capability bounds.

Use synthetic keys and local fixtures only. Exact shared semantic conversion is
tested with assertions, not a new adapter whose implementation calls the same
OpenAI converter. Physical hosts and paid/live calls remain out of scope.

## Commands After Source Changes

```bash
ERL_FLAGS='+S 2:2' mix format --check-formatted
ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors
ERL_FLAGS='+S 2:2' mix test --seed 631927
ERL_FLAGS='+S 2:2' elixir --sname provider_tests --cookie <isolated-test-cookie> -S mix test --only distributed --seed 631927
ERL_FLAGS='+S 2:2' mix credo --strict
ERL_FLAGS='+S 2:2' mix dialyzer
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_node
git diff --check
```

Also run updated copied-release scripts and active changed-file LSP probes where
supported. Report unavailable/inconclusive diagnostics and existing-PLT analysis
separately from PLT refresh. No lock/dependency change is expected.

## Stop and Rollback

Do not widen into automatic model selection, fallback, streaming, other real
providers or credential infrastructure. If neutralizing history uncovers
unsupported semantics, document them and return to planning. Preserve cleanup,
single-attempt semantics and external uncertainty. Roll back matching source/
examples/specs together without resetting unrelated changes. Commit grouping
will follow reviewed module seams; no commits or implementation during planning.
