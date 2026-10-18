defmodule Beamlet.Web.OwnedCall do
  @moduledoc "Finite disposable callers. Killing a caller never implies business cancellation."

  def start(owner, tag, fun, timeout \\ 8_000) do
    spawn(fn ->
      Process.flag(:trap_exit, true)
      monitor = Process.monitor(owner)
      guardian = self()

      worker =
        spawn_link(fn ->
          Process.put(__MODULE__, guardian)
          send(guardian, {:result, safe(fun)})
        end)

      command(owner, tag, worker, monitor, System.monotonic_time(:millisecond) + timeout)
    end)
  end

  # Relay milestones and completion from the same process. Signals from the
  # worker precede its EXIT, including when a deadline interrupts the call.
  def deliver(owner, message) do
    case Process.get(__MODULE__) do
      nil -> send(owner, message)
      guardian -> send(guardian, {:milestone, message})
    end
  end

  defp command(owner, tag, worker, monitor, deadline) do
    receive do
      {:milestone, message} ->
        send(owner, message)
        command(owner, tag, worker, monitor, deadline)

      {:result, result} ->
        finish_worker(owner, worker)
        send(owner, {:owned, tag, result})

      :cancel ->
        Process.exit(worker, :kill)
        finish_worker(owner, worker)

      {:DOWN, ^monitor, :process, ^owner, _} ->
        Process.exit(worker, :kill)
        finish_worker(owner, worker)

      {:EXIT, ^worker, _} ->
        send(owner, {:owned, tag, :unavailable})
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        Process.exit(worker, :kill)
        finish_worker(owner, worker)
        send(owner, {:owned, tag, :deadline})
    end
  end

  defp finish_worker(owner, worker) do
    receive do
      {:milestone, message} ->
        send(owner, message)
        finish_worker(owner, worker)

      {:EXIT, ^worker, _} ->
        :ok
    end
  end

  defp safe(fun) do
    fun.()
  catch
    _, _ -> :unavailable
  end

  def observe(owner, tag, ref, previous \\ nil) do
    spawn(fn ->
      Process.flag(:trap_exit, true)
      monitor = Process.monitor(owner)

      sink =
        spawn_link(fn ->
          wait_previous(previous)
          subscribe(owner, tag, ref)
        end)

      receive do
        {:DOWN, ^monitor, :process, ^owner, _} -> kill_sink(sink)
        :leave -> retire(sink)
        {:EXIT, ^sink, _} -> send(owner, {:observation, tag, :unavailable})
      end
    end)
  end

  defp wait_previous(nil), do: :ok

  defp wait_previous(previous) do
    monitor = Process.monitor(previous)
    send(previous, :leave)

    receive do
      {:DOWN, ^monitor, _, _, _} -> :ok
    end
  end

  defp retire(sink) do
    send(sink, :leave)

    receive do
      {:EXIT, ^sink, _} -> :ok
    after
      6_000 -> kill_sink(sink)
    end
  end

  defp kill_sink(sink) do
    Process.exit(sink, :kill)

    receive do
      {:EXIT, ^sink, _} -> :ok
    end
  end

  defp subscribe(owner, tag, ref) do
    Process.monitor(ref.pid)

    case Beamlet.Agent.subscribe(ref, self(), view: :display) do
      :ok -> snapshots(owner, tag, ref)
      _ -> send(owner, {:observation, tag, :unavailable})
    end
  end

  defp await_display(owner, tag, ref, sequence) do
    receive do
      {:displayed, ^sequence} ->
        Beamlet.Agent.ack(ref, sequence)
        snapshots(owner, tag, ref)

      :leave ->
        Beamlet.Agent.unsubscribe(ref, self())

      {:DOWN, _, :process, _, _} ->
        send(owner, {:observation, tag, :unavailable})
    end
  end

  defp snapshots(owner, tag, ref) do
    receive do
      :leave ->
        Beamlet.Agent.unsubscribe(ref, self())

      {:DOWN, _, :process, _, _} ->
        send(owner, {:observation, tag, :unavailable})

      {:beamlet_agent, ^ref, sequence, {:snapshot, snapshot}} ->
        send(owner, {:observation, tag, {:snapshot, snapshot, self(), sequence}})
        await_display(owner, tag, ref, sequence)
    end
  end
end
