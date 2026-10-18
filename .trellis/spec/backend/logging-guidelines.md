# Logging and Telemetry

## Current Logging Surface

All six app manifests enable `:logger` in `extra_applications`. There are no
explicit `Logger.*` calls in application `lib/` source and no established domain
log-level matrix or custom log-event schema. Do not turn the sample logger
configuration comments in `config/config.exs` into active policy.

The active formatter there is:

```elixir
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
```

This is text logging with request metadata, not JSON structured logging.
`config/dev.exs`, `config/test.exs`, and `config/prod.exs` do not override the log
level or formatter. Keep additions compatible with the existing request-ID
surface rather than assuming fields such as Agent IDs or action IDs already exist.

`apps/beamlet_app_web/lib/beamlet_web/endpoint.ex` installs `Plug.RequestId` before
`Plug.Telemetry` with `event_prefix: [:phoenix, :endpoint]`. It also installs
`Phoenix.LiveDashboard.RequestLogger` with `request_logger` parameter/cookie keys.
For request diagnostics, inspect those framework hooks before adding a parallel
request logger.

## Metrics: Definitions, Events, and Reporters Are Separate

`apps/beamlet_app_web/lib/beamlet_web/application.ex` starts `Beamlet.Web.Telemetry`.
`apps/beamlet_app_web/lib/beamlet_web/telemetry.ex` defines Phoenix endpoint, router,
socket/channel and VM metrics. Representative definitions are:

```elixir
summary("phoenix.router_dispatch.exception.duration",
  tags: [:route],
  unit: {:native, :millisecond}
),
```

```elixir
summary("vm.memory.total", unit: {:byte, :kilobyte}),
```

When extending these definitions, follow the file's units and existing
route/event tag choices. The module's comment specifies that a custom periodic
measurement must emit `:telemetry.execute/3` and have a corresponding metric.
Its poller runs every 10,000 ms, but `periodic_measurements/0` currently returns
an empty list. The console reporter is only commented out; there is no configured
metrics exporter or app-defined event emission in current source.

The development dashboard uses `metrics: Beamlet.Web.Telemetry` in
`apps/beamlet_app_web/lib/beamlet_web/router.ex`. Dashboard metric display is not
persistent metric storage or error tracking. The actual web dependencies are in
`apps/beamlet_app_web/mix.exs`; `telemetry` is transitive in `mix.lock`.

## Development Diagnostics and Pitfalls

- `apps/beamlet_app_web/assets/js/app.js` enables server-log streaming to the browser
  when the live-reload hook attaches in development. Logs may be browser-visible;
  keep credentials and readable session contents out of diagnostic output (see
  [State and Persistence](./database-guidelines.md)).
- `apps/beamlet_app_web/lib/beamlet_web/endpoint.ex` gates Tidewave, which permits
  runtime code execution, on `Mix.env() == :dev`. Router debugger CSP allowances
  are also development-only; `config/dev.exs` binds LiveDebugger to loopback.
  Preserve those guards when modifying diagnostics.
- There are no focused telemetry/logging assertions in current `apps/*/test/`.
  A metric definition or installed dependency alone is not evidence of event
  delivery, export, or tested observability.
