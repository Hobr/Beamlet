# Web Workbench

## 1. Scope / Trigger

Use for LiveView command ownership, discovery, Agent observation and shared inspectors.
Implemented sources: `apps/beamlet_web/lib/beamlet_web/live/{owned_call,workbench_commands,workbench_live}.ex`, adjacent HEEx, ObservationComponents and assets/js/app.js.
Source engineering independently reviewed. A real local browser walkthrough was executed later (geckodriver0.36.0+Firefox158 headless, deterministic host) and passed34/35 checks with no product defect; the one blocked item is the390px viewport (see §6).

## 2. Signatures

```elixir
# Phoenix browser pipeline
live "/", WorkbenchLive, :index
live "/agents/new", WorkbenchLive, :new
live "/agents/:handle", WorkbenchLive, :show
# Internal server-only helpers
pid = Beamlet.Web.OwnedCall.start(owner, tag, fun, timeout)
sink_guardian = Beamlet.Web.OwnedCall.observe(owner, tag, ref, previous)
Beamlet.Web.WorkbenchCommands.create(owner, tag, public_draft)
Beamlet.Web.WorkbenchCommands.discover()
```

## 3. Contracts

Task-first form uses only public Presets descriptions/drafts; reset replaces defaults,
modification applies only to new instances. Clear environment when no selected Tool
requires it. Keep resolution/binding credentials worker-local; private Ref/descriptor
can live in server memory but cannot be rendered/session/URL/browser payload.

Discovery explicitly lists local Agent identities and aggregates configured allowlisted
connected remote targets through Cluster, without connecting or silently truncating.
Local not_authority is a confirmed absence and does not make results incomplete;
other errors remain explicit. Completeness is for local plus configured connected
scope, not all configured/disconnected nodes. Browser entry keys select retained exact
descriptors, never decode PID/atoms. Opening rechecks incarnation through Handles.
One discovery read per generation; failed reads expose incomplete/unavailable state.

Blocking operations run outside LiveView callbacks. OwnedCall uses a guardian with
linked blocking worker and owner monitor; ordinary UI timeout8s, creation16s. It
observes actual worker EXIT before terminal delivery/retirement. Creation identity,
confirmed Ref and input milestones relay through the same guardian as terminal
feedback, preserving order. On timeout/owner death stop caller only; queued local
admission may still create an idle instance. Keep uncertain identity for explicit
discovery, never recreate/resend automatically. Confirmed Ref is retained before
input and independently of navigation errors. Pending commands lock duplicate events;
match generation, command and selected Ref before applying late outcomes.

Only selected Agent is subscribed. Observer guardian owns linked sink, monitors
LiveView owner and observes actual sink EXIT during cleanup. Replacement waits for
previous guardian DOWN before subscribing; previous-sink waiting happens in the new
sink so its guardian remains responsive to owner loss. Retirement requests unsubscribe,
then kills and observes sink after6s if needed. Agent is never closed as cleanup.
Sink itself calls subscribe/ack/unsubscribe. It forwards one display snapshot then
waits for LiveView consumption before ack; source max16 credits/coalescing remain.
Observation errors match generation and selected Ref. Agent/remote loss is unavailable,
not successful stop or closure.

Snapshots replace current display; absent display clears old content. Source turn/entry
references become opaque labels, never guessed from arrival order. Render retained
context/current concurrent activity, omissions/truncation and unknown placement;
no durable transcript, complete timeline, reasoning or token-stream claim. Child
inspector opens observe-only; event guard also prevents commands by default.
Backend busy is authoritative; draft during work is not a queue. Leave unsubscribes,
stop retains instance, close separately confirms. None proves external rollback.

Plain escaped HEEx renders untrusted text. Preserve nonce CSP/CSRF/origin/dev guards.
DOM-only scroll hook follows bottom only when already there, otherwise exposes new
activity action; browser evidence confirms scrollTop is preserved when the reader is
above the bottom and the affordance returns to the bottom. No localStorage transcript,
raw inspect/config dump, Ecto or history collector.

## 4. Validation & Error Matrix

| Condition | Behavior |
| --- | --- |
| Missing catalogue | Safe configuration unavailable before dispatch |
| Duplicate command/discovery | Pending lock, no overlapping dispatch |
| Stale descriptor/handle | Distinct safe stale/not-found feedback; explicit rediscovery |
| Partial/failed discovery | Explicit incomplete/failures, not false empty success |
| Creation/input deadline | Unknown feedback, preserve known identity/Ref, no retry |
| Hidden unneeded environment | Cleared before creation |
| Old generation/Ref response | Ignore; cannot repaint current display |
| Missing display | Clear previous display and state missing coverage |
| Sink/observer loss | Remove observation only; Agent survives |
| Child observe-only | Hide controls and reject command events |

## 5. Good / Base / Bad Cases

Good: create once, preserve separate outcomes, explicitly rediscover uncertainty.
Base: existing CLI-created Agent opens with unknown configuration provenance.
Bad: silent redispatch, fallback attachment after ID reuse, or stale display retained
when new projection omits it.

## 6. Tests Required

Preserve actual deterministic Model → two concurrent held Tools → Model and second
turn; exact external/remote instance opening, configured trust filtering, same-ID
replacement, partial/local-non-authority handling. Assert duplicate pending locks,
ordered milestones and actual worker/sink DOWN while target still suspended, late
idle creation after caller death, confirmed Ref under Handles failure, external
busy/stop/close/leave survival and child observe-only event guard. Exercise hidden
environment removal, stale observation errors and absent-display clearing, sink
backpressure, hostile text escaping, credential/root/config sentinel absence and
nonce/error-page regressions.

Parent integration additionally runs `all_role_journey_test.exs`: one enabled three-role Host
through WorkbenchLive only (preset edit/reset, create + first input, real Tool activity and
result, second turn, stop-then-survive, leave-then-survive, rediscovery, confirmed close)
and asserts all three roles are observed. Keep that journey passing when changing
component or command wiring.

Final independent source gates:43 ordinary/4 excluded;4 actual named/43 excluded;
format/warning-fatal compile/strict Credo/Sobelow/existing-PLT Dialyzer passed, no
refresh. Earlier261 umbrella/33 excluded predates repairs; no inferred final umbrella
count. Asset build/deploy passed before review; review changed no JS/HEEx.

Real-browser walkthrough (parent task research/browser-walkthrough.md):34 pass,1
blocked,0 fail at1440px and500x758px inner — no horizontal overflow, conditional
environment add/remove, preset switch/adjust/reset, create via Enter, real model→tool→
model plus second turn, live activity card, child inspector observe-only, retained
scroll with working new-activity button,19 visible focus stops, Enter activating a nav
link, leave/rediscover, stop-keeps-instance, close-confirm and close-end, all three admin
pages, escaped hostile script with no dialog and a CSP-blocked nonce-less inline script.
Blocked:390px viewport is unreachable because this Firefox build clamps windows to500
CSS px (four techniques tried);500px is a lower bound, not390px evidence. Geckodriver0.36.0
returns405 for the console-log endpoints, so console capture is unavailable and CSP was
proven in-page via securitypolicyviolation. Busy/multi-observer rejection was not
produced in the browser. Do not claim touch, screen-reader, contrast/zoom or reconnect
acceptance. Same-host peers are not physical/provider proof; LSP timeout is inconclusive.

## 7. Wrong vs Correct

Wrong: report cleanup after sending kill or let different senders race milestones
against terminal feedback. Correct: observe linked EXIT and relay feedback in one
sender order. Wrong: discover all connected nodes and take31. Correct: use configured
trust and explicit completeness scope without silent truncation.
