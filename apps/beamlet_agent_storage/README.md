# Agent Storage

`Beamlet.Agent.Storage` owns Agent persistence and reference projections. This is
an opt-in library with no Application callback; loading it starts no Repo. It
depends on Actions Storage and foundation Storage, with no dependency on Agent,
Core, Runtime, Node or product hosts.

Explicitly initialize a new dataset with `Beamlet.Storage.Dataset.initialize/2`,
using `Beamlet.Agent.Storage.Profiles.authority/0` as `:descriptor`. Open existing
datasets using `Dataset.open/2`; opening never installs or repairs tables. The
profile is `agent-authority`, container format 3, with foundation1/migration1,
Actions authority1/migration100 and Agent1/migration300. Existing formats refuse.
`SQLiteAuthorityRepo` and `PostgresAuthorityRepo` are explicit neutral Repo instances.
SQLite requires distinct absolute `:database` and `:peer_database` paths; both
adapters require the actual dataset UUID as `:dataset_id`.

`AgentRecords` exposes create_agent, accept_input, prepare_operations,
consume_results, checkpoint, advance, restore, fork, fetch, history_page and
command_response (all accept Repo plus attributes/identity). Commands persist the
original response; same command and request replays it after later transitions.
Preparation validates Agent sources, artifacts, current turn and generation,
then calls Actions' transaction participant and writes Agent associations and
events inside one transaction. Any failed batch member rolls back every table.

Agent tables are agents, agent_events, checkpoints, commands and agent_operations.
The association contains owner/turn/step/role/ordinal/tool call, generation,
preparation sequence and ordered sources. `Schema.Operation` is a read projection
through the Agent-owned `agent_operation_projections` view, joining associations
to neutral Actions Operations. Writes to Operations use Actions Storage APIs;
writes to association eligibility use Agent Storage. `OperationRecords.fetch/2`
returns string-key operation and attempt maps; `History.operation_event/3` projects
an Actions event with a scope_id for trace readers. Agent event reads never mix
Actions events into the Agent log.

Creation and fork create distinct opaque dispatch scopes. Restore locks Agent,
then rotates scope in the same generation transaction. Explicit continuation
adopts accepted output by updating only association eligibility. Pending prepared
work uses Actions reauthorization in the same transaction; claimed unresolved work
refuses. Fetch the refreshed Operation lock_version and dispatch scope/epoch after
continuation; the original command response remains unchanged. Agent's Runtime
adapter supplies this binding to Persistence. Ordered sources and description
bytes remain unchanged. Lock order is Agent, scope, Operation.

History, inheritance, codec limits, Agent event vocabulary and body-free control
policy live here. Checkpoints are optional caches. Loader and offline trace
verification remain in Agent, preserving fixed high waters and source/digest
validation. Forks store bounded flat references; no Operations or attempts clone.

Tests own isolated SQLite and PostgreSQL fixtures. Set `BEAMLET_PG_SOCKET_DIR`,
`BEAMLET_PG_PORT`, and `BEAMLET_PG_USER` to a private disposable cluster for the
PostgreSQL contracts. Agent's durable integration suite chooses PostgreSQL with
`BEAMLET_AGENT_TEST_ADAPTER=postgres`. Neither fixture uses a business dataset.
