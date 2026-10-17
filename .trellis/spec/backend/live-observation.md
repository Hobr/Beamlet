# Live Observation

## 1. Scope / Trigger

Use for Agent display consumers, Runtime reports and Node management reads.
Sources: Agent.Display/Server, Runtime.Directory/Observation and Node.Observation/
Routes in their owning apps. These public additive reads require no Phoenix,
query service, transcript store, replay, recovery or business dispatch.

## 2. Signatures

```elixir
{:ok, snapshot} = Beamlet.Agent.snapshot(ref, view: :display)
:ok = Beamlet.Agent.subscribe(ref, self(), view: :display)
:ok = Beamlet.Agent.ack(ref, sequence) # subscribing sink itself
{:ok, reports} = Beamlet.Runtime.observation()
{:ok, local} = Beamlet.Node.observation()
{:ok, aggregate} = Beamlet.Node.observe([node()])
```

Agent.start accepts optional display_metadata. Original snapshot/1 and
subscribe/1,2 retain their seven-field base and existing envelope/credits.
Empty options select default view. Reads use existing5s command handling;
list/lookup identity isolation remains unchanged.

## 3. Contracts

### Agent display

Creation metadata is a plain atom-key map, default %{}, <=4096 serialized bytes.
Optional title/preset_id are nonempty valid UTF-8 <=128 bytes. Optional option_ids
is a plain map: model/environment/constraints are such public IDs; tools is a
proper list of <=64 distinct IDs. Unknown keys/structs/types/private config reject.
These trusted caller labels describe an instance; they do not independently
verify preset provenance, authorize capabilities or sanitize malicious echoes.

Normal snapshot.display keys: version:1, coverage:live_context, metadata, entries,
activities, omitted:%{entries:count,activities:count}, truncated:boolean, reasons.
Entries have source id/turn references, role/content/call_id/calls/truncated.
Calls contain neutral ID/name and bounded JSON-text arguments. IDs are stable
only within retained source context/incarnation; Server keeps id/turn annotations
alongside neutral messages, without copying transcript. Model requests are intact.

Activities have kind/id/turn/status/placement/truncated; observed operation/attempt,
tool name/arguments/result, child Ref/child_turn appear only when known.
Prepared sibling calls are not dispatched activity; admitting requires actual
current-turn owner. Pending Runtime Ref does not prove executor admission.
Placement is currently unknown. Terminal activity disappears; replacement snapshots
can lose intermediate activity through coalescing. Unsupported non-JSON child
content is marked result_omitted:unsupported_content, never inspected into text.

Limits: most recent32 entries,16 activities,8192 UTF-8 bytes per text/argument/result,
131072 serialized display bytes and conservative1048000-byte full snapshot envelope.
Trim oldest displayed entries, activities, then metadata under pressure; never
shrink base final/progress or mutate model context. Reasons include entry_limit,
activity_limit, field_limit, unsupported_content and snapshot_budget.
A compact %{version:1,coverage:live_context,truncated:true,reason:snapshot_budget}
can replace display; if even it cannot fit, valid base snapshot has no display.
Absence on a requested view means total omission: clear prior display.

Subscription envelope remains {:beamlet_agent,ref,sequence,{:snapshot,snapshot}}.
One view per sink, max32 sinks/16 outstanding each; ack from sink frees credit,
dirty updates coalesce. DOWN removes subscription only. Ref/incarnation and turn
fence identity; nothing is appended as durable event history. Escape text.

### Runtime reports

Runtime.observation returns {:ok,%{version:1,source:node,expiry_ms:integer,
reports:list,complete:boolean}}. Directory projects current unique pg members,
sorted by endpoint PID, max256; excess sets complete:false. Missing retained report:
%{node:node,status:not_reported,age_ms:unknown}. Received entry has exactly node,
status:fresh|stale, age_ms, ready, execution_ready, capabilities, environments,
available:%{pool=>nonnegative_integer}. Multiple endpoints can describe one node;
do not sum them or infer roles. Empty/missing reports do not prove node death.

Directory computes max(0, local monotonic now minus local receipt); fresh means
age<=expiry. source identifies receipt VM; entry.node identifies endpoint VM.
Never subtract remote monotonic clocks. Departure removes reports; no fabricated
stale history after removal. Full serialized {:ok,map}<=1000000 bytes, local read5s.
No leases, incarnation/endpoint/provider PIDs, settings, roots, credentials or raw
clock timestamps. Available capacity is advisory; totals/utilization unknown.

### Node facts and aggregation

Local exact keys: version:1,node,configured,roles,services,runtime.
Absent Node tree returns configured:false,roles:unknown,services:not_configured,
runtime:{:error,:not_configured}, even if standalone Runtime exists.
Configured roles come only from startup metadata; services has routes/runtime/
authority/executor with ready/unavailable/not_configured. Ready means required
registrations present, not responsive or provider health. Authority readiness
does not depend on executor reports. Tree identity is checked across reads;
replacement returns unavailable. Facts are eventual/non-atomic.

Node local read supports nonode@nohost explicitly. Routes and Directory nested
reads consume one source5s budget. runtime preserves Runtime {:ok,map}|{:error,reason}.
No complete startup configuration is copied into Routes.

observe accepts a proper list <=32 distinct trusted atoms excluding nil/true/false.
Caller resolves trust; API never atomizes text. Local node is eligible without
distribution; remotes must be connected at entry. No initial connection attempt;
OTP can reconnect after that precheck. Empty request succeeds.
Return {:ok,%{nodes:%{target=>observation},failures:%{target=>static_reason},
complete:boolean}}. A safe partial node observation may coexist with its Runtime
failure. Not configured is explicit successful data. Service unavailability/stale
reports do not alone imply incomplete reads; Runtime count incompleteness does.

At most8 requests, queued work shares one5s receive deadline. Serialized complete
{:ok,aggregate}<=1048576 bytes, reserving16384 for32 possible failures. Reject an
overflowing node as limit without truncating its facts. Outer timeout may discard
collected data and mark all targets timeout. Disposable linked tasks and correlated
OTP replies isolate caller loss/late replies; expiry observes local worker DOWN.
Delayed erpc entry starts a finite relative budget on its own VM, possibly after
caller abandonment. No instantaneous remote cancellation/mailbox retraction,
hard-real-time bound or hostile-peer RSS limit. Matching trusted builds required.

## 4. Validation & Error Matrix

| Condition | Result |
| --- | --- |
| Invalid display metadata | invalid_agent_options |
| Unsupported view options | invalid_command |
| Valid base with display pressure | truncated marker or absent display; base retained |
| Runtime reply overflow | error:limit |
| Directory/Routes missing or stalled | unavailable or timeout |
| Invalid/duplicate/improper/>32 targets | error:invalid_query wholly |
| Disconnected target | failures[target]=unavailable |
| Target deadline / aggregate overflow | timeout / limit, complete:false |
| No Node composition | successful configured:false facts |
| Runtime partial error/count coverage | safe node facts plus explicit failure |
| Missing report / retained expired receipt | not_reported / stale, neither means dead |

## 5. Good / Base / Bad Cases

Good: consume replacement display, ack from sink, separate readiness from report
freshness and read completeness. Base: CLI-created Agent has empty metadata;
interaction-only Node has no authority/executor services. Bad: infer complete
history, execution placement, zero capacity/death from missing reports, or preserve
old display when requested replacement omits it.

## 6. Tests Required

Agent display tests cover real multi-turn concurrent tools/child identity, unchanged
full model requests, exact metadata/UTF-8/text/aggregate/envelope bounds, mixed sinks,
credit/coalescing/DOWN and stale generations. Runtime tests cover not_reported/
fresh/stale/source age,256 count/full-byte overflow and zero operation dispatch.
Node tests cover absent/all seven role trees, readiness loss/restart, malformed
targets and distinct failure-key reserve pressure. Actual named peers cover remote
timeouts/late replies, helper DOWN before target resumes, caller loss and ten
delayed nodes proving8 concurrent reads with one5s budget. Synthetic projection
fixtures are not normal report admission proof. Same-host peers are not physical
deployment evidence.

## 7. Wrong vs Correct

Wrong: Web inspects private state, saves snapshots as a second transcript, guesses
turn boundaries from browser order or computes ages across VMs.
Correct: owners project finite public facts; consumers replace display and render
coverage/omissions, unknown readiness/capacity and partial failures explicitly.
