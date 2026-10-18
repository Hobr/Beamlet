# Durable reference fork, history and offline trace

## 1. Scope / Trigger

Use when changing Agent/Storage inheritance, source validation, history cursors,
TraceSnapshot/TraceExport/TraceVerifier, or the durable Server e2e fixture. The
[Agent README](../../../apps/beamlet_agent/README.md) is the detailed API inventory.
A/B/C still own preparation/acceptance/consumption/no-replay semantics. This spec
does not authorize another transcript, graph store, retries or old-format path.

## 2. Signatures

```elixir
Agent.fork(%{repo: repo, agent_id: id, source: %{environment: :confirmed_stopped}},
  through_seq, current_source_version, command_uuid)
# {:ok, %{agent_id:, locator:, version: 0, generation: 0, through_seq: 3,
#         source: %{agent_id:, through_seq:}, risk: nil | "unconfirmed"}}
Agent.history(locator, %{view: :facts, limit: 100}, next_cursor)
TraceExport.begin(repo, locator) # fixed Agent + Operation snapshots
TraceExport.write(fixed, dir: fresh_directory, page: 100, redaction: :none)
TraceExport.verify(directory) # offline, execution_authority="none"
```

## 3. Contracts

Fork appends child created/forked/context.inherited only. It validates the selected
reference timeline against source events transactionally, with source position
and PostgreSQL shared row lock; source rows never change. Input artifacts retain
original event/Agent identity and digest; accepted-output refs retain original
Operation ownership, request digest and accepted digest. The manifest is flat
(128 ordered sources/1024 closure refs), not a recursive parent locator. Replay
reads child events, artifacts and Operation streams, never parent event prefixes.
Source content is retained without GC. New control owns no old pending work,
consumption/dedupe, commands, attempts or provider sessions. Inherited usage is not
new work or billing. Command UUID is the stable child UUID; exact replay returns
the original response after either Agent advances; changed parameters conflict.

Default environment risk is unconfirmed even when idle. Read/export/restore grant
no execution. Source confirmation is an explicit operator assertion, not remote
termination proof; a recorded continue decision `%{"risk" => "accepted"}` clears
a pending risk. Old receipts cannot advance new control or replace accepted output.

Facts/turn cursors retain fixed through_seq. Context reduces refs at as_of_seq;
step/tool output is included only if consumed at that cutoff. Evidence is separately
labeled as an Operation snapshot. Export fixes a per-Operation high-water vector,
full request/accepted/evidence/input/definition/artifact closure before writing
pages, with32 MiB capture budget/1024 Operations/5s reference deadline. Receipt
evidence is captured with each Operation, checked against its attempt/executor and
content digest, and traversed for artifacts. The evidence reader probes one row
beyond its32-row limit and refuses overflow rather than calling a truncated trace
complete. Offline verification binds performed references and input/result sources
to the original owner; inherited sources retain their source ownership without
reading parent events. Malformed inherited entries are rejected by the pure decoder
before reference traversal. It exports
supported history rather than optional caches. Missing/corrupt content is explicit;
redaction removes all bodies/artifacts and marks nonrestorable. Nonempty output
directories refuse, preventing stale plaintext in redacted packages. File hashes
are integrity checks, not signatures. No graph UI or import authority exists.

## 4. Validation & Error Matrix

| Boundary | Required result |
| --- | --- |
| Registered source | source_not_frozen, no writes |
| Pending/block/incomplete call pairs | unsafe_position, no writes |
| Bad source position/membership or changed command | conflict |
| Missing/corrupt content | reconstruction blocks; export missing + incomplete |
| Risk without decision | blocked/environment_risk_unconfirmed |
| Repeated risk acceptance | blocked/no_pending_risk |
| Oversize native context or manifest/capture | explicit limit, never truncation |
| Nonempty export directory | export_directory_not_empty |
| Malformed/rehash-tampered package | safe validation error |

## 5. Good / Base / Bad Cases

Good: fork complete content refs, retire the parent event log in a test, and replay
and re-export the child without a provider. Base: inspect input-only control
without Runtime. Bad: use a hash as prompt text, recursively replay parents,
count inherited tokens as new usage, or overwrite an existing package to redact it.

## 6. Tests Required

Run fork_test/history_export_test on SQLite and the isolated PostgreSQL adapter
(`BEAMLET_AGENT_TEST_ADAPTER=postgres` plus Storage fixture variables). Assert
unchanged source rows, no cloned execution/dedupe, safe replay/changed-command
refusal, retired-parent/chained fork, default risk/stale decision/exact acceptance,
late output isolation, missing content, fixed history/Operation cutoffs across
appends/acceptance, complete long-history paging, output digests beyond file hashes,
large artifacts, redaction and safe malformed packages. Preserve C replay/cache,
accepted-only, actual helper DOWN and named fault-window/call-count tests.
Run the independent-process durable-e2e and fresh copied/named host releases.
Single-link observation partition fixtures use explicit hidden peers and assert
the unaffected peer remains connected: OTP global can break other edges of a
visible triangle to prevent overlapping partitions. Do not replace visible
routing/release tests or weaken missing-target assertions to hide this behavior.

## 7. Wrong vs Correct

Wrong: use Agent seq as an Operation acceptance timestamp, or let later acceptance
change a previously begun export. Correct: freeze the Operation snapshot vector
before writing; ordinary Agent history includes consumed outputs at its own cutoff
and labels independent evidence separately. Wrong: assume a redacted manifest
removes old bytes. Correct: require a fresh empty output directory.
