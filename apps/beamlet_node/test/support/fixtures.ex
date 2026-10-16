defmodule Beamlet.Node.TestModel do
  @moduledoc false
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.Models.OpenAICompatible

  def complete(request, settings, _context) do
    with :ok <- OpenAICompatible.validate_request(request) do
      if settings[:observer],
        do: send(settings.observer, {:model, node(), self(), request.messages})

      if settings[:hold],
        do:
          (receive do
             :release -> :ok
           end)

      tools = Enum.filter(request.messages, &(&1["role"] == "tool"))

      assistant =
        if tools == [] and settings[:loop] do
          calls = configured_calls(settings)

          %{"role" => "assistant", "content" => nil, "tool_calls" => calls}
        else
          %{"role" => "assistant", "content" => Jason.encode!(%{node: node(), tools: tools})}
        end

      finish = if assistant["tool_calls"], do: "tool_calls", else: "stop"

      reply(assistant, finish, request.catalogue, settings)
    end
  end

  # Deliberately violate the native normalized-reply contract in this fixture so
  # the Agent's own whole-batch guard, rather than Harness normalization, is tested.
  defp reply(assistant, _, _, %{invalid: true}),
    do: {:ok, %{kind: :tool_calls, assistant: assistant, content: nil, calls: []}}

  defp reply(assistant, finish, catalogue, _) do
    OpenAICompatible.normalize(
      %{"choices" => [%{"finish_reason" => finish, "message" => assistant}]},
      catalogue
    )
  end

  defp configured_calls(%{invalid: true}),
    do: List.update_at(calls(), 1, &put_in(&1, ["function", "arguments"], "{}"))

  defp configured_calls(_), do: calls()

  defp calls do
    for {path, index} <- Enum.with_index(["first", "second"]) do
      %{
        "id" => "call#{index}",
        "type" => "function",
        "function" => %{
          "name" => "workspace_read",
          "arguments" => Jason.encode!(%{"path" => path})
        }
      }
    end
  end
end

defmodule Beamlet.Node.TestTool do
  @moduledoc false
  @behaviour Beamlet.Harness.Tool
  alias Beamlet.Harness.Tools.WorkspaceRead
  def descriptor, do: WorkspaceRead.descriptor()

  def invoke(arguments, settings, context) do
    send(settings.observer, {:tool, node(), self(), arguments["path"]})

    receive do
      :release -> :ok
    end

    WorkspaceRead.invoke(arguments, Map.take(settings, [:root]), context)
  end
end

defmodule Beamlet.Node.TestBoot do
  @moduledoc false
  alias Beamlet.Agent.AuthoritySupervisor
  alias Beamlet.Runtime.Directory

  def authority do
    {:ok, pid} = AuthoritySupervisor.start_link([])
    Process.unlink(pid)
    :ok
  end

  def boot(opts) do
    {:ok, _} = Application.ensure_all_started(:beamlet_node)
    {:ok, pid} = Beamlet.Node.start_link(opts)
    Process.unlink(pid)
    :ok
  end

  def pending(ref, n \\ 100) do
    case Map.values(:sys.get_state(ref.pid).pending) do
      [] when n > 0 ->
        Process.sleep(10)
        pending(ref, n - 1)

      [] ->
        raise "operation readiness timeout"

      entries ->
        entries
    end
  end

  defp ready?(capability) do
    Enum.any?(Directory.snapshots(), fn {_, report} -> capability in report.capabilities end)
  catch
    :exit, _ -> false
  end

  def barrier(capability, n \\ 400) do
    if ready?(capability) do
      :ok
    else
      if n == 0, do: raise("discovery timeout")

      receive do
      after
        10 -> barrier(capability, n - 1)
      end
    end
  end
end
