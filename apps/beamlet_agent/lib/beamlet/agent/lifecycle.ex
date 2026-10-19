defmodule Beamlet.Agent.Lifecycle do
  @typep resources :: %{optional(reference()) => pid()}
  @spec run(
          pid(),
          (pid() -> term()),
          pid(),
          :operation | :delegation,
          {binary(), non_neg_integer()} | nil
        ) :: :ok
  @spec start_worker(pid(), (pid() -> term()), pid(), [reference()]) :: :ok
  @spec loop(pid(), pid(), reference(), [reference()], resources(), :ready | [tuple()]) :: :ok
  @spec retire(resources()) :: :ok
  @spec await_down(resources()) :: :ok
  @moduledoc false

  # The controller never calls infrastructure. Every blocking call belongs to its
  # linked worker; killing the controller also kills that worker.
  def run(agent, fun, authority, kind, identity \\ nil) do
    Process.flag(:trap_exit, true)
    Process.put(:authority_resources, authority)
    monitors = [Process.monitor(agent), Process.monitor(authority)]
    ticket = make_ref()
    send(authority, {:register, self(), ticket, agent, kind, identity})

    receive do
      {:registered, ^ticket} -> start_worker(agent, fun, authority, monitors)
      _ -> :ok
    after
      5000 -> :ok
    end
  end

  defp start_worker(agent, fun, authority, monitors) do
    controller = self()

    {worker, wm} =
      :erlang.spawn_opt(
        fn ->
          Process.link(authority)
          fun.(controller)
        end,
        [:link, :monitor]
      )

    send(authority, {:track, self(), worker})
    Process.send_after(self(), :admission_expired, 5000)
    Process.send_after(self(), :lifecycle_expired, 65_000)
    loop(agent, worker, wm, monitors, %{}, [])
  end

  defp loop(agent, worker, wm, monitors, resources, events) do
    receive do
      {:owned, pid} ->
        send(Process.get(:authority_resources), {:track, self(), pid})
        loop(agent, worker, wm, monitors, Map.put(resources, Process.monitor(pid), pid), events)

      {:DOWN, ^wm, _, _, _} ->
        retire(resources)

      {:DOWN, mon, _, _, _} ->
        if mon in monitors,
          do: retire(Map.put(resources, wm, worker)),
          else: loop(agent, worker, wm, monitors, Map.delete(resources, mon), events)

      :admission_expired ->
        if events == :ready,
          do: loop(agent, worker, wm, monitors, resources, events),
          else: retire(Map.put(resources, wm, worker))

      {:EXIT, _, _} ->
        loop(agent, worker, wm, monitors, resources, events)

      signal when signal in [:stop, :finished, :lifecycle_expired] ->
        retire(Map.put(resources, wm, worker))

      {:operation_ready, _, _} = event ->
        send(agent, event)
        Enum.each(Enum.reverse(events), &send(agent, &1))
        loop(agent, worker, wm, monitors, resources, :ready)

      {:operation_failed, _, _} = event ->
        send(agent, event)
        loop(agent, worker, wm, monitors, resources, events)

      {:beamlet_operation, _, _} = event ->
        if events == :ready do
          send(agent, event)
          loop(agent, worker, wm, monitors, resources, events)
        else
          loop(agent, worker, wm, monitors, resources, [event | events])
        end

      {:child_startup, _, group, ticket} ->
        send(agent, {:child_startup, self(), group, ticket})
        loop(agent, worker, wm, monitors, resources, :ready)

      message ->
        send(worker, message)
        loop(agent, worker, wm, monitors, resources, events)
    end
  end

  defp retire(resources) do
    Enum.each(resources, fn {_, pid} -> Process.exit(pid, :kill) end)
    await_down(resources)
  end

  defp await_down(resources) when map_size(resources) == 0, do: :ok

  defp await_down(resources) do
    receive do
      {:owned, pid} ->
        Process.exit(pid, :kill)
        await_down(Map.put(resources, Process.monitor(pid), pid))

      {:DOWN, mon, _, _, _} ->
        await_down(Map.delete(resources, mon))

      _ ->
        await_down(resources)
    end
  end
end
