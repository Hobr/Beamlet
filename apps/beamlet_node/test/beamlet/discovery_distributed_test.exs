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

  test "remote suspended lookup retires on caller loss before Server resume", %{
    peers: [{p, a} | _]
  } do
    {:ok, ref} = Agent.start(a, options())
    assert :ok = :peer.call(p, :sys, :suspend, [ref.pid])
    caller = spawn(fn -> Agent.lookup(a, "same") end)
    controller = controller(p)
    {:links, links} = :peer.call(p, Process, :info, [controller, :links])
    endpoint = :peer.call(p, Process, :whereis, [Agent.Discovery.Endpoint])
    worker = Enum.find(links, &(&1 != endpoint))
    cm = Process.monitor(controller)
    wm = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^cm, _, _, _}, 1500
    assert_receive {:DOWN, ^wm, _, _, _}, 1500
    assert :ok = :peer.call(p, :sys, :resume, [ref.pid])
    assert {:ok, ^ref} = Agent.lookup(a, "same")
  end

  test "suspended endpoint receives no late confirmation and disconnect never reconnects", %{
    peers: [{p, a} | _]
  } do
    assert :ok = :peer.call(p, :sys, :suspend, [Agent.Discovery.Endpoint])
    task = Task.async(fn -> Agents.discover([a]) end)

    assert {:ok, %{agents: [], failures: %{^a => :timeout}, complete: false}} =
             Task.await(task, 6500)

    assert :ok = :peer.call(p, :sys, :resume, [Agent.Discovery.Endpoint])
    Process.sleep(100)
    state = :peer.call(p, :sys, :get_state, [Agent.Discovery.Endpoint])
    assert map_size(state.active) == 0
    Node.monitor(a, true)
    assert true = Node.disconnect(a)
    assert_receive {:nodedown, ^a}
    assert {:error, :unavailable} = Agent.list(a)
    assert {:ok, %{failures: %{^a => :unavailable}, complete: false}} = Agents.discover([a])
    refute_receive {:nodeup, ^a}, 300
    refute a in Node.list(:connected)
  end

  @tag :resource
  @tag timeout: 40_000
  test "ten slow nodes share one5s deadline and at most8 active requests", %{peers: peers} do
    Enum.each(peers, fn {p, _} ->
      :ok = :peer.call(p, :sys, :suspend, [Agent.Discovery.Endpoint])
    end)

    start = System.monotonic_time(:millisecond)
    task = Task.async(fn -> Agents.discover(Enum.map(peers, &elem(&1, 1))) end)
    Process.sleep(150)

    counts =
      Enum.map(peers, fn {p, _} ->
        endpoint = :peer.call(p, Process, :whereis, [Agent.Discovery.Endpoint])
        {:messages, messages} = :peer.call(p, Process, :info, [endpoint, :messages])
        Enum.count(messages, &match?({:offer, _, _}, &1))
      end)

    assert Enum.sum(counts) == 8
    assert {:ok, %{agents: [], failures: failures, complete: false}} = Task.await(task, 6500)
    elapsed = System.monotonic_time(:millisecond) - start
    assert elapsed >= 4900 and elapsed < 6000
    assert map_size(failures) == 10
    assert Enum.uniq(Map.values(failures)) == [:timeout]

    Enum.each(peers, fn {p, _} ->
      :ok = :peer.call(p, :sys, :resume, [Agent.Discovery.Endpoint])
      assert map_size(:peer.call(p, :sys, :get_state, [Agent.Discovery.Endpoint]).active) == 0
    end)
  end

  test "disconnect between validation and send, and before offer reply, cannot reconnect", %{
    peers: [{p, a} | _]
  } do
    endpoint = :peer.call(p, Process, :whereis, [Agent.Discovery.Endpoint])
    :ok = :peer.call(p, :sys, :suspend, [endpoint])
    # Request has passed the connected check; force disconnect before its reply.
    caller = spawn(fn -> Agent.list(a) end)
    await_offer(p, endpoint)
    :net_kernel.monitor_nodes(true)
    assert Node.disconnect(a)
    assert_receive {:nodedown, ^a}, 1000
    assert :noconnect = Agent.Discovery.send_safe(endpoint, {:offer, self(), make_ref()})
    :ok = :peer.call(p, :sys, :resume, [endpoint])
    # Passive queued offer reply also uses noconnect, and no confirmation follows.
    refute_receive {:nodeup, ^a}, 350
    assert map_size(:peer.call(p, :sys, :get_state, [endpoint]).active) == 0
    refute a in Node.list(:connected)
    Process.exit(caller, :kill)
    :net_kernel.monitor_nodes(false)
  end

  test "aggregate caller death kills actual local task tree before endpoint resume", %{
    peers: [{p, a} | _]
  } do
    endpoint = :peer.call(p, Process, :whereis, [Agent.Discovery.Endpoint])
    :ok = :peer.call(p, :sys, :suspend, [endpoint])

    caller =
      spawn(fn ->
        receive do
          :go -> Agents.discover([a])
        end
      end)

    :erlang.trace(caller, true, [:procs, :set_on_spawn, {:tracer, self()}])
    send(caller, :go)
    await_offer(p, endpoint)
    helpers = traced_children([])
    assert length(helpers) >= 3
    monitors = for pid <- [caller | helpers], do: {pid, Process.monitor(pid)}
    Process.exit(caller, :kill)

    Enum.each(monitors, fn {pid, monitor} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1500
    end)

    :ok = :peer.call(p, :sys, :resume, [endpoint])
    assert map_size(:peer.call(p, :sys, :get_state, [endpoint]).active) == 0
  end

  @tag timeout: 10_000
  test "queued confirmation cannot start work after public timeout and helper DOWN", %{
    peers: [{peer, authority} | _]
  } do
    alias Agent.Discovery, as: D
    {:ok, ref} = Agent.start(authority, Keyword.put(options(), :id, "public-late"))
    :peer.call(peer, :sys, :suspend, [ref.pid])
    endpoint = :peer.call(peer, Process, :whereis, [D.Endpoint])
    :peer.call(peer, :sys, :suspend, [endpoint])
    started = D.now()
    task = Task.async(fn -> Agent.lookup(authority, "public-late") end)

    await_offer = fn recur ->
      {:messages, messages} = :peer.call(peer, Process, :info, [endpoint, :messages])

      case Enum.find(messages, &match?({:offer, _, _}, &1)) do
        {:offer, helper, _} ->
          helper

        nil ->
          Process.sleep(5)
          recur.(recur)
      end
    end

    helper = await_offer.(await_offer)
    :erlang.suspend_process(helper)
    Process.sleep(max(0, started + 1500 - D.now()))
    :peer.call(peer, :sys, :resume, [endpoint])
    # Endpoint creates its offer at t1.5s, expiring at t6.5s.
    _ = :peer.call(peer, :sys, :get_state, [endpoint])
    :peer.call(peer, :sys, :suspend, [endpoint])
    Process.sleep(max(0, started + 4600 - D.now()))
    :erlang.resume_process(helper)
    # Client emits confirm with ~400ms remaining, queued at suspended endpoint.
    Process.sleep(30)
    {:messages, queued} = :peer.call(peer, Process, :info, [endpoint, :messages])
    confirm = Enum.find(queued, &match?({:confirm, _, _, _, _, _}, &1))
    true = is_tuple(confirm)
    assert elem(confirm, 5) > 0
    assert {:error, :timeout} = Task.await(task, 1000)
    refute Process.alive?(helper)
    Process.sleep(150)
    {:messages, []} = :peer.call(peer, Process, :info, [ref.pid, :messages])
    assert D.now() - started >= 5000
    :peer.call(peer, :sys, :resume, [endpoint])
    Process.sleep(350)
    {:messages, messages} = :peer.call(peer, Process, :info, [ref.pid, :messages])
    calls = Enum.count(messages, &match?({:"$gen_call", _, :ref}, &1))
    assert calls == 0
    :peer.call(peer, :sys, :resume, [ref.pid])

    state = :peer.call(peer, :sys, :get_state, [endpoint])
    assert map_size(state.active) == 0
  end

  defp traced_children(acc) do
    receive do
      {:trace, _, :spawn, pid, _} -> traced_children([pid | acc])
      {:trace, _, _, _} -> traced_children(acc)
    after
      25 -> Enum.uniq(acc)
    end
  end

  defp await_offer(peer, endpoint, remaining \\ 100) do
    {:messages, messages} = :peer.call(peer, Process, :info, [endpoint, :messages])

    if Enum.any?(messages, &match?({:offer, _, _}, &1)) do
      :ok
    else
      assert remaining > 0
      Process.sleep(10)
      await_offer(peer, endpoint, remaining - 1)
    end
  end

  defp controller(peer, attempts \\ 100) do
    case Map.keys(:peer.call(peer, :sys, :get_state, [Agent.Discovery.Endpoint]).active) do
      [pid | _] ->
        pid

      [] when attempts > 0 ->
        Process.sleep(10)
        controller(peer, attempts - 1)

      [] ->
        flunk("remote controller absent")
    end
  end
end
