# Owned, temporary browser-walkthrough endpoint fixture.
#
# Run from the umbrella root:
#   MIX_ENV=test ERL_FLAGS='+S 2:2' FIXTURE_PORT=19601 FIXTURE_OUT=/tmp/... \
#     mix run --no-start .trellis/tasks/10-17-beamlet-web/research/browser-assets/endpoint.exs
#
# Why the previous fixture failed:
#   `invalid_web_host_configuration` came from `Beamlet.Node.configuration/1`, not from
#   Host or Presets. `Node.valid_profiles?/2` requires every profile entry to carry a
#   binary `:capability` label (the previous fixture sent only type/module/settings), and
#   the Tool module must also be present in the Node `:allowlist`. Host folded the Node
#   rejection into its own generic startup error.
#
# This fixture uses only public, trusted startup APIs. No tracked config is mutated; no
# paid provider, network call or provider key is involved; nothing is persisted.

defmodule BrowserFixtureModel do
  @moduledoc false
  # Deterministic provider. Routes on the last neutral message only.
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.Context

  @impl true
  def validate_invocation(invocation), do: Beamlet.Harness.Model.validate_invocation(invocation)

  @impl true
  def complete(request, invocation, context \\ %Context{}) do
    with :ok <- validate_invocation(invocation),
         :ok <- Beamlet.Harness.Model.validate_request(request) do
      if Context.cancelled?(context) do
        {:error, :cancelled}
      else
        reply(request)
      end
    else
      error -> error
    end
  end

  defp reply(request) do
    messages = request.messages
    last = List.last(messages)
    text = if is_binary(last["content"]), do: last["content"], else: ""
    users = Enum.count(messages, &(&1["role"] == "user"))
    tools = request.catalogue |> Map.keys() |> Enum.sort()

    cond do
      String.contains?(text, "HOLD") ->
        # Long-running turn: lets the walkthrough observe running state and stop/keep.
        Process.sleep(900_000)
        {:ok, %{kind: :text, content: "HOLD turn finished", calls: []}}

      last["role"] == "tool" ->
        body = "Tool completed\n" <> List.last(messages)["content"]
        {:ok, %{kind: :text, content: body <> "\n" <> long_context(), calls: []}}

      String.contains?(text, "TOOLS") and tools != [] ->
        name = if "slow-echo" in tools, do: "slow-echo", else: hd(tools)
        Process.sleep(400)

        {:ok,
         %{
           kind: :tool_calls,
           content: "Working with the configured tool",
           # Model.validate_reply/2 canonicalises call maps with atom keys; the
           # deterministic fixture must therefore return atom-key call maps.
           calls: [
             %{
               id: "call-one",
               name: name,
               arguments: %{"text" => "browser tool argument " <> String.duplicate("x", 400)}
             }
           ]
         }}

      users >= 2 ->
        {:ok,
         %{kind: :text, content: "SECOND-TURN-ACK: " <> text <> "\n" <> long_context(), calls: []}}

      true ->
        {:ok,
         %{kind: :text, content: "Response to: " <> text <> "\n" <> long_context(), calls: []}}
    end
  end

  # ~90 short lines plus one very long line: enough height to scroll the
  # max-h-[55vh] region, and a single line that must wrap inside its container.
  defp long_context do
    lines = for n <- 1..90, do: "context line #{n} of the deterministic fixture response"
    [Enum.join(lines, "\n"), String.duplicate("long-unbroken-token-", 40)] |> Enum.join("\n")
  end
end

defmodule BrowserFixtureTool do
  @moduledoc false
  # Deterministic Tool that takes long enough to be observed as a live activity.
  @behaviour Beamlet.Harness.Tool
  alias Beamlet.Harness.{Arguments, Context}

  @impl true
  def descriptor do
    %{
      "name" => "slow-echo",
      "description" => "Deterministic bounded echo with an observable delay",
      "parameters" => %{
        "type" => "object",
        "properties" => %{"text" => %{"type" => "string", "maxLength" => 1000}},
        "required" => ["text"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(arguments, _settings, context \\ %Context{}) do
    with false <- Context.cancelled?(context),
         :ok <- Arguments.validate(arguments, descriptor()["parameters"]) do
      Context.emit(context, %{phase: "fixture-tool"})
      Process.sleep(2500)
      {:ok, %{"echoed" => arguments["text"]}}
    else
      true -> {:error, :cancelled}
      error -> error
    end
  end
end

port = System.get_env("FIXTURE_PORT", "19601") |> String.to_integer()
out = System.get_env("FIXTURE_OUT", "/tmp/beamlet-browser-fixture")

base = Application.get_env(:beamlet_web, Beamlet.Web.Endpoint)

Application.put_env(
  :beamlet_web,
  Beamlet.Web.Endpoint,
  Keyword.merge(base,
    server: true,
    http: [ip: {127, 0, 0, 1}, port: port],
    check_origin: false,
    url: [host: "127.0.0.1", port: port],
    code_reloader: false,
    watchers: []
  )
)

model_binding = %{provider: "fixture", config: %{}, credentials: %{}}

node_opts = [
  roles: [:interaction, :authority, :executor],
  model_providers: %{"fixture" => BrowserFixtureModel},
  allowlist: %{tool: [BrowserFixtureTool]},
  profiles: %{
    "slow-echo" => %{
      type: :tool,
      module: BrowserFixtureTool,
      settings: %{},
      capability: "tool.slow-echo",
      environment: "workspace"
    }
  },
  pools: %{"work" => 4}
]

catalogue = %{
  models: %{
    "local" => %{title: "Deterministic local model", binding: model_binding}
  },
  tools: %{
    "slow-echo" => %{
      title: "Slow echo tool",
      description: "Deterministic bounded echo",
      route: %{id: "slow-echo", capability: "tool.slow-echo"},
      descriptor: BrowserFixtureTool.descriptor(),
      environments: ["workspace"]
    }
  },
  environments: %{
    "workspace" => %{title: "Fixture workspace", value: "workspace"}
  },
  presets: %{
    "chat" => %{title: "Chat only", model: "local", tools: []},
    "tool-run" => %{
      title: "Tool run",
      model: "local",
      tools: ["slow-echo"],
      environment: "workspace"
    }
  },
  authorities: %{"local" => %{title: "This VM", target: :local}},
  default_authority: "local"
}

Application.put_env(:beamlet_web, :host,
  enabled: true,
  node: node_opts,
  catalogue: catalogue
)

case Application.ensure_all_started(:beamlet_web) do
  {:ok, _} -> :ok
  other -> raise "fixture startup failed: #{inspect(other)}"
end

{:ok, catalogue_handle} = Beamlet.Harness.Catalogue.new([BrowserFixtureTool.descriptor()])

agent_options = [
  model: model_binding,
  catalogue: catalogue_handle,
  tools: %{
    "slow-echo" => %{id: "slow-echo", capability: "tool.slow-echo", environment: "workspace"}
  },
  display_metadata: %{title: "Fixture Agent", preset_id: "tool-run"}
]

# A CLI-like external instance: created through the public Agent API, never through the UI.
{:ok, external} =
  Beamlet.Agent.start(
    node(),
    Keyword.merge(agent_options,
      id: "cli-external-agent",
      display_metadata: %{title: "CLI Agent"}
    )
  )

{:ok, _turn} = Beamlet.Agent.input(external, "external CLI first turn")

# A parent instance delegating a long-running child: exercises the real child inspector.
{:ok, parent} =
  Beamlet.Agent.start(node(), Keyword.merge(agent_options, id: "parent-browser"))

{:ok, _group} =
  Beamlet.Agent.delegate(parent, [
    %{
      authority: node(),
      options:
        Keyword.merge(agent_options, id: "child-browser", display_metadata: %{title: "Child"}),
      input: "HOLD child task"
    }
  ])

File.mkdir_p!(out)

handles =
  Enum.reduce([external, parent], %{}, fn ref, acc ->
    {:ok, handle} =
      Beamlet.Web.Handles.remember(%{authority: ref.authority, id: ref.id, pid: ref.pid})

    Map.put(acc, ref.id, handle)
  end)

File.write!(Path.join(out, "handles.json"), Jason.encode!(handles))
File.write!(Path.join(out, "port"), Integer.to_string(port))
IO.puts("BROWSER_FIXTURE_READY port=#{port} handles=#{inspect(handles)}")

Process.sleep(:infinity)
