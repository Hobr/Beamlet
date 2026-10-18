# Agent Core

`Beamlet.Agent.Core` is an independent library with no Application callback. Its
Reducer, Context and Decision modules compute from explicit data without starting
an Agent, Runtime, Repo or provider. Dependencies are Harness's pure neutral
validators and Jason. Harness's transitive Req dependency does not imply transport
calls from Core.

`Reducer.reduce/2` and `replay/2` consume normalized version-one events. Input
events require a transient `input_digest` supplied by the storage adapter using
the existing canonical encoder. The reducer stores only that reference digest;
it neither hashes bodies nor changes persisted event/checkpoint versions.
`Beamlet.Agent.Reducer` retains storage envelope/UUID/limit validation. Payload
nesting is checked from its own root (32), independently of event/replay wrappers.
Inherited entries require exact reference shapes, canonical identities/digests,
positive sequences and recorded evidence resolutions; verification reads remain
outside Core.

`Context.build(control, catalogue, materials)` returns the ordinary policy's
request, sources and policy metadata. Each material binds `source` to the exact
selected timeline occurrence and contains `input` or `operation`, with optional
`resolution`. Membership, order, completeness, operation identity and resolution
association are checked. Extra, missing, reordered or substituted materials fail.
Repeated occurrences explicitly selected by a timeline remain supported for the
existing exact-limit contract. Storage adapters verify digests, ownership,
inheritance closure and accepted/prepared linkage before supplying materials.
Stored model replies use their operation's historical catalogue; the final
request uses the current catalogue. `complete_boundary/1` checks tool pairing
without revalidating historical arguments against a new schema.

The adapter uses `Context.start/1`, `append/2`, `messages/1` and `finish/2` to
convert each verified occurrence before reading the next one. Append keeps reversed
messages and counts each encoded message once, including exact JSON list/comma
bytes. A conversion or overflow failure stops later reads. Completion and current
catalogue validation happen only after the last source; incomplete tool prefixes
are never validated as full requests. The batch APIs use the same accumulator.
Material wrappers do not consume a description or accepted Result's depth budget.

`Decision` classifies reply continuation, paused resume actions and safe fork
positions. Runtime adapters retain dispatch, transactions, owner retirement,
uncertainty checks and fixed prepared-request reuse.

From the umbrella root, pure coverage can run without starting applications:

```sh
mix test --no-start apps/beamlet_agent_core/test --seed 631927
```
