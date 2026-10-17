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

  test "local bounded entry validates queries and budgets" do
    for budget <- [0, -1, 5001, :infinity],
        do: assert({:error, :invalid_query} = Agent.Discovery.query_local(:list, budget))

    assert {:error, :invalid_query} = Agent.Discovery.query_local({:lookup, "", nil}, 100)
  end

  test "finite read timeout and execution death preserve identity island" do
    start_supervised!(Agent.AuthoritySupervisor)
    {:ok, ref} = create("blocked")
    registry = Process.whereis(Agent.Registry)
    agents = Process.whereis(Agent.Agents)
    :ok = :sys.suspend(ref.pid)
    on_exit(fn -> if Process.alive?(ref.pid), do: :sys.resume(ref.pid) end)
    assert {:ok, [_]} = Agent.list(node())
    assert {:error, :timeout} = Agent.Discovery.query_local({:lookup, "blocked", nil}, 30)
    :ok = :sys.resume(ref.pid)
    :ok = :sys.suspend(ref.pid)
    worker = spawn(fn -> Agent.Discovery.query_local({:lookup, "blocked", nil}, 5000) end)
    assert ^worker = await_reader(ref.pid)
    monitor = Process.monitor(worker)
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^monitor, _, _, :killed}
    assert Process.whereis(Agent.Registry) == registry
    assert Process.whereis(Agent.Agents) == agents
    assert Process.alive?(ref.pid)
    :ok = :sys.resume(ref.pid)
    assert {:ok, ^ref} = Agent.lookup(node(), "blocked")
    assert {:ok, %{status: :idle, turn: nil}} = Agent.snapshot(ref)
  end

  @tag timeout: 8000
  test "public local deadline retires actual helper without changing identity" do
    start_supervised!(Agent.AuthoritySupervisor)
    {:ok, ref} = create("local-deadline")
    :ok = :sys.suspend(ref.pid)
    on_exit(fn -> if Process.alive?(ref.pid), do: :sys.resume(ref.pid) end)
    caller = self()
    spawn(fn -> send(caller, {:reader, await_reader(ref.pid)}) end)
    assert {:error, :timeout} = Agent.lookup(node(), "local-deadline")
    assert_receive {:reader, worker}
    refute Process.alive?(worker)
    :ok = :sys.resume(ref.pid)
    assert {:ok, ^ref} = Agent.lookup(node(), "local-deadline")
    refute_receive {_, {:ok, _}}, 50
  end

  test "public caller exit retires its local helper while Server remains suspended" do
    start_supervised!(Agent.AuthoritySupervisor)
    {:ok, ref} = create("caller-exit")
    :ok = :sys.suspend(ref.pid)
    on_exit(fn -> if Process.alive?(ref.pid), do: :sys.resume(ref.pid) end)
    caller = spawn(fn -> Agent.lookup(node(), "caller-exit") end)
    worker = await_reader(ref.pid)
    monitor = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}, 1500
    assert Process.alive?(ref.pid)
    :ok = :sys.resume(ref.pid)
    assert {:ok, ^ref} = Agent.lookup(node(), "caller-exit")
  end

  defp await_reader(server, attempts \\ 100) do
    {:messages, messages} = Process.info(server, :messages)

    case Enum.find(messages, &match?({:"$gen_call", _, :ref}, &1)) do
      {:"$gen_call", {pid, _}, :ref} ->
        pid

      nil ->
        assert attempts > 0
        Process.sleep(10)
        await_reader(server, attempts - 1)
    end
  end
end
