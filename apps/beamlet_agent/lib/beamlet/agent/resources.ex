defmodule Beamlet.Agent.Resources do
  @moduledoc false
  use GenServer
  @generation {__MODULE__, :generation}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)
    # This VM-local fence survives authority replacement, never a VM restart.
    # New admission waits for observed exit of every recorded old resource.
    previous = :persistent_term.get(@generation, [])
    monitors = Map.new(previous, fn pid -> {Process.monitor(pid), pid} end)
    Enum.each(previous, &Process.exit(&1, :kill))
    drain(monitors)
    :persistent_term.put(@generation, [])
    {:ok, %{slots: %{}, processes: %{}, groups: %{}, agents: %{}, rejected: %{}, kinds: %{}}}
  end

  @impl true
  def handle_info({:register, pid, ticket, agent, kind}, s) do
    cond do
      pid in Map.values(s.processes) ->
        {:noreply, s}

      Process.alive?(pid) ->
        register(pid, ticket, agent, kind, s)

      true ->
        send(agent, {:resource_retired, pid})
        {:noreply, s}
    end
  end

  def handle_info({:track, controller, pid}, s) do
    if pid in Map.values(s.processes), do: {:noreply, s}, else: track(controller, pid, s)
  end

  def handle_info({:DOWN, mon, _, _, _}, s) do
    if rejected = s.rejected[mon] do
      {pid, agent} = rejected
      send(agent, {:resource_retired, pid})
    end

    groups = Map.delete(s.groups, mon)
    {retired, live} = Enum.split_with(s.slots, fn {slot, _} -> slot not in Map.values(groups) end)
    Enum.each(retired, fn {slot, pid} -> send(s.agents[slot], {:resource_retired, pid}) end)
    agents = Map.drop(s.agents, Enum.map(retired, &elem(&1, 0)))

    next = %{
      s
      | slots: Map.new(live),
        processes: Map.delete(s.processes, mon),
        groups: groups,
        agents: agents,
        rejected: Map.delete(s.rejected, mon),
        kinds: Map.drop(s.kinds, Enum.map(retired, &elem(&1, 0)))
    }

    remember(next)
    {:noreply, next}
  end

  def handle_info(_, s), do: {:noreply, s}

  defp track(controller, pid, s) do
    case Enum.find(s.slots, fn {_, owner} -> owner == controller end) do
      {slot, _} ->
        Process.link(pid)
        mon = Process.monitor(pid)

        next = %{
          s
          | processes: Map.put(s.processes, mon, pid),
            groups: Map.put(s.groups, mon, slot)
        }

        remember(next)
        {:noreply, next}

      nil ->
        Process.exit(pid, :kill)
        {:noreply, s}
    end
  end

  defp register(pid, ticket, agent, kind, s) do
    Process.link(pid)
    mon = Process.monitor(pid)

    if Enum.count(s.kinds, fn {_, value} -> value == kind end) < 1024 do
      next = %{
        s
        | slots: Map.put(s.slots, mon, pid),
          processes: Map.put(s.processes, mon, pid),
          groups: Map.put(s.groups, mon, mon),
          agents: Map.put(s.agents, mon, agent),
          kinds: Map.put(s.kinds, mon, kind)
      }

      remember(next)
      send(pid, {:registered, ticket})
      {:noreply, next}
    else
      next = %{
        s
        | rejected: Map.put(s.rejected, mon, {pid, agent}),
          processes: Map.put(s.processes, mon, pid)
      }

      remember(next)
      Process.exit(pid, :kill)
      {:noreply, next}
    end
  end

  @impl true
  def terminate(_, s) do
    Enum.each(s.processes, fn {_, pid} -> Process.exit(pid, :kill) end)
    drain(s.processes)
  end

  defp remember(s), do: :persistent_term.put(@generation, Map.values(s.processes))

  defp drain(processes) when map_size(processes) == 0, do: :ok

  defp drain(processes) do
    receive do
      {:DOWN, mon, _, _, _} ->
        drain(Map.delete(processes, mon))

      {:track, _, pid} ->
        Process.exit(pid, :kill)
        drain(Map.put(processes, Process.monitor(pid), pid))

      _ ->
        drain(processes)
    end
  end
end
