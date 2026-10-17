defmodule Beamlet.Agent.DiscoveryTest do
  use ExUnit.Case
  alias Beamlet.Agent

  defp create(id) do
    Agent.start(node(),
      id: id,
      model: %{
        provider: "deterministic",
        config: %{"reply" => %{"kind" => "text", "content" => "CONFIG_SECRET", "calls" => []}}
      }
    )
  end

  test "missing infrastructure and malformed queries are distinct" do
    assert {:error, :invalid_query} = Agent.list("arbitrary")
    assert {:error, :invalid_query} = Agent.lookup(node(), "")
    assert {:error, :unavailable} = Agent.list(node())
    start_supervised!({Agent.Discovery.Endpoint, authority: false})
    assert {:error, :not_authority} = Agent.list(node())
  end

  test "creator exits, safe descriptors reattach same real incarnation without input" do
    start_supervised!(Agent.AuthoritySupervisor)
    task = Task.async(fn -> create("same") end)
    assert {:ok, ref} = Task.await(task)
    assert {:ok, [descriptor]} = Agent.list(node())
    assert descriptor == %{authority: node(), id: "same", pid: ref.pid}
    refute inspect(descriptor) =~ "SECRET"
    assert {:ok, ^ref} = Agent.lookup(descriptor)
    assert {:ok, ^ref} = Agent.lookup(node(), "same")
    assert {:ok, %{status: :idle, turn: nil}} = Agent.snapshot(ref)
    assert {:error, :not_found} = Agent.lookup(node(), "absent")
    monitor = Process.monitor(ref.pid)
    assert :ok = Agent.close(ref)
    assert_receive {:DOWN, ^monitor, _, _, _}
    assert {:ok, replacement} = create("same")
    assert replacement.pid != ref.pid
    assert {:error, :stale_agent} = Agent.lookup(descriptor)
    assert {:ok, ^replacement} = Agent.lookup(node(), "same")
    assert {:error, :unavailable} = Agent.snapshot(ref)
  end

  test "list never waits for Server and caller loss retires blocked lookup workers" do
    start_supervised!(Agent.AuthoritySupervisor)
    {:ok, ref} = create("blocked")
    :ok = :sys.suspend(ref.pid)
    on_exit(fn -> if Process.alive?(ref.pid), do: :sys.resume(ref.pid) end)
    assert {:ok, [_]} = Agent.list(node())
    caller = spawn(fn -> Agent.lookup(node(), "blocked") end)
    endpoint = Process.whereis(Agent.Discovery.Endpoint)
    controller = await_controller(endpoint)
    {:links, links} = Process.info(controller, :links)
    worker = Enum.find(links, &(&1 != endpoint))
    cm = Process.monitor(controller)
    wm = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^cm, _, _, _}, 1500
    assert_receive {:DOWN, ^wm, _, _, _}, 1500
    assert Process.alive?(ref.pid)
    :ok = :sys.resume(ref.pid)
    assert {:ok, ^ref} = Agent.lookup(node(), "blocked")
  end

  @tag timeout: 8000
  test "deadline kills suspended lookup work before Server resume" do
    start_supervised!(Agent.AuthoritySupervisor)
    {:ok, ref} = create("deadline")
    :ok = :sys.suspend(ref.pid)
    task = Task.async(fn -> Agent.lookup(node(), "deadline") end)
    controller = await_controller(Process.whereis(Agent.Discovery.Endpoint))
    {:links, links} = Process.info(controller, :links)
    worker = Enum.find(links, &(&1 != Process.whereis(Agent.Discovery.Endpoint)))
    cm = Process.monitor(controller)
    wm = Process.monitor(worker)
    assert {:error, :timeout} = Task.await(task, 6500)
    assert_receive {:DOWN, ^cm, _, _, _}, 500
    assert_receive {:DOWN, ^wm, _, _, _}, 500
    :ok = :sys.resume(ref.pid)
    assert {:ok, ^ref} = Agent.lookup(node(), "deadline")
  end

  test "identity queries exclude real credential/config markers and reject registry overflow" do
    start_supervised!(Agent.AuthoritySupervisor)

    assert {:ok, ref} =
             Agent.start(node(),
               id: "secret",
               model: %{
                 provider: "openai-compatible",
                 config: %{"base_url" => "https://example.invalid/v1", "model" => "CONFIG_SECRET"},
                 credentials: %{"api_key" => "CREDENTIAL_SECRET"}
               }
             )

    assert {:ok, [descriptor]} = Agent.list(node())
    assert Map.keys(descriptor) |> Enum.sort() == [:authority, :id, :pid]
    assert {:ok, ^ref} = Agent.lookup(descriptor)
    assert {:ok, %{turn: nil, status: :idle}} = Agent.snapshot(ref)
    refute inspect({descriptor, ref}) =~ "SECRET"
    for i <- 1..128, do: Registry.register(Agent.Registry, "synthetic#{i}", nil)
    assert {:error, :limit} = Agent.list(node())
  end

  @tag timeout: 10_000
  test "queued confirmation cannot start work after public timeout and helper DOWN" do
    alias Agent.Discovery, as: D
    start_supervised!(Agent.AuthoritySupervisor)
    {:ok, ref} = create("public-late")
    on_exit(fn -> if Process.alive?(ref.pid), do: :sys.resume(ref.pid) end)
    :sys.suspend(ref.pid)
    endpoint = Process.whereis(D.Endpoint)
    :sys.suspend(endpoint)
    started = D.now()
    task = Task.async(fn -> Agent.lookup(node(), "public-late") end)

    await_offer = fn recur ->
      {:messages, messages} = Process.info(endpoint, :messages)

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
    :sys.resume(endpoint)
    # Endpoint creates its offer at t1.5s, expiring at t6.5s.
    _ = :sys.get_state(endpoint)
    :sys.suspend(endpoint)
    Process.sleep(max(0, started + 4600 - D.now()))
    :erlang.resume_process(helper)
    # Client emits confirm with ~400ms remaining, queued at suspended endpoint.
    Process.sleep(30)
    {:messages, queued} = Process.info(endpoint, :messages)
    confirm = Enum.find(queued, &match?({:confirm, _, _, _, _, _}, &1))
    true = is_tuple(confirm)
    assert elem(confirm, 5) > 0
    assert {:error, :timeout} = Task.await(task, 1000)
    refute Process.alive?(helper)
    Process.sleep(150)
    {:messages, []} = Process.info(ref.pid, :messages)
    assert D.now() - started >= 5000
    :sys.resume(endpoint)
    Process.sleep(350)
    {:messages, messages} = Process.info(ref.pid, :messages)
    calls = Enum.count(messages, &match?({:"$gen_call", _, :ref}, &1))
    assert calls == 0
    :sys.resume(ref.pid)

    state = :sys.get_state(endpoint)
    assert map_size(state.active) == 0
  end

  test "queued expired admission responses cannot start workers and passive controllers retire" do
    start_supervised!(Agent.AuthoritySupervisor)
    {:ok, ref} = create("expired-pong")
    :ok = :sys.suspend(ref.pid)
    on_exit(fn -> if Process.alive?(ref.pid), do: :sys.resume(ref.pid) end)
    endpoint = Process.whereis(Agent.Discovery.Endpoint)
    reply = :erlang.alias()
    on_exit(fn -> :erlang.unalias(reply) end)

    for delay <- [120, 300] do
      send(endpoint, {:offer, self(), reply})
      assert_receive {^reply, {:offer, ^endpoint, token}}
      send(endpoint, {:confirm, self(), reply, token, {:lookup, "expired-pong", nil}, 5000})
      assert_receive {^reply, {:ping, controller, challenge}}
      monitor = Process.monitor(controller)
      :erlang.suspend_process(controller)
      # A small reported budget or a response older than the lease must expire,
      # even when its message precedes the receive timeout in the mailbox.
      send(controller, {:pong, challenge, if(delay == 120, do: 100, else: 5000)})
      Process.sleep(delay)
      :erlang.resume_process(controller)
      assert_receive {:DOWN, ^monitor, _, _, _}, 500
      assert {:messages, []} = Process.info(ref.pid, :messages)
    end

    for _ <- 1..256, do: send(endpoint, {:offer, self(), reply})

    for _ <- 1..256 do
      assert_receive {^reply, {:offer, ^endpoint, token}}
      send(endpoint, {:confirm, self(), reply, token, :list, 5000})
    end

    Process.sleep(350)
    assert map_size(:sys.get_state(endpoint).active) == 0
  end

  test "delayed heartbeat response cannot renew an expired lease" do
    start_supervised!(Agent.AuthoritySupervisor)
    {:ok, ref} = create("heartbeat")
    :ok = :sys.suspend(ref.pid)
    on_exit(fn -> if Process.alive?(ref.pid), do: :sys.resume(ref.pid) end)
    endpoint = Process.whereis(Agent.Discovery.Endpoint)
    reply = :erlang.alias()
    send(endpoint, {:offer, self(), reply})
    assert_receive {^reply, {:offer, ^endpoint, token}}
    send(endpoint, {:confirm, self(), reply, token, {:lookup, "heartbeat", nil}, 5000})
    assert_receive {^reply, {:ping, controller, challenge}}
    send(controller, {:pong, challenge, 5000})
    assert_receive {^reply, {:ping, ^controller, heartbeat}}, 500
    {:links, links} = Process.info(controller, :links)
    worker = Enum.find(links, &(&1 != endpoint))
    cm = Process.monitor(controller)
    wm = Process.monitor(worker)
    :erlang.suspend_process(controller)
    send(controller, {:pong, heartbeat, 5000})
    Process.sleep(300)
    :erlang.resume_process(controller)
    assert_receive {:DOWN, ^cm, _, _, _}, 500
    assert_receive {:DOWN, ^wm, _, _, _}, 500
    :erlang.unalias(reply)
  end

  @tag timeout: 8000
  test "requester refuses a queued heartbeat after its own deadline" do
    Process.register(self(), Agent.Discovery.Endpoint)
    started = Agent.Discovery.now()
    task = Task.async(fn -> Agent.list(node()) end)
    assert_receive {:offer, helper, reply}
    send(reply, {reply, {:offer, self(), make_ref()}})
    assert_receive {:confirm, ^helper, ^reply, _, :list, _}
    {:links, [stream]} = Process.info(helper, :links)
    :erlang.suspend_process(stream)
    :erlang.suspend_process(helper)
    challenge = make_ref()
    send(reply, {reply, {:ping, self(), challenge}})
    Process.sleep(max(0, started + 5100 - Agent.Discovery.now()))
    :erlang.resume_process(helper)
    refute_receive {:pong, ^challenge, _}, 100
    :erlang.resume_process(stream)
    assert {:error, :timeout} = Task.await(task, 1000)
  end

  defp await_controller(endpoint, remaining \\ 100) do
    case Map.keys(:sys.get_state(endpoint).active) do
      [] when remaining > 0 ->
        Process.sleep(10)
        await_controller(endpoint, remaining - 1)

      [] ->
        flunk("query controller absent")

      [pid | _] ->
        pid
    end
  end
end
