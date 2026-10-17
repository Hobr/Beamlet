# Live Agent workbench

The workbench uses the opt-in host and trusted catalogues described in [HOST.md](HOST.md).
Ordinary startup remains unconfigured. Open `/` for task entry and discovery,
`/agents/new` for expanded options, or an opaque `/agents/:handle` to inspect an
exact live incarnation. Selecting a preset applies defaults; adjustments and reset
are disposable and apply only to the new instance. Environment choices appear
only for capabilities that require them. Missing options disable creation or
produce a safe rejection, without provider probing or fallback.

Creation, initial input and navigation are separate outcomes. The Web-owned caller
has a 16-second UI deadline; other commands/reads have an 8-second budget. It reports
the generated identity before dispatch, then a confirmed Ref before initial input
and navigation. A deadline or caller death does not retract queued local admission
or cancel business effects. Unknown creation must be investigated using explicit
live discovery; there is no automatic resend or replacement. A confirmed instance
remains selected if input or navigation fails. Navigation is ephemeral, not an
ownership or authorization token. Backend busy/constraints remain authoritative.

Only the selected Agent is subscribed. The sink acknowledges after LiveView has
consumed each replacement snapshot; it never builds an event transcript. Switching
waits for the previous sink's cleanup before subscribing. Leaving unsubscribes or
removes the dead sink; it does not stop or close the Agent. Stop keeps the instance;
close requires a separate confirmation. Neither promises rollback of external
side effects. Drafts during active work are never queued. Child inspection defaults
to observation with command controls hidden.

The UI renders escaped plain text, source turn boundaries, current concurrent
activities and omission/truncation notices. A later snapshot replaces all display
state, including clearing it when display is absent. Turn and entry references
are converted to opaque correlation labels, never inspected as internal terms.
Configuration bindings, credentials, PID/Ref structures and executable settings
are never rendered. Current context is not complete history, a token stream,
reasoning, an archive or replay. No transcript is stored in browser storage,
a database or files. The scroll hook holds only DOM scroll state: readers above
the bottom receive a new-activity button rather than forced scrolling.

Web restart clears handles; rediscover remote Agents that still survive. A host
embedding authority/executor may lose its own Agents on restart. Retain CSP nonce,
CSRF and origin checks. Shared exposure still requires trusted-network or
operator-managed authentication and the relevant core authorization boundaries.

Browser UX was verified in a real local walkthrough (geckodriver 0.36.0 + Firefox 158 headless against an owned deterministic host):34 of35 checks passed with no product defect. Confirmed there: no horizontal overflow at1440px and at the narrowest attainable window (500x758 inner), conditional environment add/remove, preset switch/adjust/reset, Enter-submit creation, real model-tool-model activity with a second turn, live activity card, observe-only child inspector, retained scroll with a working new-activity button, visible focus stops with Enter activation, leave/rediscovers the same Agent, stop keeps the instance, and close requires confirmation. Not verified: a390px viewport (this Firefox build clamps windows to500 CSS px), browser console logs (driver returns405 for the log endpoints), busy/multi-observer rejection in a browser, touch, screen readers, colour contrast, text zoom and reconnect after a real network drop. See the parent task research/browser-walkthrough.md.

Same-host peer tests are not physical deployment or paid-provider evidence.
