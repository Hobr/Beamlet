# Web Management (Read-only)

## 1. Scope / Trigger

Use for the read-only management LiveViews, their bounded reads and diagnostics links.
Sources: apps/beamlet_web/lib/beamlet_web/live/{management_reads,management_live}.ex,
router.ex, and the workbench links/components. Management is discovery, not
administration: navigation is not authorization and no mutation exists. Browser/visual
verification was later executed in a real local browser (34/35 checks; the 390px viewport
is blocked by a Firefox500px minimum), as well as in-process LiveView tests.

## 2. Signatures

```elixir
{:ok, snapshot} = Beamlet.Web.ManagementReads.nodes()
scope = %{connected: [node], targets: [node], distributed: boolean, reads: [result], excluded: [node]}
{:ok, descriptors} = Beamlet.Web.Presets.describe()
```

Routes in the existing :browser pipeline: /admin/nodes, /admin/presets and
/admin/diagnostics (ManagementLive actions). The only reading event is "refresh"; every
other event is ignored by a catch-all.

## 3. Contracts

Nodes scope is the explicit local VM plus configured trusted allowed_nodes, resolved
through public Cluster/Node.observe only. Duplicate and local-inclusive allowlists
collapse; invalid allowlists return {:error, reason} instead of raising. One page read is
in flight at a time; the page deadline is 12s while Node keeps 32 targets/8 workers/5s/
1MiB. When local pushes the trusted scope past 32, the excess target is rendered as
unread/unknown ("scope partial") rather than silently dropped or read twice.

Each target shows connection (local / connected at entry / disconnected), configured
roles, registration readiness per service and a separate Runtime block with source,
coverage, per-report status (not_reported/fresh/stale), source-reported age, ready/
execution_ready, capabilities, environment IDs and available quantities only. Registered
readiness is not provider health; missing/stale reports are not death; totals and
utilization are unknown and available is advisory. Ages come from the source entry and
are never computed by subtracting another VM's monotonic clock.

Presets renders exactly Presets.describe/0, the same projection the creation form uses.
Known-absent facts are stated as such (empty list "none", nil environment "not
required", nil default authority "none configured") instead of "unknown". Private
binding/route/descriptor/value/target/settings/credentials/roots never reach the DOM;
there is no form or write path.

Diagnostics resolves an exact opaque handle through Handles.fetch/1 and subscribes via the
reviewed OwnedCall.observe/4; it renders the shared activity component with observe-only
controls disabled. Source turn/entry/activity/operation/attempt identities become opaque
hash labels; the activity query key only selects a current label, never decodes or
reconstructs history, and a stale key says so. Missing display clears the previous
display. Workbench exposes page-level and per-activity diagnostic links; a per-error deep
link is not implemented.

Reads happen in owned callers outside LiveView callbacks with a pending lock and
generation fencing. Failures keep the previous observation plus an action-specific reason
and an explicit "current facts unknown"; they never render a healthy empty page. No admin
mutation route/event (RPC, terminal, restart, connect, role switch, config write,
recovery), no tracing collector, log query, database, exporter or persistent diagnostics.
CSP nonce, CSRF, origin, escaping and dev-only dashboard/debugger gates are unchanged.

## 4. Validation & Error Matrix

| Condition | Behavior |
| --- | --- |
| Node not configured | Explicit unconfigured facts; not an empty healthy cluster |
| Configured target disconnected | Listed as disconnected plus failures[target]=unavailable, complete:false |
| No report / retained stale report | not_reported / stale with age; neither implies death |
| Invalid allowed_nodes | Explicit read failure with retained last observation |
| Scope exceeds 32 with local | Excess target shown unread/unknown |
| Duplicate or local-inclusive allowlist | Deduplicated; no second read, no phantom entry |
| Repeated refresh / stale generation | Pending lock; non-current generation/action/Ref ignored |
| Page owner unmount | Owned guardian and worker observed DOWN; source work not cancelled |
| Invalid/stale handle or activity key | Explicit stale/unknown; no reconstruction |
| Forged management event | Ignored |

## 5. Good / Base / Bad Cases

Good: read nodes once, separate connection/readiness/report freshness, and keep the last
observation with its receipt time after failure. Base: an unconfigured local VM shows
explicit not-configured facts. Bad: render "0 nodes"/"healthy" from an unread scope, sum
available capacity as a total, infer death from a missing report, or expose bindings.

## 6. Tests Required

Cover authority-only, executor-only, combined, unconfigured and service-loss trees;
disconnected/partial scope; not_reported/fresh/stale rendering from named public-shape
fixtures (clearly distinguished from core admission tests); preset parity with
describe/0, private-config/binding/form refutations and known-absent wording; diagnostics
exact handle, same-ID replacement, stale activity key, Agent survival, observe-only forged
commands and no #PID leakage; zero Agent/Runtime/Node.connect calls on mount, refresh and
forged events; duplicate and local-inclusive allowlists; invalid scope retaining the last
observation; duplicate slow refresh, stale generation and actual guardian DOWN while the
source stays suspended. Escaping is asserted for untrusted report/catalogue text. Keep one
real named peer test for connected roles, source timeout and disconnect.

Independent review passed focused 15, Web 58 ordinary/5 excluded, umbrella 281/34 excluded
and 25 actual named, plus format/warning-fatal compile/strict Credo/Sobelow/existing-PLT
Dialyzer (no refresh). A real-browser pass also confirmed the three admin pages render real
roles/readiness/freshness/available-only capacity, preset parity without private values,
diagnostics with retained context and observe-only controls, escaped hostile text and no
#PID leakage; see the parent task's research/browser-walkthrough.md. The implementer's
/tmp/management-final artifacts were absent in the
reviewer environment, so those earlier counts are historical and unverified there; do not
extrapolate either set to a final umbrella claim. Same-host named peers are not physical/
provider proof; LSP unavailability is inconclusive.

## 7. Wrong vs Correct

Wrong: query every Node.list(:connected) entry, mutate config from the page, or treat a
partial read as a complete cluster inventory. Correct: read the trusted configured scope
through public APIs, show the excess and failures explicitly, and keep management
read-only with navigation clearly not authorization.
