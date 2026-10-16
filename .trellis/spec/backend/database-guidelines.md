# State and Persistence

## Current Scope: No Database Layer

Beamlet has no implemented database, ORM, Repo, schemas, migrations, queries, or
transactions. None of `apps/*/mix.exs` declares Ecto or a database adapter, and
`mix.lock` has no resolved Ecto package entry. LiveDashboard's lock metadata lists
optional Ecto integrations, but those are not selected as resolved packages.
Runtime owns ephemeral process state: Directory snapshots, coordinator terminal
retention, and gateway admission accounting/tombstones. None survives infrastructure
restart. Node composes configured roles (empty by default). Agent retains bounded
context/turn/subscriber/peer state; Resources retains infrastructure PID inventories
until DOWN, with VM-local restart fencing and no business replay state. There is no
durable Agent/Operation history. See [Agent and Node](./agent-orchestration.md). See [Operation Runtime](./operation-runtime.md).

Accordingly, there are no established table names, migration commands, transaction
patterns, or repository test fixtures to follow. Storage work needs an explicit
task-level contract rather than an invented Ecto convention. Runtime refs address
live coordinators; status is unavailable after expiry or shared infrastructure loss.
Do not turn retained Results/tombstones into replay or durable deduplication promises.

## Existing State Boundaries

`apps/beamlet_web/lib/beamlet_web/endpoint.ex` configures a cookie session:

```elixir
@session_options [
  store: :cookie,
  key: "_beamlet_web_key",
  signing_salt: "HwX5hC6W",
  same_site: "Lax"
]
```

The endpoint passes these options to both LiveView socket transports and
`Plug.Session`. As the source comment states, the session is **signed, not
encrypted**: clients can read its contents. Keep sensitive server-only data out
of it. The browser pipeline fetches the session; this is not a server-side
persistence service (`apps/beamlet_web/lib/beamlet_web/router.ex`).

Other current state is boundary-local: the router assigns a fresh CSP nonce per
request, and `apps/beamlet_web/lib/beamlet_web/components/layouts/root.html.heex`
stores a theme preference in browser `localStorage`. Neither is Agent storage.
`config/runtime.exs` supplies production `SECRET_KEY_BASE` from the environment;
`config/dev.exs` and `config/test.exs` have local-only defaults.

## Misleading Scaffolding to Check

`apps/beamlet_web/test/support/conn_case.ex` mentions SQL sandboxing in its
generated module documentation, but its actual setup only returns
`{:ok, conn: Phoenix.ConnTest.build_conn()}`. No SQL sandbox is configured.
`apps/beamlet_web/lib/beamlet_web/components/core_components.ex` accepts
`Phoenix.HTML.FormField` and translates error tuples; that UI helper is not proof
of Ecto changesets or persisted models. `priv/` currently contains static and
translation resources, not database migrations.

When changing state behavior, trace its real owner first and specify lifetime,
visibility, and failure behavior in the task. Do not add database setup or
sandbox calls to existing connection tests on the strength of generated comments.
