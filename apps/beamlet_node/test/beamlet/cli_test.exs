defmodule Beamlet.Node.CLITest do
  use ExUnit.Case
  alias Beamlet.Node.CLI

  test "authority is explicit and restricted to trusted deployment names" do
    assert {:ok, :authority@localhost} =
             CLI.authority("authority@localhost", ["authority@localhost"])

    assert {:error, :invalid_authority} = CLI.authority("other@localhost", [])
    assert {:error, :invalid_authority} = CLI.authority("invalid", ["invalid"])
  end

  test "malformed watch options reject before subscription" do
    for opts <- [nil, %{}, [:timeout], [{"timeout", 1}], [unknown: 1], [timeout: 0], [events: 0]] do
      assert {:error, :invalid_watch_options} = CLI.watch(nil, opts)
    end
  end

  test "event limits and dead refs clean up the subscriber" do
    start_supervised!({Beamlet.Node, roles: [:authority]})

    {:ok, ref} =
      CLI.create(node(),
        id: "cleanup",
        model: %{
          provider: "deterministic",
          config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
        }
      )

    assert {:error, :event_limit} = CLI.watch(ref, events: 1)
    assert :sys.get_state(ref.pid).subscribers == %{}
    assert {:error, :timeout_or_loss} = CLI.watch(ref, timeout: 1)
    assert :sys.get_state(ref.pid).subscribers == %{}
    assert :ok = CLI.close(ref)
    assert {:error, :unavailable} = CLI.watch(ref)
  end

  test "authority loss while watching is explicit" do
    start_supervised!({Beamlet.Node, roles: [:authority]})

    {:ok, ref} =
      CLI.create(node(),
        id: "loss",
        model: %{
          provider: "deterministic",
          config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
        }
      )

    watcher = Task.async(fn -> CLI.watch(ref, timeout: 100) end)
    await_subscriber(ref.pid, watcher.pid, System.monotonic_time(:millisecond) + 1000)
    stop_supervised(Beamlet.Node)
    assert {:error, reason} = Task.await(watcher, 2000)
    assert reason in [:timeout_or_loss, :unavailable]
  end

  defp await_subscriber(agent, sink, deadline) do
    unless Map.has_key?(:sys.get_state(agent).subscribers, sink) do
      assert System.monotonic_time(:millisecond) < deadline
      await_subscriber(agent, sink, deadline)
    end
  end

  test "watch credits, terminal output, timeout and input controls use live refs" do
    start_supervised!({Beamlet.Node, roles: [:authority]})

    assert {:ok, ref} =
             CLI.create(node(),
               id: "cli",
               model: %{
                 provider: "deterministic",
                 config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
               }
             )

    assert {:ok, %{status: :idle}} = CLI.status(ref)
    assert {:error, :invalid_watch_options} = CLI.watch(ref, events: 257)
    assert {:error, :timeout_or_loss} = CLI.watch(ref, timeout: 1)
    assert {:error, :invalid_or_oversize_input} = CLI.input(ref, String.duplicate("x", 65_537))
    assert :ok = CLI.stop(ref)
    assert {:ok, %{status: :stopped}} = CLI.watch(ref)
    assert :ok = CLI.close(ref)
    assert {:error, :unavailable} = CLI.snapshot(ref)
  end
end
