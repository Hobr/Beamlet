# Agent persistence and reference reads

Agent authority format-3 persistence uses `Reducer` (pure control), `Loader` (bounded,
fixed-sequence validation) and `ContextBuilder` (disposable native messages).
Original inputs belong to Agent events; complete model/Tool requests belong to neutral Actions Operations; ordered source
manifests and orchestration associations belong to Agent Storage; business outputs belong to immutable authority
accepted Results. Neither events nor checkpoints contain a second transcript.
See [Agent Storage](../beamlet_agent_storage/README.md) and [Runtime](../beamlet_runtime/README.md)
for transactional preparation, execution claims and evidence.

## Explicit creation and activation

```elixir
{:ok, durable} = Beamlet.Agent.Durable.open(repo, %{
  agent_id: agent_uuid, authority_id: dataset_uuid, command_id: command_uuid,
  definition: %{"version" => 1}
})
{:ok, durable} = Beamlet.Agent.Durable.with_runtime(durable, runtime)
# runtime: authority_repo, journal_repo, executor_id, executor_boot_id
{:ok, ref} = Beamlet.Agent.start(node(), id: agent_uuid, model: binding, durable: durable)
{:ok, turn} = Beamlet.Agent.input(ref, "hello", input_command_uuid)
```

Model credentials are supplied transiently in `binding`; never persist them in
definitions, descriptions or sources. Storage initialization is an operator action,
not part of Agent startup. The authority_id is the opened dataset's actual UUID.

`Durable.inspect(%{repo: repo, agent_id: uuid}, through_seq: seq)` reads only;
it needs no binding, provider, runtime, live parent or executor. Live
`Agent.restore(locator, expected_version, command_id)` requires a binding to build
a Server and activates paused, without dispatch. Explicit `Agent.continue/4`
validates a decision and only then consumes accepted work or first-dispatches
unclaimed prepared work. Claimed unresolved work cannot be sent again. A completed
restoration continues to idle without another model call. Missing dependencies,
corrupt history/content and unknown execution remain explicit blockers.

## Same-authority reference fork

```elixir
{:ok, fork} = Beamlet.Agent.fork(
  %{repo: repo, agent_id: source_uuid,
    source: %{environment: :confirmed_stopped}},
  through_seq, current_source_version, fork_command_uuid)
```

The selected committed position must have no pending/unconsumed work or blocker,
and must be await_input, await_model_result with complete call pairing, or completed.
A registered source refuses with source_not_frozen. Source version/generation and
reference membership are rechecked in the write transaction; PostgreSQL holds a
shared source lock. No source rows are changed. The command is idempotent and its
UUID is also the stable new Agent UUID. Its response has `agent_id`, `locator`,
`version`, `generation`, `through_seq`, `source` and `risk`.

The child has three initial events (created, forked, context.inherited), generation
and version zero, and paused/await_input control. It inherits no pending work,
consumption/command dedupe, provider session, attempts or execution entities.
`context.inherited` contains a direct ordered source list plus a flat closure:

- inherited_input: original event identity/sequence, source Agent, digest and an
  immutable authority-local JSON input artifact;
- inherited_result: original Operation/accepted digest/kind, immutable description
  digest, source Agent and any explicit uncertainty resolution.

Input content is materialized into shared digest-deduplicated artifacts in the fork
transaction. Operation/Result bodies remain owned by their original Operations.
A child and chained child replay their own events and this direct content only;
no parent event prefix, registry or recursive parent history is needed. All source
content remains retained (no automatic GC); deleting it blocks reconstruction.
Inherited outputs/usage are provenance, not new execution or new billing.

Omitted environment confirmation defaults to `risk: "unconfirmed"`, even for an
idle parent. Restore/read/export never grant execution. Continue with
`%{"risk" => "accepted"}` to record explicit risk acceptance, or `%{}` for a
confirmed-safe paused child; stale versions and repeated risk decisions refuse.
This is an operator assertion, not proof of remote termination or rollback.

## History and offline trace export

`Agent.history(locator, %{view: view}, cursor)` supports facts, turns, context,
steps, tools, evidence, decisions and provenance. Context is reduced at the requested
`:as_of_seq`, not taken from a message checkpoint. Facts/turn cursors carry their
fixed through_seq and keyset position; pass the returned `next_cursor` unchanged.
Evidence is explicitly an independent Operation snapshot, not an Agent-sequence
claim. Source lists provide causal/context edges; there is no graph UI or second
mutable authority graph.

`TraceExport.begin(repo, locator)` captures the Agent cutoff and the request,
accepted-output/evidence snapshots for the complete Operation source closure before
writing pages. `write(fixed, dir: fresh_directory)` writes a format-2 manifest,
events/inputs/operations/definition JSONL and referenced binary artifacts. Appends,
acceptances or receipts after capture cannot alter that package. Optional control
caches are deliberately unnecessary: supported events plus content are sufficient.
The package includes full logical requests, not hashes used as pretend bodies.

Each file has SHA-256 and count; request/accepted/source/artifact and receipt-content
digests are checked again offline by `TraceExport.verify/1`. Source references retain
their original ownership, and receipt rows bind to the captured attempt/executor.
Missing or corrupt referenced content is
listed in `missing` and makes `history_complete` false; it never silently restores.
`:drop_content` removes input/request/output/definition/evidence bodies and all
artifacts, marks every line and never claims restoration. Output directories must
be empty to prevent stale plaintext from surviving a redacted export. Verification
grants no import, execution or cryptographic authenticity against coordinated
rewriting of the entire package. Protect packages/backups as sensitive content.

Budgets: history at most100000 events/32 MiB; trace capture at most32 MiB total,
1024 Operations, at most32 receipt evidence rows per Operation and a5s reference
traversal; inherited manifest at most128 ordered
sources/1024 closure entries and existing command/codec caps. Native context remains
128 messages/1 MiB. Export pages1..500, page byte policy4096..4 MiB (oversized whole
records are marked). Wire limits and accepted/unknown/no-replay guarantees are
unchanged. Larger histories/closures refuse explicitly rather than truncate.

## Verification

From umbrella root run Agent tests normally, then with
`BEAMLET_AGENT_TEST_ADAPTER=postgres BEAMLET_PG_SOCKET_DIR=... BEAMLET_PG_PORT=...`.
The fixtures create/drop only their own new databases. Server's durable-e2e test
covers actual model→Tool→model, host restart, paused continuation and reference fork;
`scripts/deployment/durable-e2e.sh` repeats the phases in independent OS processes.
Named peer fault-window/call-count and release evidence are separate gates; no
physical-host, paid-provider or power-cut acceptance is implied.

## Pure business kernel

[Agent Core](../beamlet_agent_core/README.md) owns event semantics, ordered context
conversion and continuation decisions. This application's Reducer and
ContextBuilder remain storage adapters; Server/Durable retain process ownership,
preparation/acceptance/consumption transactions and execution. Core receives no
Repo, callback, credentials or live Runtime reference. Public Agent interfaces and
persisted event/reducer/checkpoint versions are unchanged.
