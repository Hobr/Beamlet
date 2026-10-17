defmodule Beamlet.Runtime.ObservationTest do
  use ExUnit.Case
  alias Beamlet.Runtime.{Directory, Groups, NodeEndpoint, TestPeer}

  test "report absence, source receipt age and stale retention do not alter selection" do
    start_supervised!({Beamlet.Runtime, execution: false, limits: [refresh_ms: 3_600_000]})
    endpoint = Process.whereis(NodeEndpoint)
    :sys.suspend(endpoint)
    on_exit(fn -> if Process.alive?(endpoint), do: :sys.resume(endpoint) end)
    :sys.replace_state(Directory, fn s -> %{s | reports: %{}} end)
    assert {:ok, %{reports: reports}} = Beamlet.Runtime.observation()
    assert Enum.any?(reports, &(&1.status == :not_reported and &1.age_ms == :unknown))

    report = %{
      node: node(),
      ready: true,
      execution_ready: true,
      capabilities: ["safe"],
      environments: ["public"],
      available: %{"pool" => 3},
      gateway: self(),
      lease: -999,
      incarnation: make_ref(),
      handlers: %{"secret" => true},
      utilization: 8.0
    }

    time = System.monotonic_time(:millisecond)

    :sys.replace_state(Directory, fn s ->
      %{s | reports: %{endpoint => {time - 20_000, report}}}
    end)

    assert {:ok, %{source: source, reports: [projected]}} = Beamlet.Runtime.observation()
    assert source == node()
    assert projected.age_ms in 20_000..21_000
    assert projected.status == :stale
    assert projected.available == %{"pool" => 3}

    assert Map.keys(projected) |> Enum.sort() ==
             Enum.sort([
               :node,
               :ready,
               :execution_ready,
               :capabilities,
               :environments,
               :available,
               :age_ms,
               :status
             ])

    assert Directory.snapshots() == %{}
    :sys.resume(endpoint)
    :pg.leave(Groups, :nodes, endpoint)
  end

  test "live reports expose available quantities without starting operations" do
    start_supervised!(
      {Beamlet.Runtime,
       execution: true,
       handlers: %{"echo" => {Beamlet.Runtime.TestHandler, self()}},
       capabilities: ["public"],
       environments: ["safe"],
       pools: %{"pool" => 3},
       limits: [refresh_ms: 10]}
    )

    TestPeer.barrier("echo")
    before = DynamicSupervisor.count_children(Beamlet.Runtime.Coordinators)
    assert {:ok, %{reports: reports, complete: true}} = Beamlet.Runtime.observation()
    assert Enum.any?(reports, &(&1.status == :fresh and &1.available == %{"pool" => 3}))
    assert DynamicSupervisor.count_children(Beamlet.Runtime.Coordinators) == before
    assert Task.Supervisor.children(Beamlet.Runtime.Workers) == []
    refute_receive {:worker, _}, 20
  end

  test "report projection count is bounded with explicit completeness" do
    start_supervised!({Beamlet.Runtime, execution: false})
    members = for _ <- 1..257, do: spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Enum.each(members, &Process.exit(&1, :kill)) end)
    Enum.each(members, &:pg.join(Groups, :nodes, &1))
    assert {:ok, %{reports: reports, complete: false}} = Beamlet.Runtime.observation()
    assert length(reports) == 256
  end

  test "owner projection limits complete serialized bytes without returning raw state" do
    start_supervised!({Beamlet.Runtime, execution: false, limits: [refresh_ms: 3_600_000]})

    :sys.replace_state(Directory, fn s ->
      report = %{
        node: node(),
        ready: false,
        execution_ready: false,
        capabilities: [String.duplicate("x", 1_000_000)],
        environments: [],
        available: %{}
      }

      %{
        s
        | reports: %{
            Process.whereis(NodeEndpoint) => {System.monotonic_time(:millisecond), report}
          }
      }
    end)

    assert {:error, :limit} = Beamlet.Runtime.observation()
  end
end
