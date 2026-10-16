# Error Handling

## Existing Contracts, Not a Domain Error Taxonomy

Actions/Runtime now define validated data contracts, immediate `{:error, reason}`
responses and terminal Result statuses. See [Operation Runtime](./operation-runtime.md)
for the executable failure matrix. No automatic retry or recovery exists.
Harness returns safe native errors without raw credentials, paths or provider
bodies; see [Native Harness](./harness-providers.md). Agent/Node expose explicit
command/startup/terminal errors; see [Agent and Node](./agent-orchestration.md).
Stopped generations reject late replies; infrastructure loss never replays work.

## Startup and Configuration Failures

Both `apps/beamlet_node/lib/beamlet/node/application.ex` and
`apps/beamlet_web/lib/beamlet_web/application.ex` return
`Supervisor.start_link(children, opts)` directly. The source preserves OTP's
startup result; it does not convert a failed start into success or rescue it.
Web's `config_change/3` forwards endpoint changes and returns `:ok`.

`config/runtime.exs` explicitly raises when production `SECRET_KEY_BASE` is
missing. `apps/beamlet_web/lib/beamlet_web/router.ex` uses
`Application.compile_env!(:live_debugger, :port)` only in development; its value
is provided by `config/dev.exs`. Preserve these fail-fast boundaries instead of
substituting silent defaults.

## HTTP Error Rendering

`config/config.exs` registers HTML and JSON error modules on
`Beamlet.Web.Endpoint`, with `layout: false`.
`apps/beamlet_web/lib/beamlet_web/controllers/error_html.ex` renders the status
message as plain text. The JSON renderer in
`apps/beamlet_web/lib/beamlet_web/controllers/error_json.ex` is:

```elixir
def render(template, _assigns) do
  %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
end
```

The matching tests under `apps/beamlet_web/test/beamlet_web/controllers/` lock
404 → `"Not Found"` and 500 → `"Internal Server Error"`:

- `error_html_test.exs` calls `Phoenix.Template.render_to_string/4`.
- `error_json_test.exs` directly checks the map returned by `ErrorJSON.render/2`.

These are renderer unit tests, not end-to-end exception tests. There are no
active API routes or fallback controller in
`apps/beamlet_web/lib/beamlet_web/router.ex`; `PageController.home/2` simply
renders `:home` (`controllers/page_controller.ex` in the same web source tree).
Use the status renderers for their existing purpose; an API validation/error
envelope beyond this map is not yet established. Avoid exposing raw exception
assigns in a status renderer: both renderers currently ignore assigns.
`config/dev.exs` enables `debug_errors: true`, so development debug responses
must not be mistaken for the production error contract.

## Form and Connection Feedback

`apps/beamlet_web/lib/beamlet_web/components/core_components.ex` keeps form
feedback in components: `input/1` accepts `Phoenix.HTML.FormField`, shows errors
only after `Phoenix.Component.used_input?/1`, and translates `{msg, opts}` with
`translate_error/1`. That function uses Gettext's `errors` domain, choosing plural
translation when `opts[:count]` is present. `translate_errors/2` filters a keyword
list by field. These helpers do not define a backend validation layer.

`apps/beamlet_web/lib/beamlet_web/components/layouts.ex` renders info/error flash
and client/server disconnection notices with reconnect text. Those UI notices are
separate from HTTP status responses and have no focused component tests today.
When changing them, add a test for the changed behavior rather than inferring
coverage from the renderer tests.
