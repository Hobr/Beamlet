defmodule Beamlet.RuntimeDistributedTest do
  use ExUnit.Case
  @moduletag :distributed
  alias Beamlet.Actions.Operation
  alias Beamlet.Runtime

  setup do
    unless Node.alive?(), do: flunk("distributed tests require a named VM")
    name = String.to_atom("beamlet_peer_#{System.unique_integer([:positive])}")
    paths = :code.get_path() |> Enum.flat_map(fn path -> [~c"-pa", path] end)

    {:ok, peer, remote} =
      :peer.start_link(%{
        name: name,
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())] ++ paths,
        wait_boot: 10_000,
        shutdown: 3_000
      })

    Process.unlink(peer)

    on_exit(fn ->
      monitor = Process.monitor(peer)

      try do
        if Process.alive?(peer), do: :peer.stop(peer)
      catch
        :exit, {:noproc, _} -> :ok
        :exit, {:normal, _} -> :ok
      end

      assert_receive {:DOWN, ^monitor, :process, ^peer, _}, 4000
      assert Node.disconnect(remote) in [true, false, :ignored]
    end)

    :ok =
      :peer.call(peer, Runtime.TestPeer, :boot, [
        [
          execution: true,
          handlers: %{"echo" => {Runtime.TestHandler, self()}},
          pools: %{"cpu" => 1},
          capabilities: ["remote"],
          limits: [refresh_ms: 20, expiry_ms: 100]
        ]
      ])

    start_supervised!(
      {Runtime.SharedSupervisor,
       limits: [refresh_ms: 20, expiry_ms: 100, admission_ms: 500, cancel_ms: 20]}
    )

    true = Node.connect(remote)
    Runtime.TestPeer.barrier("echo", 4000)
    %{peer: peer, remote: remote}
  end

  defp op(remote, attrs \\ []),
    do:
      elem(
        Operation.new([kind: "echo", allowed_nodes: [remote], claims: %{"cpu" => 1}] ++ attrs),
        1
      )

  test "remote gateway enforces credential-inclusive deployment cap", %{
    peer: peer,
    remote: remote
  } do
    :ok = :peer.call(peer, Runtime.TestPeer, :operation_cap, [1024])
    base = op(remote, credentials: %{"token" => ""})

    exact = %{
      base
      | credentials: %{"token" => String.duplicate("x", 1024 - :erlang.external_size(base))}
    }

    over = %{exact | credentials: Map.update!(exact.credentials, "token", &(&1 <> "x"))}
    assert :erlang.external_size(exact) == 1024
    assert :ok = Operation.validate(over)
    # Public cap remains larger: executor must independently reject this invocation.
    assert {:ok, ref} = Runtime.submit(over)
    assert_receive {:beamlet_operation, ^ref, {:result, %{reason: :ineligible} = rejected}}, 3000
    assert rejected.value == nil
    refute inspect(rejected) =~ "credentials:"
    assert {:ok, snapshot} = Runtime.status(ref)
    refute inspect(snapshot) =~ "credentials:"
    state = :peer.call(peer, :sys, :get_state, [Runtime.ExecutorGateway])
    assert state.tasks == %{}
    assert state.available == %{"cpu" => 1}
    assert {:ok, accepted} = Runtime.submit(exact)
    assert_receive {:beamlet_operation, ^accepted, {:result, %{status: :ok}}}, 3000
  end

  test "credentials reach the handler unchanged and stay absent from generated outputs", %{
    remote: remote
  } do
    credentials = %{
      "token" => "synthetic-operation-only",
      "session" => [%{"credentials" => [true, nil, 4]}]
    }

    operation = op(remote, payload: %{"mode" => "credentials"}, credentials: credentials)
    assert {:ok, ref} = Runtime.submit(operation, require_live_owner: true)
    assert_receive {:credentials, executor, ^credentials}, 3000
    assert executor == remote
    assert_receive {:beamlet_operation, ^ref, {:progress, _, seq, "working"}}, 3000
    :ok = Runtime.ack(ref, seq)
    assert_receive {:beamlet_operation, ^ref, {:result, result}}, 3000
    assert result.status == :ok
    assert result.value == "done"
    assert {:ok, snapshot} = Runtime.status(ref)

    for projection <- [result, snapshot, Runtime.Directory.snapshots()] do
      refute inspect(projection) =~ "synthetic-operation-only"
      refute inspect(projection) =~ "credentials:"
      refute inspect(projection) =~ ~s("credentials" =>)
    end
  end

  test "remote execution, stale duplicate result, and no local fallback", %{
    peer: peer,
    remote: remote
  } do
    remote_owner = :peer.call(peer, :erlang, :whereis, [:init])

    assert {:error, :invalid_operation} =
             Runtime.submit(op(remote), owner: remote_owner, require_live_owner: true)

    assert {:ok, generic} =
             Runtime.submit(op(remote, payload: %{"mode" => "hold"}), owner: remote_owner)

    assert_receive {:worker, worker}, 3000

    await(
      fn ->
        Enum.any?(Runtime.Directory.snapshots(), fn {_, r} ->
          r.node == remote and r.ready and r.available == %{"cpu" => 0}
        end)
      end,
      "Directory did not observe the occupied remote pool"
    )

    endpoint = :peer.call(peer, Process, :whereis, [Runtime.NodeEndpoint])
    :ok = :peer.call(peer, :sys, :suspend, [endpoint])

    # Completion and gateway release do not refresh the independent Directory cache.
    # Hold reports across completion to exercise that ordering deterministically.
    try do
      send(worker, :release)
      assert_receive {:beamlet_operation, ^generic, {:result, %{status: :ok}}}, 3000
      await_gateway_capacity(peer)

      assert Enum.any?(Runtime.Directory.snapshots(), fn {_, r} ->
               r.node == remote and r.available == %{"cpu" => 0}
             end)
    after
      :ok = :peer.call(peer, :sys, :resume, [endpoint])
    end

    await_capacity_report(peer, remote)
    {:ok, ref} = Runtime.submit(op(remote))
    assert_receive {:beamlet_operation, ^ref, {:result, result}}, 3000

    assert result.status == :ok,
           "second submission: #{inspect(Map.take(result, [:status, :reason]))}"

    assert result.value["node"] == Atom.to_string(remote)
    {:ok, %{execution: e}} = Runtime.status(ref)
    send(ref.pid, {:completed, "stale", e.handle, %{result | value: "wrong"}})
    assert {:ok, %{result: ^result}} = Runtime.status(ref)
    {:ok, absent} = Runtime.submit(op(remote, environment: "absent"))
    assert_receive {:beamlet_operation, ^absent, {:result, %{reason: :no_target}}}
    assert {:ok, %{execution: nil}} = Runtime.status(absent)
  end

  test "concurrent remote admissions charge once and coordinator death cleans worker", %{
    peer: peer,
    remote: remote
  } do
    operation = op(remote, payload: %{"mode" => "hold"})
    parent = self()

    callers =
      for _ <- 1..2 do
        spawn_link(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> :ok
          end

          send(parent, {:submitted, Runtime.submit(operation, owner: parent, sink: parent)})
        end)
      end

    Enum.each(callers, fn caller -> assert_receive {:ready, ^caller} end)
    Enum.each(callers, &send(&1, :go))

    refs =
      for _ <- 1..2 do
        assert_receive {:submitted, {:ok, ref}}
        ref
      end

    assert_receive {:worker, worker}, 3000
    assert_receive {:beamlet_operation, rejected, {:result, %{status: :error}}}, 3000
    assert rejected in refs
    first = Enum.find(refs, &(&1 != rejected))
    running = :peer.call(peer, :sys, :get_state, [Runtime.ExecutorGateway])
    assert running.available == %{"cpu" => 0}
    assert map_size(running.tasks) == 1
    Process.exit(first.pid, :kill)
    assert :ok = await_dead(peer, worker)
    state = :peer.call(peer, :sys, :get_state, [Runtime.ExecutorGateway])
    assert state.available == %{"cpu" => 1}
    assert map_size(state.tasks) == 0
  end

  test "partition is uncertain; alternate stdio verifies remote cleanup and no replay", %{
    peer: peer,
    remote: remote
  } do
    {:ok, ref} = Runtime.submit(op(remote, payload: %{"mode" => "hold"}))
    assert_receive {:worker, worker}, 3000
    assert true = Node.disconnect(remote)

    assert_receive {:beamlet_operation, ^ref,
                    {:result, %{status: :uncertain, reason: :connection_lost}}},
                   3000

    assert :ok = await_dead(peer, worker)
    assert true = Node.connect(remote)
    Runtime.TestPeer.barrier("echo", 4000)
    refute_receive {:worker, _}, 100
    {:ok, next} = Runtime.submit(op(remote))
    assert_receive {:beamlet_operation, ^next, {:result, %{status: :ok}}}, 3000
  end

  test "uncertain admission never triggers a second placement", %{peer: peer, remote: remote} do
    endpoint = :peer.call(peer, Process, :whereis, [Runtime.NodeEndpoint])
    :ok = :peer.call(peer, :sys, :suspend, [endpoint])
    :ok = :peer.call(peer, :sys, :suspend, [Runtime.ExecutorGateway])
    {:ok, ref} = Runtime.submit(op(remote, payload: %{"mode" => "hold"}))

    assert_receive {:beamlet_operation, ^ref,
                    {:result, %{status: :uncertain, reason: :admission_timeout}}},
                   3000

    :ok = :peer.call(peer, :sys, :resume, [endpoint])
    _ = :peer.call(peer, :sys, :get_state, [endpoint])
    gateway = :peer.call(peer, Process, :whereis, [Runtime.ExecutorGateway])

    {:ok, queued} =
      :peer.call(peer, Process, :info, [gateway, :messages])
      |> then(fn {:messages, messages} -> {:ok, messages} end)

    assert Enum.count(queued, &match?({:admit, _, _, _, _, _, _, _}, &1)) == 1
    :ok = :peer.call(peer, :sys, :resume, [gateway])
    state = :peer.call(peer, :sys, :get_state, [gateway])
    assert map_size(state.tasks) == 0
    assert state.available == %{"cpu" => 1}
    assert Enum.count(state.attempts, fn {_, value} -> value == :rejected end) == 1
    refute_receive {:worker, _}
    assert {:ok, %{result: %{status: :uncertain}}} = Runtime.status(ref)
  end

  defp await_gateway_capacity(peer) do
    await(
      fn ->
        state = :peer.call(peer, :sys, :get_state, [Runtime.ExecutorGateway])
        state.ready and state.available == %{"cpu" => 1} and map_size(state.tasks) == 0
      end,
      "remote gateway did not release its worker and pool"
    )
  end

  defp await_capacity_report(peer, remote) do
    await_gateway_capacity(peer)
    # Both timestamps come from the executor's clock. Require a report generated
    # after observed release, so an older idle report cannot satisfy this barrier.
    released_at = :peer.call(peer, System, :monotonic_time, [:millisecond])

    await(
      fn ->
        case Runtime.Directory.select(op(remote)) do
          {:ok, _, report} -> report.node == remote and report.lease > released_at
          :none -> false
        end
      end,
      "Directory did not observe a new eligible remote capacity report"
    )
  end

  defp await(condition, message),
    do: await(condition, message, System.monotonic_time(:millisecond) + 3000)

  defp await(condition, message, deadline) do
    if condition.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline, do: flunk(message)
      await(condition, message, deadline)
    end
  end

  defp await_dead(peer, pid),
    do: await_dead(peer, pid, System.monotonic_time(:millisecond) + 3000)

  defp await_dead(peer, pid, deadline) do
    if :peer.call(peer, Process, :alive?, [pid]) do
      if System.monotonic_time(:millisecond) > deadline,
        do: flunk("remote worker survived cleanup")

      receive do
      after
        10 -> await_dead(peer, pid, deadline)
      end
    else
      :ok
    end
  end
end
