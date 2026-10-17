defmodule Beamlet.Node.ObservationTest do
  use ExUnit.Case
  alias Beamlet.Node.Observation
  alias Beamlet.Runtime.Directory

  test "absent tree and explicit non-distributed local target" do
    assert {:ok, %{configured: false, roles: :unknown}} = Beamlet.Node.observation()
    local = node()

    assert {:ok, %{nodes: %{^local => %{configured: false}}, complete: true}} =
             Beamlet.Node.observe([local])

    assert {:error, :unavailable} = Beamlet.Runtime.observation()
  end

  test "all seven role declarations and independent registered readiness" do
    for roles <- [
          [:interaction],
          [:authority],
          [:executor],
          [:interaction, :authority],
          [:interaction, :executor],
          [:authority, :executor],
          [:interaction, :authority, :executor]
        ] do
      start_supervised!({Beamlet.Node, roles: roles})
      assert {:ok, %{roles: ^roles, services: services}} = Beamlet.Node.observation()
      assert services.authority == if(:authority in roles, do: :ready, else: :not_configured)
      assert services.executor == if(:executor in roles, do: :ready, else: :not_configured)
      assert services.runtime == :ready
      assert :ok = stop_supervised(Beamlet.Node)
    end
  end

  test "authority service loss and actual restart remain independent of reports" do
    start_supervised!({Beamlet.Node, roles: [:authority]})
    :ok = Supervisor.terminate_child(Beamlet.Node, Beamlet.Agent.AuthoritySupervisor)

    assert {:ok, %{roles: [:authority], services: %{authority: :unavailable}}} =
             Beamlet.Node.observation()

    assert {:ok, _} = Supervisor.restart_child(Beamlet.Node, Beamlet.Agent.AuthoritySupervisor)
    assert {:ok, %{services: %{authority: :ready}}} = Beamlet.Node.observation()
  end

  test "executor service loss and restart" do
    start_supervised!({Beamlet.Node, roles: [:executor]})

    :ok =
      Supervisor.terminate_child(Beamlet.Runtime.SharedSupervisor, Beamlet.Runtime.NodeEndpoint)

    :ok =
      Supervisor.terminate_child(
        Beamlet.Runtime.SharedSupervisor,
        Beamlet.Runtime.ExecutionSupervisor
      )

    assert {:ok, %{services: %{executor: :unavailable}}} = Beamlet.Node.observation()

    assert {:ok, _} =
             Supervisor.restart_child(
               Beamlet.Runtime.SharedSupervisor,
               Beamlet.Runtime.ExecutionSupervisor
             )

    assert {:ok, _} =
             Supervisor.restart_child(
               Beamlet.Runtime.SharedSupervisor,
               Beamlet.Runtime.NodeEndpoint
             )

    assert {:ok, %{services: %{executor: :ready}}} = Beamlet.Node.observation()
  end

  test "trusted targets are validated wholly" do
    for input <- [
          nil,
          "node",
          ["node"],
          [nil],
          [true],
          [node(), node()],
          [node() | :bad],
          Enum.to_list(1..33)
        ] do
      assert {:error, :invalid_query} = Beamlet.Node.observe(input)
    end

    too_many = :erlang.module_info(:exports) |> Keyword.keys() |> Enum.uniq() |> Enum.take(33)
    assert length(too_many) == 33
    assert {:error, :invalid_query} = Beamlet.Node.observe(too_many)
    assert {:ok, %{nodes: %{}, failures: %{}, complete: true}} = Beamlet.Node.observe([])
    target = :unconnected_observation@localhost

    assert {:ok, %{failures: %{^target => :unavailable}, complete: false}} =
             Beamlet.Node.observe([target])

    refute target in Node.list(:connected)
  end

  test "full aggregate envelope reserves failure space under byte pressure" do
    initial = %{nodes: %{}, failures: %{}, complete: true}
    large = %{configured: false, content: String.duplicate("x", 520_000)}
    result = Observation.retain(initial, :a, {:ok, large})
    result = Observation.retain(result, :b, {:ok, large})

    targets =
      :erlang.module_info(:exports)
      |> Keyword.keys()
      |> Enum.uniq()
      |> Enum.reject(&(&1 in [:a, :b]))
      |> Enum.take(30)

    assert length(targets) == 30

    result =
      Enum.reduce(targets, result, fn target, acc ->
        Observation.retain(acc, target, {:error, :timeout})
      end)

    assert map_size(result.nodes) == 1
    assert map_size(result.failures) == 31
    assert Enum.all?(targets, &(result.failures[&1] == :timeout))
    assert result.failures.b == :limit
    assert :erlang.external_size({:ok, result}) <= 1_048_576
  end

  @tag timeout: 12_000
  test "suspended owner reader goes DOWN before resume, abandoned caller receives no late reply" do
    start_supervised!({Beamlet.Node, roles: [:authority]})
    directory = Process.whereis(Directory)
    :ok = :sys.suspend(directory)
    on_exit(fn -> if Process.alive?(directory), do: :sys.resume(directory) end)
    parent = self()
    caller = spawn(fn -> send(parent, {:result, Beamlet.Node.observation()}) end)
    worker = await_reader(directory)
    monitor = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 6000
    assert Process.alive?(directory)
    :ok = :sys.resume(directory)
    refute_receive {:result, _}, 100
    assert {:ok, _} = Beamlet.Node.observation()
  end

  test "nested read consumes remaining budget" do
    start_supervised!({Beamlet.Node, roles: [:interaction]})
    directory = Process.whereis(Directory)
    :sys.suspend(directory)
    task = Task.async(fn -> Observation.local_read(100) end)
    worker = await_reader(directory)
    ref = Process.monitor(worker)
    assert {:ok, %{runtime: {:error, :timeout}}} = Task.await(task, 1000)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
    :sys.resume(directory)
  end

  defp await_reader(server, attempts \\ 100) do
    {:messages, messages} = Process.info(server, :messages)

    case Enum.find(messages, &match?({:"$gen_call", _, :observation}, &1)) do
      {:"$gen_call", {pid, _}, :observation} ->
        pid

      nil ->
        assert attempts > 0
        Process.sleep(10)
        await_reader(server, attempts - 1)
    end
  end
end
