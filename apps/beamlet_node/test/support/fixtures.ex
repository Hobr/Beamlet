defmodule Beamlet.Node.TestModel do
  alias Beamlet.Node.TestBinding
  @moduledoc false
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.Model

  def validate_invocation(%{config: config, credentials: credentials}) do
    if Map.keys(config) -- ["hold", "loop", "invalid", "observer"] == [] and credentials == %{},
      do: :ok,
      else: {:error, :invalid_profile}
  end

  def complete(request, %{config: settings}, _context) do
    with :ok <- Model.validate_request(request) do
      if settings["observer"],
        do:
          send(
            TestBinding.observer(settings["observer"]),
            {:model, node(), self(), request.messages}
          )

      if settings["hold"], do: receive(do: (:release -> :ok))
      tools = Enum.filter(request.messages, &(&1["role"] == "tool"))

      reply(tools, settings)
    end
  end

  defp reply(tools, settings) do
    if tools == [] and settings["loop"] do
      calls =
        for {path, i} <- Enum.with_index(["first", "second"]),
            do: %{id: "call#{i}", name: "workspace_read", arguments: %{"path" => path}}

      calls =
        if settings["invalid"],
          do: List.update_at(calls, 1, &%{&1 | arguments: %{}}),
          else: calls

      {:ok, %{kind: :tool_calls, content: nil, calls: calls}}
    else
      {:ok, %{kind: :text, content: Jason.encode!(%{node: node(), tools: tools}), calls: []}}
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
    # This fixture adds a separate authority island after interaction startup.
    # Remove the non-authority query responder to avoid two fixed-name owners.
    if Process.whereis(Beamlet.Node) do
      Supervisor.terminate_child(Beamlet.Node, Beamlet.Agent.Discovery.Endpoint)
      Supervisor.delete_child(Beamlet.Node, Beamlet.Agent.Discovery.Endpoint)
    end

    {:ok, pid} =
      AuthoritySupervisor.start_link(
        model_providers: %{"held" => Beamlet.Node.TestModel, "model" => Beamlet.Node.TestModel}
      )

    Process.unlink(pid)
    :ok
  end

  def boot(opts) do
    {:ok, _} = Application.ensure_all_started(:beamlet_node)
    {:ok, pid} = Beamlet.Node.start_link(opts)
    Process.unlink(pid)
    :ok
  end

  def capacity_fence(n \\ 100) do
    if map_size(:sys.get_state(Beamlet.Runtime.ExecutorGateway).tasks) == 0 do
      System.monotonic_time(:millisecond)
    else
      if n == 0, do: raise("gateway capacity timeout")
      Process.sleep(10)
      capacity_fence(n - 1)
    end
  end

  def fresh_capacity(executor, fence, n \\ 100) do
    if Enum.any?(Directory.snapshots(), fn {_, r} ->
         r.node == executor and r.lease > fence and r.available["native"] == 2
       end) do
      :ok
    else
      if n == 0, do: raise("fresh capacity report timeout")
      Process.sleep(10)
      fresh_capacity(executor, fence, n - 1)
    end
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
