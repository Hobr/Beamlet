# Implementation and Integration Plan

## Authorization and Ownership

Planning only until the user approves the latest final summary. All five tasks
must remain `planning` in this turn. Do not run `task.py start`, edit product
code, fetch project dependencies or start an implementation worker now.

The parent owns requirements/design/task mapping/final integration, not a broad
implementation handoff. After approval, activate child 1 first. Child ownership
and dependencies below remain authoritative even if task-tree metadata changes.
Default execution is sequential, one writer per checkout. Each active-child
dispatch begins with `Active task: <task.py current>`; load child PRD/design/plan
and curated manifests. A child cannot expand scope or commit on its own.

## 1. Gates and Ordered Work

- [x] Inspect accepted architecture, current code/manifests/config and backend specs.
- [x] Confirm B scope with user; research primary sources and record caveats.
- [x] Probe existing toolchain, baseline tests and disposable same-host BEAM peers.
- [x] Create parent/child planning artifacts with explicit ownership/dependencies.
- [ ] Obtain explicit user approval of this final plan; record approval.
- [ ] Start `10-16-operation-runtime`; implement and check child 1.
  Gate: non-AI submission, real multi-VM execution, local capacity/fault/uncertainty,
  bounded event/state handling and no automatic retry/replay.
- [ ] Start `10-16-harness-providers`; implement and check child 2.
  Gate: Harness independent tests, real HTTP adapter against local fixture,
  strict call validation, no retries/redirects, bounded response/read-only Tool.
- [ ] Start `10-16-agent-orchestration` only after 1 and 2 gates.
  Gate: complete model→parallel Tools→model loop through normal Runtime,
  delegation/peers/stop/loss/late reply tests, role and provider-readiness faults.
- [ ] Start `10-16-backend-release` only after 1–3 gates.
  Gate: CLI plus actual backend release closure/boot, automated three-node end-to-end
  suite and recorded cross-physical-host run; no claims based solely on peers.
- [ ] Perform full parent AC1–AC12 integration review; do not archive parent with
  missing required multi-host evidence or failing child gates.
- [ ] Update backend executable-contract specs where implementation added knowledge.
- [ ] Follow finish-work/commit process; preserve unrelated staged changes and do
  not let worker subagents commit. Record actual checks and remaining limitations.

## 2. Deliverable/Writer Boundaries

| Child | Owns | Must not absorb |
| --- | --- | --- |
| 1 operation-runtime | Actions/Runtime source, manifests and tests; generic distributed fixtures | Harness/Agent semantics, Node product policy, provider dependencies |
| 2 harness-providers | Harness source/manifest/tests; narrowly scoped dependency lock additions | operation structs/behaviours, Agent loop, Node scheduling |
| 3 agent-orchestration | Agent/Node source/manifests/tests; explicit role/provider wiring | HTTP client internals, generic scheduler duplication, UI |
| 4 backend-release | root release/config, rel/scripts/runbook/README, CLI module, Node integration tests | new loop policy/providers/UI; broad unrelated refactoring |
| parent | these planning artifacts, requirements traceability and final review | unbounded product implementation |

Child 2 owns provider dependency lock changes. If another child needs a new
third-party dependency, pause and justify it; prefer existing OTP facilities.
A child touching a shared root file must declare the narrow reason first.
Minimal Web boot-guard/config changes are allowed only in child 4 if required to
preserve production secret validation, not for product pages or CSP relaxation.

## 3. Validation Commands

Use available toolchain and run actual checks; these are prospective gates except
for the separately recorded baseline. Read child plans for focused commands.

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
mix sobelow
mix xref graph --format cycles
git diff --check
git diff --cached --check
MIX_ENV=prod mix release beamlet_node
```

Run focused tests from each child application (shared umbrella build paths).
Introduce a `:distributed` ExUnit tag; run explicitly and record that tests
executed rather than were excluded:

```bash
elixir --sname beamlet_tests --cookie <isolated-test-cookie> -S mix test --only distributed
```

Distributed fixtures must use unique peer names/cookies, bounded startup, low peer
scheduler counts, explicit cleanup via on_exit/after, and message barriers instead
of timing-dependent sleeps. Use stdio alternative control to inspect/stop isolated
peers without reconnecting the application distribution channel during loss tests.
One-host peer success is not physical-machine acceptance.

For independent package boundaries, inspect each app's runtime dependency closure
and source imports, not just which umbrella apps happen to compile. Inspect release
`lib/`, `.rel` and `.app` dependencies, then boot a copied release outside the
source checkout with `SECRET_KEY_BASE` and model credentials unset on authority.
Test explicit enabled-Web production missing-secret failure separately.

HTTP tests include local socket/fixture server for actual wire/cancellation/size
behavior; Req.Test alone cannot prove transport bounds/TLS. Do not call a paid
provider without credentials/spending approval. Multi-host run requires accessible
hosts supplied by operator/environment; record missing access as a blocked gate.

## 4. Required Evidence and Review

Each child leaves a verification record: changed paths, contract/API summary,
commands+outcomes, fault-test coverage, diagnostics coverage/missing tooling,
dependency graph and safe handoff to consumers. Probe changed files with active
LSP diagnostics when supported; an empty cache or unavailable server is not a pass.
Investigate warnings in changed code; record existing dependency warnings separately.

Parent reviews AC mapping, result/attempt identity, no-retry ambiguity, readiness,
provider isolation, nonblocking orchestration, event credit/limits, file confinement
caveats, and cleanup/no business replay under infrastructure failure.

Required external records distinguish:
1. deterministic local tests;
2. same-host independent BEAM nodes;
3. actual distinct physical hosts;
4. optional operator-authorized live upstream provider.

Only mark what actually ran. Capture no secrets/prompt/file contents in shared logs.

## 5. Baseline and Risks

Parent baseline on 2026-10-16: `mix compile --warnings-as-errors && mix test`
exited 0; 17 tests passed. Gettext deprecation/type warnings and LiveDashboard's
optional Postgrex reference warning appeared during dependency compilation.
They are not newly introduced app warnings or evidence of future clean builds.
A controller and two disposable peers connected; every probe peer was stopped.
No provider request, release build or physical multi-host application test ran.

Pause at provider compatibility or unsupported tool schemas; do not silently widen
the wire protocol. Pause before real effects if no-retry/uncertainty tests fail.
Do not treat symlink checks as a sandbox or a read-only mount as protection against
backing-tree writers. API/ref state is in memory only; no recovery promises.

Working-tree/index entries were externally staged during research; neither parent
nor research worker should unstage/reset/re-stage unrelated work to compensate.
Use scoped diffs and preserve existing index contents. Do not commit automatically
while implementation approval is pending.
