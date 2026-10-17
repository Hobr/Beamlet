defmodule Beamlet.Node.ObservationDistributedTest do
  use ExUnit.Case
  @moduletag :distributed
  setup context do
    assert Node.alive?()

    peers =
      for role <-
            if(context[:resource],
              do: List.duplicate(:authority, 10),
              else: [:authority, :executor]
            ) do
        paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

        {:ok, peer, remote} =
          :peer.start_link(%{
            name: String.to_atom("discovery_#{System.unique_integer([:positive])}"),
            connection: :standard_io,
            args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())] ++ paths,
            wait_boot: 10_000,
            shutdown: 3000
          })

        Process.unlink(peer)
        on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)
        assert true = :peer.call(peer, Node, :connect, [node()])
        assert :ok = :peer.call(peer, Beamlet.Node.TestBoot, :boot, [[roles: [role]]])
        {peer, remote}
      end

    Enum.each(peers, fn {peer, remote} ->
      Enum.each(peers, fn {_, other} ->
        if other != remote, do: assert(:peer.call(peer, Node, :connect, [other]))
      end)
    end)

    %{peers: peers}
  end

  test "named authority/executor observations and disconnected partial failures", %{
    peers: [{_, a}, {_, b}]
  } do
    assert {:ok, %{nodes: nodes, complete: true}} = Beamlet.Node.observe([a, b])
    assert nodes[a].roles == [:authority]
    assert nodes[b].roles == [:executor]
    assert nodes[a].services.authority == :ready
    assert nodes[b].services.authority == :not_configured
    assert Node.disconnect(b)

    assert {:ok, %{nodes: nodes, failures: %{^b => :unavailable}, complete: false}} =
             Beamlet.Node.observe([a, b])

    assert Map.has_key?(nodes, a)
    refute b in Node.list(:connected)
  end

  @tag timeout: 12_000
  test "remote read expires and helper is DOWN before source resumes", %{
    peers: [{peer, target} | _]
  } do
    directory = :peer.call(peer, Process, :whereis, [Beamlet.Runtime.Directory])
    :ok = :peer.call(peer, :sys, :suspend, [directory])
    on_exit(fn -> :peer.call(peer, :sys, :resume, [directory]) end)
    task = Task.async(fn -> Beamlet.Node.observe([target]) end)
    worker = await_reader(peer, directory)
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 6000
    assert {:ok, %{complete: false}} = Task.await(task, 1500)
    :ok = :peer.call(peer, :sys, :resume, [directory])
    assert {:ok, %{complete: true}} = Beamlet.Node.observe([target])
    refute_receive {:observed, _, _}, 100
  end

  defp await_reader(peer, server, attempts \\ 100) do
    {:messages, messages} = :peer.call(peer, Process, :info, [server, :messages])

    case Enum.find(messages, &match?({:"$gen_call", _, :observation}, &1)) do
      {:"$gen_call", {pid, _}, :observation} ->
        pid

      nil ->
        assert attempts > 0
        Process.sleep(10)
        await_reader(peer, server, attempts - 1)
    end
  end

  test "aggregate caller exit retires its local task tree before delayed remote load", %{
    peers: [{p, a} | _]
  } do
    :peer.call(p, :code, :purge, [Beamlet.Node.Observation])
    :peer.call(p, :code, :delete, [Beamlet.Node.Observation])
    :peer.call(p, :sys, :suspend, [:code_server])
    on_exit(fn -> :peer.call(p, :sys, :resume, [:code_server]) end)
    caller = spawn(fn -> receive do: (:go -> Beamlet.Node.observe([a])) end)
    :erlang.trace(caller, true, [:procs, :set_on_spawn, {:tracer, self()}])
    send(caller, :go)
    assert [1] = await_loads([{p, a}])
    helpers = traced_children([])
    assert length(helpers) >= 3
    monitors = for pid <- [caller | helpers], do: {pid, Process.monitor(pid)}
    Process.exit(caller, :kill)

    Enum.each(monitors, fn {pid, monitor} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1500
    end)

    :peer.call(p, :sys, :resume, [:code_server])
  end

  defp traced_children(acc) do
    receive do
      {:trace, _, :spawn, pid, _} -> traced_children([pid | acc])
      {:trace, _, _, _} -> traced_children(acc)
    after
      25 -> Enum.uniq(acc)
    end
  end

  @tag :resource
  @tag timeout: 40_000
  test "ten slow code loads share one5s deadline and at most8 requests", %{peers: peers} do
    # Delay module loading before the finite entry starts. This deliberately
    # exercises approved late execution semantics without a product test switch.
    Enum.each(peers, fn {p, _} ->
      :peer.call(p, :code, :purge, [Beamlet.Node.Observation])
      :peer.call(p, :code, :delete, [Beamlet.Node.Observation])
      :peer.call(p, :sys, :suspend, [:code_server])
      on_exit(fn -> :peer.call(p, :sys, :resume, [:code_server]) end)
    end)

    started = System.monotonic_time(:millisecond)
    task = Task.async(fn -> Beamlet.Node.observe(Enum.map(peers, &elem(&1, 1))) end)
    counts = await_loads(peers)
    assert Enum.sum(counts) == 8
    assert Enum.count(counts, &(&1 > 0)) == 8
    assert {:ok, %{nodes: %{}, failures: failures, complete: false}} = Task.await(task, 6500)
    assert (System.monotonic_time(:millisecond) - started) in 4900..6200
    assert map_size(failures) == 10
    assert Enum.uniq(Map.values(failures)) == [:timeout]
    Enum.each(peers, fn {p, _} -> :peer.call(p, :sys, :resume, [:code_server]) end)
  end

  defp await_loads(peers, attempts \\ 100) do
    counts =
      Enum.map(peers, fn {p, _} ->
        pid = :peer.call(p, Process, :whereis, [:code_server])
        {:messages, messages} = :peer.call(p, Process, :info, [pid, :messages])
        Enum.count(messages, &match?({:code_call, _, _}, &1))
      end)

    if Enum.sum(counts) == 8 or attempts == 0 do
      counts
    else
      Process.sleep(10)
      await_loads(peers, attempts - 1)
    end
  end
end
