defmodule Beamlet.RuntimeCompositionTest do
  use ExUnit.Case
  alias Beamlet.Actions.Operation
  alias Beamlet.Runtime

  test "shared-only starts no execution services and remains discoverable" do
    start_supervised!({Runtime.SharedSupervisor, []})
    refute Process.whereis(Runtime.ExecutorGateway)
    refute Process.whereis(Runtime.Workers)
    endpoint = Process.whereis(Runtime.NodeEndpoint)
    assert endpoint in :pg.get_members(Runtime.Groups, :nodes)
    nonce = make_ref()
    send(endpoint, {:report, self(), nonce})

    assert_receive {:report, ^endpoint, ^nonce,
                    %{execution_ready: false, ready: false, capabilities: []}}

    {:ok, op} = Operation.new(kind: "echo")
    {:ok, operation} = Runtime.submit(op)
    assert_receive {:beamlet_operation, ^operation, {:result, %{reason: :no_target}}}
  end

  test "explicit standalone execution subtree attaches to shared discovery" do
    opts = [handlers: %{"echo" => {Runtime.TestHandler, self()}}]
    start_supervised!({Runtime.SharedSupervisor, limits: [refresh_ms: 10]})
    start_supervised!({Runtime.ExecutionSupervisor, {opts, Runtime.Limits.new([])}})
    Runtime.TestPeer.barrier("echo")
    assert Process.whereis(Runtime.Workers)
    {:ok, op} = Operation.new(kind: "echo")
    {:ok, operation} = Runtime.submit(op)
    assert_receive {:beamlet_operation, ^operation, {:result, %{status: :ok}}}
    snapshots = Runtime.Directory.snapshots()
    assert Enum.any?(snapshots, fn {_, report} -> report.execution_ready end)
  end
end
