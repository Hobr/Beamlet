defmodule Beamlet.Runtime.DeadlineHandler do
  @behaviour Beamlet.Actions.Handler
  def run(payload, context) do
    if payload["trap"], do: Process.flag(:trap_exit, true)
    send(context.settings, {:started, self(), context.remaining_ms})

    receive do
      :release -> {:ok, "done"}
      :crash -> exit(:unrelated_crash)
    end
  end
end

defmodule Beamlet.Runtime.DeadlineClassificationTest do
  use ExUnit.Case
  alias Beamlet.Actions.Operation
  alias Beamlet.Runtime
  alias Beamlet.Runtime.ExecutorGateway, as: Gateway

  setup do
    start_supervised!(
      {Runtime.SharedSupervisor,
       execution: true,
       handlers: %{"deadline" => {Runtime.DeadlineHandler, self()}},
       pools: %{"cpu" => 1},
       limits: [refresh_ms: 10_000, expiry_ms: 3000, retention_ms: 3000, cancel_ms: 100]}
    )

    Runtime.TestPeer.barrier("deadline")
    :ok
  end

  defp submit(payload \\ %{}, budget \\ 5000) do
    {:ok, op} =
      Operation.new(kind: "deadline", payload: payload, budget_ms: budget, claims: %{"cpu" => 1})

    {:ok, ref} = Runtime.submit(op)
    assert_receive {:started, worker, remaining}, 2000
    {:ok, %{execution: execution}} = Runtime.status(ref)
    {ref, worker, remaining, execution, op}
  end

  test "valid aged report expires actual worker before coordinator deadline" do
    {:ok, op} = Operation.new(kind: "deadline")
    {:ok, _, report} = Runtime.Directory.select(op)
    # Age a genuine report, without blocking endpoint admission or altering its lease.
    wait_until(report.lease + 700)
    {ref, worker, remaining, execution, op} = submit(%{}, 1400)
    assert remaining > 0 and remaining < 800
    mon = Process.monitor(worker)
    assert_receive {:DOWN, ^mon, :process, ^worker, :shutdown}, 2000
    assert_receive {:beamlet_operation, ^ref, {:result, result}}, 2000
    assert result.status == :deadline
    assert result.reason == :worker_stopped
    assert result.source == :execution
    assert {:ok, %{result: ^result}} = Runtime.status(ref)
    assert_once(ref, worker, execution, op, result)
  end

  for first <- [:deadline, :cancelled], outcome <- [:kill, :crash, :success] do
    @first first
    @outcome outcome
    test "first #{@first} trigger followed by #{@outcome} keeps causal classification" do
      {ref, worker, _, execution, op} = submit(%{"trap" => true})
      key = {ref.pid, execution.attempt_id}
      mon = Process.monitor(worker)
      gateway = Process.whereis(Gateway)
      :sys.suspend(gateway)

      try do
        if @first == :deadline, do: send(gateway, {:execution_deadline, key, worker})
        assert :ok = Runtime.cancel(ref)
        # Fence NodeEndpoint's forwarded cancellation before the later deadline.
        :sys.get_state(execution.endpoint)
        if @first == :cancelled, do: send(gateway, {:execution_deadline, key, worker})
      after
        :sys.resume(gateway)
      end

      assert :sys.get_state(gateway).attempts[key].stop_source == @first

      case @outcome do
        :kill -> :ok
        :crash -> send(worker, :crash)
        :success -> send(worker, :release)
      end

      expected_down = %{kill: :killed, crash: :unrelated_crash, success: :normal}[@outcome]
      assert_receive {:DOWN, ^mon, :process, ^worker, ^expected_down}, 2000
      assert_receive {:beamlet_operation, ^ref, {:result, result}}, 2000
      expected_status = %{kill: @first, crash: :error, success: :ok}[@outcome]
      expected_reason = %{kill: :worker_stopped, crash: :worker_lost, success: nil}[@outcome]
      assert result.status == expected_status
      assert result.reason == expected_reason
      assert_once(ref, worker, execution, op, result)
    end
  end

  for trigger <- [:deadline, :cancel_timeout] do
    @trigger trigger
    test "#{@trigger} without observed termination stays unconfirmed" do
      {ref, worker, _, execution, op} = submit()
      gateway = Process.whereis(Gateway)
      mon = Process.monitor(worker)
      :sys.suspend(gateway)

      result =
        try do
          assert :ok = Runtime.cancel(ref)
          send(ref.pid, @trigger)
          assert_receive {:beamlet_operation, ^ref, {:result, result}}, 1000
          assert Process.alive?(worker)
          expected = if @trigger == :deadline, do: :deadline, else: :uncertain

          reason =
            if @trigger == :deadline, do: :termination_unconfirmed, else: :cancel_unconfirmed

          assert result.status == expected
          assert result.reason == reason
          result
        after
          :sys.resume(gateway)
        end

      assert_receive {:DOWN, ^mon, :process, ^worker, :shutdown}, 2000
      # DOWN delivery to this test and to Gateway is independent; fence completion.
      assert_receive_terminal_gateway({ref.pid, execution.attempt_id})
      assert_once(ref, worker, execution, op, result)
    end
  end

  defp assert_receive_terminal_gateway(key, attempts \\ 200)
  defp assert_receive_terminal_gateway(_, 0), do: flunk("gateway did not retire worker")

  defp assert_receive_terminal_gateway(key, attempts) do
    case :sys.get_state(Gateway).attempts[key] do
      :terminal ->
        :ok

      _ ->
        Process.sleep(5)
        assert_receive_terminal_gateway(key, attempts - 1)
    end
  end

  defp wait_until(time) do
    remaining = time - System.monotonic_time(:millisecond)
    if remaining > 0, do: Process.sleep(remaining)
  end

  defp assert_once(ref, worker, execution, op, result) do
    key = {ref.pid, execution.attempt_id}
    send(Gateway, {:execution_deadline, key, worker})
    send(Gateway, {:kill, key, worker})
    send(Gateway, {:cancel, ref.pid, execution.attempt_id})

    send(
      execution.endpoint,
      {:admit, ref.pid, ref.id, execution.attempt_id, execution.incarnation,
       System.monotonic_time(:millisecond), op, 1000}
    )

    send(ref.pid, {:completed, execution.attempt_id, execution.handle, result})
    send(ref.pid, :deadline)
    send(ref.pid, :cancel_timeout)
    assert :sys.get_state(Gateway).available == %{"cpu" => 1}
    assert map_size(:sys.get_state(Gateway).tasks) == 0
    assert {:ok, %{result: ^result}} = Runtime.status(ref)
    refute_receive {:started, _, _}, 120
    refute_receive {:beamlet_operation, ^ref, {:result, _}}, 120
  end
end
