Code.require_file("apps/beamlet_runtime/test/support/fixture.ex")
if System.get_env("OBS_BASELINE") == "1" do
  for path <- ["apps/beamlet_runtime/lib/beamlet/runtime.ex", "apps/beamlet_runtime/lib/beamlet/runtime/directory.ex"] do
    {source, 0} = System.cmd("git", ["show", "e7f59d1:" <> path])
    Code.compile_string(source, path)
  end
end
alias Beamlet.Runtime
{:ok, sup} = Runtime.SharedSupervisor.start_link(execution: true, handlers: %{"echo" => {Runtime.TestHandler, self()}}, limits: [coordinators: 4, refresh_ms: 1000, expiry_ms: 100, retention_ms: 300, cancel_ms: 20])
Runtime.TestPeer.barrier("echo")
gateway = Process.whereis(Runtime.ExecutorGateway)
endpoint = Process.whereis(Runtime.NodeEndpoint)
# Keep the first report eligible for a controlled 20ms; refresh interval is 1000ms.
Process.sleep(20)
:erlang.trace(gateway, true, [:receive, :send, :monotonic_timestamp])
:erlang.trace(Process.whereis(Runtime.Coordinators), true, [:set_on_spawn, :receive, :send, :monotonic_timestamp])
{:ok, op} = Beamlet.Actions.Operation.new(kind: "echo", payload: %{"mode" => "hold"}, budget_ms: 50)
{:ok, ref} = Runtime.submit(op)
receive do
  {:beamlet_operation, ^ref, {:result, result}} -> IO.inspect(result, label: "RESULT")
after
  1000 -> IO.puts("MISSING RESULT")
end
Process.sleep(70)
collect = fn collect ->
  receive do
    {:trace_ts, pid, kind, msg, ts} ->
      if pid in [gateway, ref.pid], do: IO.inspect({pid, kind, msg, ts}, limit: 30)
      collect.(collect)
    {:trace_ts, pid, kind, msg, to, ts} ->
      if pid in [gateway, ref.pid], do: IO.inspect({pid, kind, msg, to, ts}, limit: 30)
      collect.(collect)
    other -> IO.inspect(other, label: "OTHER"); collect.(collect)
  after
    20 -> :ok
  end
end
collect.(collect)
Supervisor.stop(sup)
