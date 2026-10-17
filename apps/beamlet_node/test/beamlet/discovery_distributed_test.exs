defmodule Beamlet.Node.DiscoveryDistributedTest do
  use ExUnit.Case
  alias Beamlet.Agent
  alias Beamlet.Node.Agents
  @moduletag :distributed

  setup context do
    assert Node.alive?()

    peers =
      for role <-
            if(context[:resource],
              do: List.duplicate(:authority, 10),
              else: [:authority, :authority, :interaction]
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

  defp options,
    do: [
      id: "same",
      model: %{
        provider: "deterministic",
        config: %{"reply" => %{"kind" => "text", "content" => "SYNTHETIC_SECRET", "calls" => []}}
      }
    ]

  test "real authorities disambiguate same IDs and non-authority; creator exit and restart", %{
    peers: [{p, a}, {_, b}, {_, interaction}]
  } do
    task = Task.async(fn -> Agent.start(a, options()) end)
    {:ok, first} = Task.await(task)
    {:ok, second} = Agent.start(b, options())

    assert {:ok,
            %{agents: descriptors, failures: %{^interaction => :not_authority}, complete: false}} =
             Agents.discover([a, b, interaction])

    assert Enum.sort(Enum.map(descriptors, & &1.authority)) == Enum.sort([a, b])
    refute inspect(descriptors) =~ "SECRET"
    assert {:ok, ^first} = Agent.lookup(Enum.find(descriptors, &(&1.authority == a)))
    assert {:ok, ^second} = Agent.lookup(b, "same")
    assert {:ok, %{turn: nil, status: :idle}} = Agent.snapshot(first)
    assert {:error, :not_found} = Agent.lookup(a, "missing")
    assert {:error, :not_authority} = Agent.lookup(interaction, "same")
    descriptor = Enum.find(descriptors, &(&1.authority == a))
    :ok = Agent.close(first)
    assert {:ok, replacement} = Agent.start(a, options())
    assert replacement.pid != first.pid
    assert {:error, :stale_agent} = Agent.lookup(descriptor)
    assert {:ok, ^replacement} = Agent.lookup(a, "same")

    :ok =
      :peer.call(p, Supervisor, :terminate_child, [
        Beamlet.Node,
        Beamlet.Agent.AuthoritySupervisor
      ])

    assert {:ok, _} =
             :peer.call(p, Supervisor, :restart_child, [
               Beamlet.Node,
               Beamlet.Agent.AuthoritySupervisor
             ])

    assert {:error, :not_found} = Agent.lookup(a, "same")
    assert {:error, :unavailable} = Agent.snapshot(first)
  end

  @tag timeout: 10_000
  test "remote caller loss permits finite read completion without changing identity", %{
    peers: [{p, a} | _]
  } do
    {:ok, ref} = Agent.start(a, options())
    registry = :peer.call(p, Process, :whereis, [Agent.Registry])
    agents = :peer.call(p, Process, :whereis, [Agent.Agents])
    :ok = :peer.call(p, :sys, :suspend, [ref.pid])
    caller = spawn(fn -> Agent.lookup(a, "same") end)
    worker = await_reader(p, ref.pid)
    monitor = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert :peer.call(p, Process, :alive?, [worker])
    assert_receive {:DOWN, ^monitor, _, _, _}, 6000
    assert :peer.call(p, Process, :whereis, [Agent.Registry]) == registry
    assert :peer.call(p, Process, :whereis, [Agent.Agents]) == agents
    :ok = :peer.call(p, :sys, :resume, [ref.pid])
    assert {:ok, ^ref} = Agent.lookup(a, "same")
    assert {:ok, %{status: :idle, turn: nil}} = Agent.snapshot(ref)
  end

  test "killing actual remote execution does not restart identity infrastructure", %{
    peers: [{p, a} | _]
  } do
    {:ok, ref} = Agent.start(a, options())
    registry = :peer.call(p, Process, :whereis, [Agent.Registry])
    :ok = :peer.call(p, :sys, :suspend, [ref.pid])
    task = Task.async(fn -> Agent.lookup(a, "same") end)
    worker = await_reader(p, ref.pid)
    :peer.call(p, Process, :exit, [worker, :kill])
    assert {:error, :unavailable} = Task.await(task)
    assert :peer.call(p, Process, :whereis, [Agent.Registry]) == registry
    :ok = :peer.call(p, :sys, :resume, [ref.pid])
    assert {:ok, ^ref} = Agent.lookup(a, "same")
  end

  @tag timeout: 10_000
  test "remote timeout drops late replies; disconnected entry rejects without connecting", %{
    peers: [{p, a} | _]
  } do
    {:ok, ref} = Agent.start(a, options())
    :ok = :peer.call(p, :sys, :suspend, [ref.pid])
    caller = self()
    spawn(fn -> send(caller, {:reader, await_reader(p, ref.pid)}) end)
    assert {:error, :timeout} = Agent.lookup(a, "same")
    assert_receive {:reader, worker}
    await_dead(p, worker, 100)
    :ok = :peer.call(p, :sys, :resume, [ref.pid])
    assert {:ok, ^ref} = Agent.lookup(a, "same")
    refute_receive {_, {:ok, _}}, 100
    assert Node.disconnect(a)
    assert {:error, :unavailable} = Agent.list(a)
    assert {:ok, %{failures: %{^a => :unavailable}, complete: false}} = Agents.discover([a])
    refute a in Node.list(:connected)
  end

  @tag timeout: 10_000
  test "disconnect during a read abandons response while remote budget remains finite", %{
    peers: [{p, a} | _]
  } do
    {:ok, ref} = Agent.start(a, options())
    :ok = :peer.call(p, :sys, :suspend, [ref.pid])
    task = Task.async(fn -> Agent.lookup(a, "same") end)
    worker = await_reader(p, ref.pid)
    assert Node.disconnect(a)
    assert {:error, :unavailable} = Task.await(task, 1500)
    assert :peer.call(p, Process, :alive?, [worker])
    # Observe remote death through the independent standard_io control channel.
    await_dead(p, worker, 600)
    :ok = :peer.call(p, :sys, :resume, [ref.pid])
    assert Node.connect(a)
    assert {:ok, ^ref} = Agent.lookup(a, "same")
  end

  test "OTP reconnects after a successful precheck followed by disconnect", %{
    peers: [{_, a} | _]
  } do
    assert a in Node.list(:connected)
    assert Node.disconnect(a)
    assert {:ok, []} = :erpc.call(a, Agent.Discovery, :query_local, [:list, 500], 1000)
    assert a in Node.list(:connected)
  end

  test "connected VM without Beamlet code is unavailable" do
    {:ok, peer, remote} =
      :peer.start_link(%{
        name: String.to_atom("no_query_code_#{System.unique_integer([:positive])}"),
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())],
        shutdown: 3000
      })

    Process.unlink(peer)
    on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)
    assert :peer.call(peer, :net_kernel, :connect_node, [node()])
    assert {:error, :unavailable} = Agent.list(remote)
  end

  defp await_dead(peer, pid, attempts) do
    if :peer.call(peer, Process, :alive?, [pid]) do
      assert attempts > 0
      Process.sleep(10)
      await_dead(peer, pid, attempts - 1)
    end
  end

  test "aggregate caller exit retires its local task tree before delayed remote load", %{
    peers: [{p, a} | _]
  } do
    :peer.call(p, :code, :purge, [Agent.Discovery])
    :peer.call(p, :code, :delete, [Agent.Discovery])
    :peer.call(p, :sys, :suspend, [:code_server])
    on_exit(fn -> :peer.call(p, :sys, :resume, [:code_server]) end)
    caller = spawn(fn -> receive do: (:go -> Agents.discover([a])) end)
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
      :peer.call(p, :code, :purge, [Agent.Discovery])
      :peer.call(p, :code, :delete, [Agent.Discovery])
      :peer.call(p, :sys, :suspend, [:code_server])
      on_exit(fn -> :peer.call(p, :sys, :resume, [:code_server]) end)
    end)

    started = Agent.Discovery.now()
    task = Task.async(fn -> Agents.discover(Enum.map(peers, &elem(&1, 1))) end)
    counts = await_loads(peers)
    assert Enum.sum(counts) == 8
    assert Enum.count(counts, &(&1 > 0)) == 8
    assert {:ok, %{agents: [], failures: failures, complete: false}} = Task.await(task, 6500)
    assert (Agent.Discovery.now() - started) in 4900..6200
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

  defp await_reader(peer, server, attempts \\ 100) do
    {:messages, messages} = :peer.call(peer, Process, :info, [server, :messages])

    case Enum.find(messages, &match?({:"$gen_call", _, :ref}, &1)) do
      {:"$gen_call", {pid, _}, :ref} ->
        pid

      nil ->
        assert attempts > 0
        Process.sleep(10)
        await_reader(peer, server, attempts - 1)
    end
  end
end
