# Current capabilities and implementation seams

Evidence baseline: HEAD `e7f59d1` (2026-10-17), inspected during planning. This file distinguishes existing behavior from proposed contracts. No application code or test was changed/executed for this research.

## Existing Web

- `apps/beamlet_web/mix.exs:39`: Phoenix 1.8, LiveView 1.2, Tailwind/DaisyUI, esbuild, Gettext and test-only LazyHTML. No sibling runtime dependencies, Ecto or adapter.
- `apps/beamlet_web/lib/beamlet_web/application.ex`: Telemetry, PubSub, Endpoint only; no Node role composition.
- `apps/beamlet_web/lib/beamlet_web/router.ex`: only product route GET / to scaffold controller; browser session, CSRF and nonce CSP. Dev dashboard remains dev-only.
- `apps/beamlet_web/lib/beamlet_web.ex:51`: LiveView/LiveComponent setup already exists. `assets/js/app.js` starts LiveSocket; no separate SPA is needed.
- `apps/beamlet_web/test/beamlet_web/controllers/page_controller_test.exs`: replace scaffold copy assertion when changing homepage, preserve security header and fresh 16-byte nonce assertions.
- `config/dev.exs`: endpoint binds loopback; no identity/authentication system exists. Protect nonlocal exposure through deployment controls; admin navigation is not an authorization boundary.

## Existing Agent/Node

- `apps/beamlet_agent/lib/beamlet/agent.ex:9`: explicit start, input, snapshot, subscribe/ack/unsubscribe, stop and close; public list/lookup are present. Commands are bounded but creation/input are separate, potentially uncertain distributed actions. Do not retry on lost acknowledgements.
- `apps/beamlet_agent/lib/beamlet/agent/server.ex:32`: already retains bounded in-memory neutral model context, pending work and children. This is not a durable record. Options currently accept only id/model/tools/catalogue/delegator; no title/preset metadata or system-prompt option.
- `apps/beamlet_agent/lib/beamlet/agent/server.ex:210`: input accepts one turn at a time; stop preserves Agent but requests best-effort work cleanup. One immutable model binding per Agent.
- `apps/beamlet_agent/lib/beamlet/agent/server.ex:767`: snapshot includes only ref/turn/terminal_turn/status/steps/final/progress. It does NOT expose a conversation, complete tool activity timeline or executor placement. Credit coalescing explicitly loses intermediate observations. A Web-only accumulator cannot create a complete record.
- `apps/beamlet_agent/lib/beamlet/agent/discovery.ex`: identity descriptors have exactly authority/id/pid, no credentials/binding/history. Lookup descriptor rejects PID replacement; actual Ref includes incarnation. Preserve the identity island and finite read/erpc isolation, no new discovery endpoint.
- `apps/beamlet_node/lib/beamlet/node/agents.ex:15`: at most32 explicit targets,8 concurrent,5s total query budget,1MiB envelope; complete/failures semantics cover the requested set only.
- `apps/beamlet_node/lib/beamlet/node.ex:12`: explicit supervisor supports seven role subsets; profile/catalogue accessors exist, but no public sanitized role/status overview. One Node tree per VM. Never enable CLI/daemon and Web-owned Node simultaneously.
- `apps/beamlet_node/lib/beamlet/node/cluster.ex`: only trusted bounded node names can be resolved; connected filtering does not create connections. Local non-distributed Web needs an explicit local path rather than pretending Cluster.connected includes nonode@nohost.

## Existing Runtime/Tools

- `apps/beamlet_runtime/lib/beamlet/runtime.ex`: public submit/status/cancel/ack, no product node-observation facade.
- `apps/beamlet_runtime/lib/beamlet/runtime/directory.ex:8`: private snapshots API returns fresh reports without receipt ages. Web must not read this private server or `:sys.get_state` directly. Add owner-projected public reads for report ages/status if needed.
- `apps/beamlet_runtime/lib/beamlet/runtime/report.ex`: readiness, capabilities, environments and AVAILABLE pool quantities; no pool totals, physical utilization guarantees or full cluster role inventory. Do not invent x/total capacity, CPU charts or cross-VM timestamp comparisons.
- `.trellis/spec/backend/harness-providers.md`: implemented native WorkspaceRead is a trusted-root read tool, not arbitrary shell/write/sandbox support. Preset examples must advertise configured tools only. Tool settings/roots stay executor-local; catalogue is neutral data.
- Model request is messages/catalogue, HTTP adapter is stream=false. UI can show observable progress, not fabricate token streaming, reasoning or model delegation tools that do not exist.

## Proposed, not currently implemented

1. Optional bounded Agent display projection through the same snapshot/credit mechanism; safe metadata for Web-created instances. No second history store, replay endpoint or durable protocol.
2. Public owner-projected Runtime/Node observations with explicit readiness/unknown/partial and local age semantics.
3. Trusted Web preset and option catalogues, opt-in Node host and server-side creation resolver, opaque ephemeral browser handles.
4. LiveView workbench and read-only admin views consuming the shared contracts.

Detailed proposed contracts and limits are in ../design.md. Durable action, storage, system-prompt presets, richer write/shell tools and Web release packaging remain outside this task.
