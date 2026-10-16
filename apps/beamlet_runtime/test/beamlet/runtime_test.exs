defmodule Beamlet.RuntimeTest do
  use ExUnit.Case
  alias Beamlet.Actions.Operation
  alias Beamlet.Runtime

  setup do
    provider =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> Process.exit(provider, :kill) end)

    start_supervised!(
      {Runtime.SharedSupervisor,
       execution: true,
       handlers: %{"echo" => {Runtime.TestHandler, self()}},
       providers: [provider],
       capabilities: ["math"],
       environments: ["test"],
       pools: %{"cpu" => 1},
       limits: [coordinators: 4, refresh_ms: 10, expiry_ms: 100, retention_ms: 300, cancel_ms: 20]}
    )

    Runtime.TestPeer.barrier("echo")
    %{provider: provider}
  end

  defp operation(attrs \\ []), do: elem(Operation.new([kind: "echo"] ++ attrs), 1)

  test "successful result is accepted once and retained only boundedly" do
    assert {:ok, ref} = Runtime.submit(operation())
    assert_receive {:beamlet_operation, ^ref, {:result, result}}, 1000
    assert result.status == :ok
    assert {:ok, %{result: ^result, execution: execution}} = Runtime.status(ref)
    send(ref.pid, {:completed, execution.attempt_id, execution.handle, %{result | value: "late"}})
    assert {:ok, %{result: ^result}} = Runtime.status(ref)
    mon = Process.monitor(ref.pid)
    assert_receive {:DOWN, ^mon, _, _, :normal}, 1000
    assert {:error, :unavailable} = Runtime.status(ref)
  end

  test "no eligible target creates no execution" do
    {:ok, ref} = Runtime.submit(operation(capabilities: ["absent"]))
    assert_receive {:beamlet_operation, ^ref, {:result, %{reason: :no_target, execution_id: nil}}}
    assert {:ok, %{execution: nil}} = Runtime.status(ref)
  end

  test "atomic admission under stale capacity and cancellation release" do
    op = operation(payload: %{"mode" => "hold"}, claims: %{"cpu" => 1})
    {:ok, first} = Runtime.submit(op)
    assert_receive {:worker, worker}
    {:ok, second} = Runtime.submit(op)
    assert_receive {:beamlet_operation, ^second, {:result, %{status: :error}}}
    assert :ok = Runtime.cancel(first)
    assert_receive {:beamlet_operation, ^first, {:result, %{status: :cancelled}}}, 1000
    refute Process.alive?(worker)
    assert :sys.get_state(Runtime.ExecutorGateway).available == %{"cpu" => 1}
  end

  test "deadline and owner loss stop workers without blocking gateway" do
    {:ok, ref} = Runtime.submit(operation(payload: %{"mode" => "hold"}, budget_ms: 50))
    assert_receive {:worker, worker}
    monitor = Process.monitor(worker)
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :deadline}}}, 1000
    assert_receive {:DOWN, ^monitor, _, _, _}, 1000

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, lost} = Runtime.submit(operation(payload: %{"mode" => "hold"}), owner: owner)
    assert_receive {:worker, worker2}
    monitor2 = Process.monitor(worker2)
    send(owner, :stop)
    assert_receive {:beamlet_operation, ^lost, {:result, %{status: :uncertain}}}, 1000
    assert_receive {:DOWN, ^monitor2, _, _, _}, 1000
  end

  test "progress credits and absolute producer rate bound sink messages" do
    {:ok, ref} = Runtime.submit(operation(payload: %{"mode" => "progress"}))
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok}}}, 1000

    events =
      for _ <- 1..16 do
        assert_receive {:beamlet_operation, ^ref, {:progress, _, seq, _}}
        seq
      end

    assert events == Enum.to_list(1..16)
    refute_receive {:beamlet_operation, ^ref, {:progress, _, _, _}}
  end

  test "gateway restart kills accounting island and never replays work" do
    {:ok, ref} = Runtime.submit(operation(payload: %{"mode" => "hold"}))
    assert_receive {:worker, worker}
    monitor = Process.monitor(worker)
    Process.exit(Process.whereis(Runtime.ExecutorGateway), :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}, 1000
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: status}}}, 3000
    assert status in [:deadline, :uncertain]
    refute_receive {:worker, _}
  end

  test "provider loss withdraws readiness and stops affected workers", %{provider: provider} do
    {:ok, ref} = Runtime.submit(operation(payload: %{"mode" => "hold"}))
    assert_receive {:worker, worker}
    monitor = Process.monitor(worker)
    Process.exit(provider, :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}, 1000
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :error}}}, 1000
    refute :sys.get_state(Runtime.ExecutorGateway).ready
  end

  test "wrong incarnation and duplicate dispatch cannot create another worker" do
    {:ok, ref} = Runtime.submit(operation(payload: %{"mode" => "hold"}))
    assert_receive {:worker, worker}
    {:ok, %{execution: execution}} = Runtime.status(ref)
    op = operation(payload: %{"mode" => "hold"})

    send(
      execution.endpoint,
      {:admit, ref.pid, ref.id, execution.attempt_id, execution.incarnation,
       System.monotonic_time(:millisecond), op, 1000}
    )

    send(
      execution.endpoint,
      {:admit, self(), "wrong", "wrong", make_ref(), System.monotonic_time(:millisecond), op,
       1000}
    )

    assert_receive {:rejected, "wrong", :ineligible}
    refute_receive {:worker, _}
    send(worker, :release)
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok}}}
  end

  test "coordinator count includes retained results and oversize output is explicit" do
    refs =
      for _ <- 1..4 do
        {:ok, ref} = Runtime.submit(operation(payload: %{"mode" => "oversize"}))

        assert_receive {:beamlet_operation, ^ref,
                        {:result, %{reason: :invalid_or_oversize_result}}},
                       1000

        ref
      end

    assert {:error, :capacity} = Runtime.submit(operation())
    assert length(refs) == 4
  end

  test "timer escalation kills a trapping worker while gateway remains responsive" do
    {:ok, ref} = Runtime.submit(operation(payload: %{"mode" => "trap"}))
    assert_receive {:worker, worker}
    monitor = Process.monitor(worker)
    assert :ok = Runtime.cancel(ref)
    {:ok, other} = Runtime.submit(operation())
    assert_receive {:beamlet_operation, ^other, {:result, %{status: :ok}}}, 1000
    assert_receive {:DOWN, ^monitor, _, _, :killed}, 1000
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :cancelled}}}, 1000
  end

  test "coordinator death releases worker and shared restart invalidates refs" do
    {:ok, ref} = Runtime.submit(operation(payload: %{"mode" => "hold"}))
    assert_receive {:worker, worker}
    monitor = Process.monitor(worker)
    Process.exit(ref.pid, :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}, 1000
    {:ok, retained} = Runtime.submit(operation())
    assert_receive {:beamlet_operation, ^retained, {:result, _}}
    monitor2 = Process.monitor(retained.pid)
    Process.exit(Process.whereis(Runtime.Groups), :kill)
    assert_receive {:DOWN, ^monitor2, _, _, _}, 1000
    assert {:error, :unavailable} = Runtime.status(retained)
    refute_receive {:worker, _}
  end

  test "guarded and generic admission preserve validation, limits and capacity" do
    for guarded <- [false, true] do
      assert {:error, :invalid_operation} =
               Runtime.submit(%{operation() | budget_ms: 0}, require_live_owner: guarded)

      assert {:error, :invalid_operation} = Runtime.submit(operation(), owner: :invalid)
      assert {:error, :invalid_operation} = Runtime.submit(operation(), sink: :invalid)
      assert {:ok, ref} = Runtime.submit(operation(), require_live_owner: guarded)
      assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok}}}, 1000
    end

    :sys.replace_state(Runtime.Directory, fn s ->
      %{s | limits: %{s.limits | operation_bytes: 1024}}
    end)

    for guarded <- [false, true] do
      assert {:error, :invalid_operation} =
               Runtime.submit(operation(payload: %{"data" => String.duplicate("x", 1200)}),
                 require_live_owner: guarded
               )
    end

    for _ <- 1..2 do
      assert {:ok, _} = Runtime.submit(operation(payload: %{"mode" => "hold"}))
      assert_receive {:worker, _}
    end

    for guarded <- [false, true] do
      assert {:error, :capacity} = Runtime.submit(operation(), require_live_owner: guarded)
    end
  end

  test "dead local ownership is unavailable without dispatch" do
    owner = idle_owner()
    kill_and_wait(owner)

    assert {:error, :unavailable} =
             Runtime.submit(operation(), owner: owner, require_live_owner: true)

    assert DynamicSupervisor.count_children(Runtime.Coordinators).active == 0
    refute_receive {:worker, _}
  end

  test "owner DOWN before resuming blocked admission prevents late dispatch at every read" do
    Enum.each([:public_limits, :supervisor, :init_limits, :select], fn stage ->
      owner = idle_owner()
      parent = self()
      directory = Process.whereis(Runtime.Directory)
      supervisor = Process.whereis(Runtime.Coordinators)

      if stage == :public_limits, do: :sys.suspend(directory), else: :sys.suspend(supervisor)

      submitter =
        spawn(fn ->
          result =
            Runtime.submit(operation(payload: %{"mode" => "hold"}),
              owner: owner,
              sink: parent,
              require_live_owner: true
            )

          send(parent, {:submission, result})
        end)

      blocked = if stage == :public_limits, do: directory, else: supervisor
      queued_call(blocked, submitter)

      if stage in [:init_limits, :select] do
        :sys.suspend(directory)
        :sys.resume(supervisor)
        coordinator = queued_call(directory, :any)

        if stage == :select do
          :erlang.suspend_process(coordinator)
          :sys.resume(directory)
          :sys.get_state(directory)
          :sys.suspend(directory)
          :erlang.resume_process(coordinator)
          queued_call(directory, coordinator)
        end
      end

      kill_and_wait(owner)
      # DOWN is observed while the relevant infrastructure is still suspended.
      if stage == :supervisor, do: :sys.resume(supervisor), else: :sys.resume(directory)

      assert_receive {:submission, result}, 1000

      if stage == :select do
        assert {:ok, ref} = result
        mon = Process.monitor(ref.pid)
        assert_receive {:DOWN, ^mon, :process, _, _}, 1000
      else
        assert result == {:error, :unavailable}
      end

      assert DynamicSupervisor.count_children(supervisor).active == 0
      refute_receive {:worker, _}, 150
    end)
  end

  test "missing Directory and missing coordinator supervisor normalize to unavailable" do
    directory = Process.whereis(Runtime.Directory)
    Process.unregister(Runtime.Directory)

    try do
      for guarded <- [false, true] do
        assert {:error, :unavailable} = Runtime.submit(operation(), require_live_owner: guarded)
      end
    after
      Process.register(directory, Runtime.Directory)
    end

    supervisor = Process.whereis(Runtime.Coordinators)
    Process.unregister(Runtime.Coordinators)

    try do
      for guarded <- [false, true] do
        assert {:error, :unavailable} = Runtime.submit(operation(), require_live_owner: guarded)
      end
    after
      Process.register(supervisor, Runtime.Coordinators)
    end
  end

  defp idle_owner, do: spawn(fn -> receive do: (:stop -> :ok) end)

  defp kill_and_wait(pid) do
    mon = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^mon, :process, ^pid, :killed}, 1000
  end

  defp queued_call(pid, caller, attempts \\ 200)
  defp queued_call(_, _, 0), do: flunk("admission did not reach blocked call")

  defp queued_call(pid, caller, attempts) do
    {:messages, messages} = Process.info(pid, :messages)

    case Enum.find(messages, fn
           {:"$gen_call", {from, _}, _} -> caller == :any or from == caller
           _ -> false
         end) do
      {:"$gen_call", {from, _}, _} ->
        from

      nil ->
        receive do
        after
          5 -> queued_call(pid, caller, attempts - 1)
        end
    end
  end
end
