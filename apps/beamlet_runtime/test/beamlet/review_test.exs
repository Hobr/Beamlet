defmodule Beamlet.Runtime.ReviewTest do
  use ExUnit.Case
  alias Beamlet.Actions.Operation
  alias Beamlet.Runtime
  alias Beamlet.Runtime.{Directory, ExecutorGateway, Limits, Report, TestHandler, TestPeer}

  defp boot(limits \\ [], pools \\ %{"cpu" => 1}) do
    start_supervised!(
      {Runtime.SharedSupervisor,
       execution: true,
       handlers: %{"echo" => {TestHandler, self()}},
       pools: pools,
       limits:
         Keyword.merge([refresh_ms: 10, expiry_ms: 100, retention_ms: 200, cancel_ms: 20], limits)}
    )

    TestPeer.barrier("echo")
  end

  defp op(payload \\ %{}), do: elem(Operation.new(kind: "echo", payload: payload), 1)

  test "credential bytes count at the exact deployment envelope boundary at both admissions" do
    boot(operation_bytes: 1024)
    base = %Operation{kind: "echo", credentials: %{"token" => ""}}

    exact = %{
      base
      | credentials: %{"token" => String.duplicate("x", 1024 - :erlang.external_size(base))}
    }

    assert :erlang.external_size(exact) == 1024
    over = %{exact | credentials: Map.update!(exact.credentials, "token", &(&1 <> "x"))}
    assert :ok = Operation.validate(over)

    for guarded <- [false, true] do
      assert {:error, :invalid_operation} = Runtime.submit(over, require_live_owner: guarded)
    end

    gateway = :sys.get_state(ExecutorGateway)

    send(
      ExecutorGateway,
      {:admit, self(), "op", "credential-over", gateway.incarnation,
       System.monotonic_time(:millisecond), over, 1000}
    )

    assert_receive {:rejected, "credential-over", :ineligible}
    assert :sys.get_state(ExecutorGateway).tasks == %{}
    assert {:ok, ref} = Runtime.submit(exact)
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok}}}, 1000
  end

  test "multiple pools charge atomically and duplicate terminal messages release once" do
    boot([], %{"cpu" => 1, "io" => 2})

    {:ok, operation} =
      Operation.new(kind: "echo", payload: %{"mode" => "hold"}, claims: %{"cpu" => 1, "io" => 1})

    {:ok, ref} = Runtime.submit(operation)
    assert_receive {:worker, worker}
    {:ok, other} = Runtime.submit(operation)
    assert_receive {:beamlet_operation, ^other, {:result, %{status: :error}}}
    state = :sys.get_state(ExecutorGateway)
    assert state.available == %{"cpu" => 0, "io" => 1}
    [task_ref] = Map.keys(state.tasks)
    send(worker, :release)
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok}}}
    send(ExecutorGateway, {task_ref, {:ok, "duplicate"}})
    send(ExecutorGateway, {:DOWN, task_ref, :process, worker, :shutdown})
    assert :sys.get_state(ExecutorGateway).available == %{"cpu" => 1, "io" => 2}
    refute_receive {:beamlet_operation, ^ref, {:result, _}}
  end

  test "deployment byte overrides bound submit, executor, result and live progress" do
    boot(operation_bytes: 4096, result_bytes: 1024, progress_bytes: 1024)
    large = String.duplicate("x", 4500)
    assert {:error, :invalid_operation} = Runtime.submit(op(large))
    gateway = :sys.get_state(ExecutorGateway)

    send(
      ExecutorGateway,
      {:admit, self(), "op", "big", gateway.incarnation, System.monotonic_time(:millisecond),
       op(large), 1000}
    )

    assert_receive {:rejected, "big", :ineligible}
    {:ok, ref} = Runtime.submit(op(String.duplicate("x", 1500)))

    assert_receive {:beamlet_operation, ^ref, {:result, %{reason: :invalid_or_oversize_result}}},
                   1000

    {:ok, live} = Runtime.submit(op(%{"mode" => "aux"}))
    assert_receive {:worker, worker}
    assert_receive {:large_progress, {:error, :progress_limit}}
    assert_receive {:beamlet_operation, ^live, {:progress, _, 2, "live"}}
    assert {:ok, %{result: nil}} = Runtime.status(live)
    send(worker, :release)
    assert_receive {:beamlet_operation, ^live, {:result, %{status: :ok}}}
  end

  test "progress marshaler dies with worker on coordinator loss" do
    boot()
    {:ok, ref} = Runtime.submit(op(%{"mode" => "aux"}))
    assert_receive {:worker, worker}
    assert_receive {:beamlet_operation, ^ref, {:progress, _, _, _}}
    {:links, links} = Process.info(worker, :links)
    helpers = Enum.filter(links, &(is_pid(&1) and &1 != Process.whereis(Runtime.Workers)))
    assert helpers != []
    monitors = Enum.map([worker | helpers], &Process.monitor/1)
    Process.exit(ref.pid, :kill)
    Enum.each(monitors, fn monitor -> assert_receive {:DOWN, ^monitor, :process, _, _}, 1000 end)
  end

  test "gateway loss stops wrapper-owned progress marshaler" do
    boot()
    {:ok, ref} = Runtime.submit(op(%{"mode" => "aux"}))
    assert_receive {:worker, worker}
    assert_receive {:beamlet_operation, ^ref, {:progress, _, _, _}}
    {:links, links} = Process.info(worker, :links)
    helpers = Enum.filter(links, &(is_pid(&1) and &1 != Process.whereis(Runtime.Workers)))
    assert helpers != []
    monitors = Enum.map([worker | helpers], &Process.monitor/1)
    Process.exit(Process.whereis(ExecutorGateway), :kill)
    Enum.each(monitors, fn monitor -> assert_receive {:DOWN, ^monitor, :process, _, _}, 1000 end)
  end

  test "terminal and stopped coordinators ignore dispatch; cancellation preserves unrelated crash" do
    boot()
    {:ok, ref} = Runtime.submit(op(%{"mode" => "hold"}))
    assert_receive {:worker, worker}
    :sys.suspend(ExecutorGateway)
    assert :ok = Runtime.cancel(ref)
    assert :ok = Runtime.cancel(ref)
    Process.exit(worker, :kill)
    :sys.resume(ExecutorGateway)
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :error, reason: :worker_lost}}}
    send(ref.pid, :dispatch)
    assert {:ok, %{result: %{reason: :worker_lost}}} = Runtime.status(ref)
    refute_receive {:worker, _}
    assert :sys.get_state(ExecutorGateway).available == %{"cpu" => 1}
  end

  test "tombstone saturation cannot admit previously rejected envelope after expiry" do
    boot(attempts: 1, retention_ms: 20, expiry_ms: 30, admission_ms: 20)
    gateway = :sys.get_state(ExecutorGateway)
    lease = System.monotonic_time(:millisecond)
    first = {:admit, self(), "op", "one", gateway.incarnation, lease, op(), 1000}
    send(ExecutorGateway, first)
    assert_receive {:admitted, "one", _}
    assert_receive {:completed, "one", _, _}

    rejected =
      {:admit, self(), "op", "two", gateway.incarnation, lease, op(%{"mode" => "hold"}), 1000}

    send(ExecutorGateway, rejected)
    assert_receive {:rejected, "two", :capacity}
    # A local barrier establishes that the expiry message has actually been handled.
    deadline = System.monotonic_time(:millisecond) + 1000
    wait_empty(deadline)
    send(ExecutorGateway, rejected)
    assert_receive {:rejected, "two", :ineligible}
    send(ExecutorGateway, first)
    assert_receive {:rejected, "one", :capacity}
    refute_receive {:worker, _}
    assert :sys.get_state(ExecutorGateway).available == %{"cpu" => 1}
  end

  defp wait_empty(deadline) do
    if map_size(:sys.get_state(ExecutorGateway).attempts) != 0 do
      assert System.monotonic_time(:millisecond) < deadline

      receive do
      after
        5 -> wait_empty(deadline)
      end
    end
  end

  test "malformed and oversized report replies never enter cache or crash selection" do
    boot()
    endpoint = Process.whereis(Runtime.NodeEndpoint)
    :sys.suspend(endpoint)
    send(Directory, :refresh)
    state = :sys.get_state(Directory)
    nonce = state.pending[endpoint]
    send(Directory, {:report, endpoint, nonce, %{ready: true}})
    assert is_map(Directory.snapshots())
    assert Process.alive?(Process.whereis(Directory))
    report = state.reports[endpoint] |> elem(1)

    send(
      Directory,
      {:report, endpoint, nonce, %{report | capabilities: [String.duplicate("x", 70_000)]}}
    )

    send(Directory, {:report, endpoint, nonce, Map.put(report, :settings, %{token: "secret"})})
    assert Directory.snapshots()[endpoint] == report
    refute Report.valid?(%{ready: true}, endpoint, 65_536)
    :sys.resume(endpoint)
  end

  test "wrong gateway admission and malformed or wrong-source Result cannot capture attempt" do
    boot()
    :sys.suspend(ExecutorGateway)
    {:ok, ref} = Runtime.submit(op(%{"mode" => "hold"}))
    {:ok, %{execution: execution}} = Runtime.status(ref)

    handle = %Beamlet.Actions.ExecutionHandle{
      id: "fake",
      gateway: self(),
      incarnation: execution.incarnation
    }

    send(ref.pid, {:admitted, execution.attempt_id, handle})
    assert {:ok, %{execution: %{handle: nil}}} = Runtime.status(ref)

    bad = %Beamlet.Actions.Result{
      operation_id: ref.id,
      execution_id: handle.id,
      status: :ok,
      source: :execution,
      metadata: []
    }

    send(ref.pid, {:completed, execution.attempt_id, handle, bad})
    assert {:ok, %{result: nil}} = Runtime.status(ref)
    :sys.resume(ExecutorGateway)
    assert_receive {:worker, worker}
    {:ok, %{execution: admitted}} = Runtime.status(ref)

    send(
      ref.pid,
      {:completed, execution.attempt_id, admitted.handle,
       %{bad | source: :coordinator, execution_id: admitted.handle.id, metadata: %{}}}
    )

    assert {:ok, %{result: nil}} = Runtime.status(ref)
    send(worker, :release)
    assert_receive {:beamlet_operation, ^ref, {:result, %{status: :ok, value: "released"}}}
  end

  test "task supervisor capacity failure is a definite rejection without gateway restart" do
    boot()
    gateway = Process.whereis(ExecutorGateway)
    :sys.replace_state(Runtime.Workers, fn state -> %{state | max_children: 0} end)
    {:ok, ref} = Runtime.submit(op())
    assert_receive {:beamlet_operation, ^ref, {:result, %{reason: :capacity}}}
    assert Process.whereis(ExecutorGateway) == gateway
    assert :sys.get_state(gateway).available == %{"cpu" => 1}
  end

  test "membership leave immediately invalidates reports without waiting for refresh" do
    boot(refresh_ms: 10_000)
    endpoint = Process.whereis(Runtime.NodeEndpoint)
    assert Map.has_key?(Directory.snapshots(), endpoint)
    :ok = :pg.leave(Runtime.Groups, :nodes, endpoint)
    assert Directory.snapshots() == %{}
    state = :sys.get_state(Directory)
    refute Map.has_key?(state.reports, endpoint)
    assert Process.alive?(endpoint)
  end

  test "registration rejects unbounded labels, handlers, settings and provider counts" do
    limits = Limits.new([])

    for opts <- [
          [capabilities: List.duplicate("x", 33)],
          [handlers: %{"bad" => {MissingHandler, %{}}}],
          [handlers: %{"echo" => {TestHandler, String.duplicate("x", 65_536)}}],
          [providers: List.duplicate(self(), 33)]
        ] do
      assert_raise ArgumentError, fn -> Report.validate_configuration!(opts, limits) end
    end

    assert_raise ArgumentError, fn ->
      Report.validate_configuration!(
        [capabilities: List.duplicate(String.duplicate("x", 128), 32)],
        Limits.new(limits: [report_bytes: 1024])
      )
    end

    assert_raise ArgumentError, fn -> Limits.new(limits: [result_bytes: 100]) end
    assert_raise ArgumentError, fn -> Limits.new(limits: [progress_bytes: 9000]) end
  end
end
