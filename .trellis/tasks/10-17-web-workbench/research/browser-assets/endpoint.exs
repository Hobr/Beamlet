# Run from umbrella root: MIX_ENV=test ERL_FLAGS='+S 2:2' mix run --no-start PATH
# Loopback fixture only; uses real public model, Tool, Agent and Host APIs.
defmodule BrowserModel do
  @behaviour Beamlet.Harness.Model
  def validate_invocation(_), do: :ok
  def complete(request, _, _) do
    last = List.last(request.messages)
    text = last["content"] || ""
    Process.sleep(if String.contains?(text, "HOLD"), do: 20000, else: 1000)
    cond do
      last["role"] == "tool" -> {:ok, %{kind: :text, content: "Tool completed\n" <> String.duplicate("bounded final output <script>window.hostile=1</script>\n", 220), calls: []}}
      String.contains?(text, "TOOLS") -> {:ok, %{kind: :tool_calls, content: "Concurrent work", calls: for(id <- ["one", "two"], do: %{id: id, name: "echo", arguments: %{"text" => String.duplicate("long line\n", 1100)}})}}
      true -> {:ok, %{kind: :text, content: "Response: " <> text <> "\n" <> String.duplicate("readable context line\n", 100), calls: []}}
    end
  end
end
defmodule BrowserTool do
  @behaviour Beamlet.Harness.Tool
  def descriptor, do: %{"name" => "echo", "description" => "Bounded browser fixture", "parameters" => %{"type" => "object", "properties" => %{"text" => %{"type" => "string"}}, "required" => ["text"]}}
  def invoke(args, _, _), do: (Process.sleep(7000); {:ok, args})
end
Application.put_env(:beamlet_web, Beamlet.Web.Endpoint, Keyword.merge(Application.get_env(:beamlet_web, Beamlet.Web.Endpoint), server: true, http: [ip: {127,0,0,1}, port: 19447], check_origin: ["//127.0.0.1:19447"]))
model = %{provider: "browser", config: %{}, credentials: %{}}
Application.put_env(:beamlet_web, :host,
 enabled: true,
 node: [roles: [:interaction, :authority, :executor], model_providers: %{"browser" => BrowserModel}, allowlist: %{tool: [BrowserTool]}, profiles: %{"echo" => %{type: :tool, module: BrowserTool, settings: %{}}}],
 catalogue: %{models: %{"local" => %{title: "Browser deterministic", binding: model}},
 tools: %{"echo" => %{title: "Echo tool", route: %{id: "echo", capability: "echo"}, descriptor: BrowserTool.descriptor(), environments: ["workspace"]}},
 environments: %{"workspace" => %{title: "Fixture workspace", value: "workspace"}},
 presets: %{"basic" => %{title: "Chat", model: "local", tools: []}, "tools" => %{title: "Tool run", model: "local", tools: ["echo"], environment: "workspace"}},
 authorities: %{"local" => %{title: "Fixture local", target: :local}}, default_authority: "local"})
{:ok, _} = Application.ensure_all_started(:beamlet_web)
{:ok, external} = Beamlet.Agent.start(node(), id: "external-browser", model: model)
{:ok, parent} = Beamlet.Agent.start(node(), id: "parent-browser", model: model)
{:ok, _} = Beamlet.Agent.delegate(parent, [%{authority: node(), options: [id: "child-browser", model: model], input: "HOLD child"}])
IO.puts("BROWSER_FIXTURE_READY")
# A local file signal makes only a public business input, for the arrival-while-reading test.
spawn(fn ->
  Stream.repeatedly(fn -> Process.sleep(300); File.exists?("/tmp/beamlet-browser-arrival") end)
  |> Enum.find(& &1)
  File.rm("/tmp/beamlet-browser-arrival")
  IO.inspect(Beamlet.Agent.input(external, "arrival while reader above bottom"), label: "PUBLIC_ARRIVAL")
end)
Process.sleep(:infinity)
