defmodule Beamlet.Web.HostTest do
  use ExUnit.Case
  alias Beamlet.Web.{Agents, Handles, Host, Presets}

  setup do
    previous = Application.get_env(:beamlet_web, :host)
    :ok = Application.stop(:beamlet_web)

    on_exit(fn ->
      Application.stop(:beamlet_web)

      if previous,
        do: Application.put_env(:beamlet_web, :host, previous),
        else: Application.delete_env(:beamlet_web, :host)

      {:ok, _} = Application.ensure_all_started(:beamlet_web)
    end)

    :ok
  end

  defp example do
    Config.Reader.read!(Path.expand("../../priv/examples/host.exs", __DIR__))[:beamlet_web][:host]
  end

  defp enable(settings) do
    Application.put_env(:beamlet_web, :host, settings)
    assert {:ok, _} = Application.ensure_all_started(:beamlet_web)
  end

  test "disabled host isolates roles and connections while endpoint stays available" do
    peers = Node.list(:connected)
    enable([])
    assert Supervisor.which_children(Host) == []

    for name <- [
          Beamlet.Node,
          Beamlet.Agent.Registry,
          Beamlet.Runtime.ExecutorGateway,
          Presets,
          Handles
        ],
        do: assert(Process.whereis(name) == nil)

    assert Node.list(:connected) == peers
    assert Process.whereis(Beamlet.Web.Endpoint)
  end

  test "all four interaction-containing subsets compose actual trees" do
    for roles <- [
          [:interaction],
          [:interaction, :authority],
          [:interaction, :executor],
          [:interaction, :authority, :executor]
        ] do
      enable(enabled: true, node: [roles: roles])
      assert {:ok, %{roles: ^roles}} = Beamlet.Node.observation()
      assert is_pid(Process.whereis(Beamlet.Agent.Registry)) == :authority in roles
      assert is_pid(Process.whereis(Beamlet.Runtime.ExecutorGateway)) == :executor in roles
      :ok = Application.stop(:beamlet_web)
    end
  end

  test "malformed startup config rejects with static error before role startup" do
    for settings <- [
          [enabled: :yes],
          [node: [roles: [:authority]]],
          [node: [roles: [:interaction, :interaction]]],
          [node: [limits: [refresh_ms: 0], roles: [:interaction]]],
          [peers: ["untrusted@localhost"]],
          [enabled: true, enabled: true],
          [catalogue: %{root: "PRIVATE"}]
        ] do
      assert {:error, :invalid_web_host_configuration} = Host.configuration(settings)
      assert Process.whereis(Beamlet.Node) == nil
    end
  end

  test "confirmed creation plus rejected input retains instance, immutable metadata, reset and handles" do
    enable(
      Keyword.put(example(), :node,
        roles: [:interaction, :authority],
        limits: [operation_bytes: 1024]
      )
    )

    {:ok, d} = Presets.reset("basic")

    assert {:created,
            %{ref: ref, navigation: {:ok, handle}, input: {:rejected, :invalid_or_oversize_input}}} =
             traced_create(%{d | "task" => String.duplicate("x", 2000)}, 1)

    assert {:ok, ^ref} = Handles.fetch(handle)

    assert {:ok, %{status: :idle, display: %{metadata: metadata}}} =
             Beamlet.Agent.snapshot(ref, view: :display)

    assert metadata.title == d["title"]
    assert {:ok, ^d} = Presets.reset("basic")

    assert {:ok, ^ref} =
             Beamlet.Agent.lookup(%{authority: ref.authority, id: ref.id, pid: ref.pid})

    assert :ok = Beamlet.Agent.close(ref)
    assert {:error, :stale_handle} = Handles.fetch(handle)
    # Replacing the same ID cannot retarget old handles.
    {:ok, resolved} = Presets.resolve(d)
    {:ok, replacement} = Beamlet.Agent.start(node(), Keyword.put(resolved.options, :id, ref.id))
    assert replacement.pid != ref.pid
    assert {:error, :stale_handle} = Handles.fetch(handle)
    assert :ok = Beamlet.Agent.close(replacement)
  end

  test "actual local model completes and observing/restarting navigation never closes it" do
    enable(example())
    wait_ready(100)
    {:ok, d} = Presets.reset("basic")

    assert {:created, %{ref: ref, navigation: {:ok, handle}, input: {:accepted, _}}} =
             Agents.create(%{d | "task" => "hello"})

    assert :ok = Beamlet.Agent.subscribe(ref)
    wait_done(ref, 100)
    assert :ok = Beamlet.Agent.unsubscribe(ref)
    :ok = Supervisor.terminate_child(Host, Handles)
    {:ok, _} = Supervisor.restart_child(Host, Handles)
    assert {:error, :stale_handle} = Handles.fetch(handle)
    assert {:ok, %{status: :done, final: "Local example response"}} = Beamlet.Agent.snapshot(ref)
    assert {:ok, _} = Agents.attach(%{authority: ref.authority, id: ref.id, pid: ref.pid})
  end

  test "idle expiry and capacity are bounded without retaining Agent ownership" do
    enable(example())
    {:ok, d} = Presets.reset("basic")
    {:created, %{ref: ref, navigation: {:ok, handle}}} = Agents.create(d)

    :sys.replace_state(Handles, fn state ->
      Map.new(state, fn {k, e} -> {k, %{e | touched: e.touched - 3_600_001}} end)
    end)

    assert {:error, :stale_handle} = Handles.fetch(handle)
    assert Process.alive?(ref.pid)
    descriptor = %{authority: ref.authority, id: ref.id, pid: ref.pid}
    {:ok, h} = Handles.remember(descriptor)

    :sys.replace_state(Handles, fn state ->
      entry = state[h]
      Map.new(1..4096, &{to_string(&1), entry})
    end)

    assert {:error, :handle_limit} = Handles.remember(descriptor)
    assert map_size(:sys.get_state(Handles)) == 4096
  end

  test "unreachable remote creation is unknown and is never resubmitted" do
    c = example()[:catalogue]
    name = "web_missing@localhost"
    c = %{c | authorities: %{"local" => %{title: "Remote", target: name}}}
    enable(enabled: true, node: [roles: [:interaction]], allowed_nodes: [name], catalogue: c)
    {:ok, d} = Presets.reset("basic")
    assert {:create_unknown, %{id: "web-" <> _, authority: _}} = traced_create(d, 0)
    assert :sys.get_state(Handles) == %{}
    assert {:rejected, :invalid_draft} = Agents.create(Map.put(d, "module", String))
  end

  test "lost input acknowledgement is unknown without closing or recreating" do
    enable(example())
    {:ok, d} = Presets.reset("basic")
    {:created, %{ref: ref}} = Agents.create(d)
    :ok = :sys.suspend(ref.pid)
    task = Task.async(fn -> Agents.input(ref, "hello") end)
    assert :input_unknown = Task.await(task, 6000)
    assert Process.alive?(ref.pid)
    :ok = :sys.resume(ref.pid)
  end

  test "navigation process loss clears handles without owning embedded Agent lifetime" do
    enable(example())
    {:ok, d} = Presets.reset("basic")
    {:created, %{ref: ref, navigation: {:ok, handle}}} = Agents.create(d)
    navigation = Process.whereis(Handles)
    monitor = Process.monitor(navigation)
    Process.exit(navigation, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^navigation, :killed}
    wait_handles(navigation, 100)
    assert Process.alive?(ref.pid)
    assert {:error, :stale_handle} = Handles.fetch(handle)

    assert {:ok, ^ref} =
             Beamlet.Agent.lookup(%{authority: ref.authority, id: ref.id, pid: ref.pid})
  end

  test "navigation absence preserves confirmed creation and dispatches input once" do
    enable(
      Keyword.put(example(), :node,
        roles: [:interaction, :authority],
        limits: [operation_bytes: 1024]
      )
    )

    {:ok, d} = Presets.reset("basic")
    :ok = Supervisor.terminate_child(Host, Handles)

    assert {:created,
            %{
              ref: ref,
              navigation: {:error, :unavailable},
              input: {:rejected, :invalid_or_oversize_input}
            }} =
             traced_create(%{d | "task" => String.duplicate("x", 2000)}, 1)

    assert {:ok, ^ref} =
             Beamlet.Agent.lookup(%{authority: ref.authority, id: ref.id, pid: ref.pid})

    assert {:error, :unavailable} = Handles.fetch(String.duplicate("x", 32))
    {:ok, _} = Supervisor.restart_child(Host, Handles)
    assert {:ok, handle} = Agents.attach(%{authority: ref.authority, id: ref.id, pid: ref.pid})
    assert {:ok, ^ref} = Handles.fetch(handle)
    assert :ok = Beamlet.Agent.close(ref)
  end

  test "navigation timeout preserves confirmed creation while navigation stays suspended" do
    enable(
      Keyword.put(example(), :node,
        roles: [:interaction, :authority],
        limits: [operation_bytes: 1024]
      )
    )

    {:ok, d} = Presets.reset("basic")
    :ok = :sys.suspend(Handles)

    try do
      assert {:created,
              %{
                ref: ref,
                navigation: {:error, :unavailable},
                input: {:rejected, :invalid_or_oversize_input}
              }} =
               traced_create(%{d | "task" => String.duplicate("x", 2000)}, 1)

      assert Process.alive?(ref.pid)
      assert :ok = Beamlet.Agent.close(ref)
    after
      :sys.resume(Handles)
    end
  end

  defp wait_handles(_, 0), do: flunk("navigation did not restart")

  defp wait_handles(previous, n) do
    if is_pid(Process.whereis(Handles)) and Process.whereis(Handles) != previous do
      :ok
    else
      Process.sleep(10)
      wait_handles(previous, n - 1)
    end
  end

  defp traced_create(draft, input_count) do
    for {function, arity} <- [start: 2, input: 2],
        do: :erlang.trace_pattern({Beamlet.Agent, function, arity}, true, [])

    owner = self()

    task =
      Task.async(fn ->
        receive do
          :go -> send(owner, {:creation_result, Agents.create(draft)})
        end

        receive do
          :finish -> :ok
        end
      end)

    try do
      :erlang.trace(task.pid, true, [:call, {:tracer, owner}])
      send(task.pid, :go)
      assert_receive {:creation_result, result}, 6000
      barrier = :erlang.trace_delivered(task.pid)
      assert_receive {:trace_delivered, _, ^barrier}
      pid = task.pid
      assert_receive {:trace, ^pid, :call, {Beamlet.Agent, :start, _}}
      if input_count == 1, do: assert_receive({:trace, ^pid, :call, {Beamlet.Agent, :input, _}})
      refute_receive {:trace, ^pid, :call, {Beamlet.Agent, _, _}}, 20
      result
    after
      send(task.pid, :finish)
      Task.await(task)

      for {function, arity} <- [start: 2, input: 2],
          do: :erlang.trace_pattern({Beamlet.Agent, function, arity}, false, [])
    end
  end

  defp wait_ready(0), do: flunk("executor report absent")

  defp wait_ready(n) do
    {:ok, view} = Beamlet.Runtime.observation()

    if Enum.any?(view.reports, &(&1[:execution_ready] == true)),
      do: :ok,
      else:
        (
          Process.sleep(10)
          wait_ready(n - 1)
        )
  end

  defp wait_done(_, 0), do: flunk("model did not complete")

  defp wait_done(ref, n) do
    receive do
      {:beamlet_agent, ^ref, seq, {:snapshot, snapshot}} ->
        Beamlet.Agent.ack(ref, seq)

        if snapshot.status == :done,
          do: assert(snapshot.final == "Local example response"),
          else: wait_done(ref, n - 1)
    after
      100 -> wait_done(ref, n - 1)
    end
  end
end
