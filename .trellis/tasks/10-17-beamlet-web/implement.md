# Beamlet Web — Execution Plan

## Gate 0: planning review

- [x] User approved product direction, creation of tasks, and explicit no-database/no-persistence scope.
- [x] Inspect existing Web, Agent, Node, Runtime, security/test contracts; record research/current-capabilities.md.
- [x] Split independent deliverables; curate per-task spec/research manifests.
- [x] User reviewed the final planning summary and replied “批准” in a subsequent message (2026-10-17); implementation is authorized in child-task order.
- [x] Started `10-17-web-observation` as the current in_progress child (2026-10-17); parent remains integration owner, not the default implementation target.

## Task map and order

| Order | Child | Deliverable | Prerequisite |
| --- | --- | --- | --- |
| 1 | `../10-17-web-observation` | Additive bounded Agent display and public Node/Runtime observations | None; preserve current core contracts |
| 2 | `../10-17-web-presets` | Opt-in Web host, trusted catalogues/resolution and safe create adapter | Observation metadata/read contracts settled first |
| 3 | `../10-17-web-workbench` | Task-first creation, discover/attach, multi-turn activity UI and controls | Both first children accepted |
| 4 | `../10-17-web-management` | Read-only nodes/presets/diagnostics, shared inspector | Observation + presets, then workbench components |
| Final | Parent | Cross-child validation and implemented-spec synchronization | All child acceptance evidence |

Parent-child tree does not enforce dependencies. Execute in this order to avoid concurrent edits to Agent/Node APIs and shared Web adapters/layouts. Each child owns its source tests and evidence; parent owns complete user journeys. Re-review artifacts if a contract/scope must change materially.

## Step 1: shared contracts

- [x] Preserve default Agent snapshot/subscription and identity discovery, add opt-in display with bounded source projection and safe optional instance metadata.
- [x] Add public Runtime/Node reads; finite erpc aggregation, local-age reporting, no new endpoint or credential/config dump.
- [x] Tests cover byte/count limits, truncation, stalled readers, sink loss, legacy defaults, partial queries, roles and no scheduling side effects.
- [x] Record actual ordinary/named test counts and update relevant implemented core specs after review.

Rollback: disable/remove additive observation calls; do not change default business lifecycle, model context or release configuration to make UI work.

## Step 2: host and presets

- [x] Add child-owned Web runtime dependencies; explicit disabled-by-default host and one-shot configured peers.
- [x] Implement bounded startup catalogues and browser-safe projection / server resolver; model credentials never enter form/session/URL/logs.
- [x] Effective tool routes and catalogue agree; forged params cannot broaden configured environments or execute arbitrary modules.
- [x] Create-then-input result variants preserve live instance on known input failure and uncertainty on lost acknowledgement.
- [x] Add bounded opaque handle mapping, no transcript or saved-draft store. Provide deterministic opt-in example with no paid calls.
- [x] Host/catalogue/adapter tests pass independently of final UI.

Rollback: disabled Web host preserves existing endpoint; restore matching startup config. Existing Agent instances are never rewritten when presets change.

## Step 3: workbench

- [x] Replace scaffold homepage, preserving security regression tests; implement shell, task-first form, preset edits/reset/risk summary and conditional environments.
- [x] Discover exact live identities with partial results and safe handles; lookup before attach, reject replacement/stale instances.
- [x] Consume display snapshots as replaceable projections; ack from sink and bound command/read helpers. Do not turn coalesced updates into a fake event log.
- [x] Render turn boundaries, current tool/child cards, inspection, truncation, unavailable history, responsive layouts and scroll-follow behavior.
- [x] Stop vs close vs leave; running drafts are not queued; multi-tab/CLI conflicts and uncertain outcomes visible.
- [x] LiveView/ConnCase tests recorded for creation, discovery, multi-turn activity, stop/close/leave, stale identity and security. A real browser walkthrough was executed later (34 pass/1 blocked/0 fail, no product defect); the blocked item is the390px viewport, and console logs/browser busy conflicts/reconnect remain unverified. See research/browser-walkthrough.md.

Rollback: gate routes/entrypoint back to unconfigured shell; unsubscribe owned observation only. Never close Agents as navigation cleanup.

## Step 4: management

- [x] Nodes show connection/readiness/report age/capability/environment/AVAILABLE capacity without inventing totals or health proofs.
- [x] Presets reflect trusted startup configuration; management has no mutation routes or raw config/credential dump.
- [x] Diagnostics reuse safe Agent activity and correlation; absent facts show unknown, not fabricated traces.
- [x] Test unavailable/partial/stale states, sanitization, link handling and preserved dev-only diagnostic gates.

Rollback: remove admin navigation/routes; workbench and shared business APIs remain independent.

## Parent integration acceptance

- [x] Deterministic local all-role Web: choose/edit preset → create + first input → tool observation/result → next turn → stop/close distinctions.
- [x] Web interaction-only + named remote daemon roles: use existing shared contracts and real peer VMs; CLI-created Agent is discoverable/observable, Web-created Agent remains alive after observer exit and can be attached by CLI/another browser.
- [x] ID reuse/authority disconnect/partial discovery/slow sink; old Ref/handle never silently rebinds and no business retry/fallback.
- [x] Known create success/input rejection and ambiguous create/input return produce different UI, no duplicate dispatch.
- [x] Web restart + remote surviving Agent uses rediscovery; embedded authority loss is not misrepresented as recoverable. No history replay or persisted UI record.
- [x] Inspect dependency/config diff: no Ecto/adapter/Repo/migrations/database, no transcript file/browser storage, no daemon/CLI coupling, no new Web release requirement.
- [x] All code/spec changes receive full-scope check; update implemented backend specs and Web guidance where justified.

## Validation commands (planned, not executed by task creation)

Use installed umbrella Elixir/OTP toolchain; use `nix develop` if unavailable. Build/test alone does not prove manual visual acceptance. Browser verification was later requested and executed: a real geckodriver+Firefox walkthrough passed34/35 checks with no product defect (390px viewport blocked by a Firefox500px clamp; console-log API405; browser busy conflict unproduced). See research/browser-walkthrough.md; do not claim the blocked or unlisted items.

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test apps/beamlet_agent/test apps/beamlet_runtime/test apps/beamlet_node/test
mix test apps/beamlet_web/test
mix test
mix credo --strict
mix dialyzer
mix sobelow
mix tailwind beamlet_web && mix esbuild beamlet_web
mix tailwind beamlet_web --minify && mix esbuild beamlet_web --minify && mix phx.digest
# child-dir form (cd apps/beamlet_web && mix assets.build) is blocked by an umbrella :only mismatch
git diff --check
```

Named distributed regressions use a secure temporary cookie supplied privately, not printed in evidence. Example after child fixtures exist:

```bash
ERL_FLAGS='+S 2:2' elixir --sname beamlet_web_check --cookie "$BEAMLET_TEST_COOKIE" \
  -S mix test apps/beamlet_node/test apps/beamlet_web/test --include distributed
```

Tests must preserve exclusions in ordinary helpers and use isolated peers/ports. Do not infer actual named execution from an empty selected suite; record executed counts. If backend manifest/config/shared Node changes affect release closures, additionally run existing deployment smoke scripts as documented in scripts/deployment/README.md; paid APIs and physical multi-host checks are not required. Pre-commit all-files is a final repository gate where available; distinguish benchmark/SBoM/tool prerequisites from product test evidence.

For planning-only changes: validate all task JSON/JSONL, real manifest paths, parent-child links, Markdown links and whitespace. No application tests need run solely for these documents. Preserve failures/skips and diagnostic coverage limitations; empty LSP cache is not proof of clean code.

## Finish discipline

After actual implementation: full-scope check → implemented-spec updates → user-confirmed commit plan → task archive/journal. No commit or archive merely because these planning artifacts exist.
