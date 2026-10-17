defmodule Beamlet.Runtime.Directory do
  @moduledoc false
  use GenServer
  alias Beamlet.Runtime.{ExecutorGateway, Groups, Report}
  def start_link(limits), do: GenServer.start_link(__MODULE__, limits, name: __MODULE__)
  def limits, do: GenServer.call(__MODULE__, :limits)
  def select(op), do: GenServer.call(__MODULE__, {:select, op})
  def snapshots, do: GenServer.call(__MODULE__, :snapshots)
  @impl true
  def init(limits) do
    {membership, _members} = :pg.monitor(Groups, :nodes)
    send(self(), :refresh)
    {:ok, %{limits: limits, reports: %{}, pending: %{}, monitors: %{}, membership: membership}}
  end

  @impl true
  def handle_info(:refresh, s) do
    members = :pg.get_members(Groups, :nodes) |> Enum.sort() |> Enum.take(256)

    pending =
      Map.new(members, fn pid ->
        nonce = make_ref()
        send(pid, {:report, self(), nonce})
        {pid, nonce}
      end)

    monitors =
      Enum.reduce(members, s.monitors, fn pid, acc ->
        if Map.has_key?(acc, pid), do: acc, else: Map.put(acc, pid, Process.monitor(pid))
      end)

    monitors =
      Enum.reduce(monitors, %{}, fn {pid, ref}, acc ->
        if pid in members do
          Map.put(acc, pid, ref)
        else
          Process.demonitor(ref, [:flush])
          acc
        end
      end)

    Process.send_after(self(), :refresh, s.limits.refresh_ms)
    {:noreply, %{s | pending: pending, reports: Map.take(s.reports, members), monitors: monitors}}
  end

  def handle_info({:report, pid, nonce, report}, s) do
    if Map.get(s.pending, pid) == nonce and is_reference(nonce) and
         Report.valid?(report, pid, s.limits.report_bytes) do
      {:noreply,
       %{
         s
         | monitors: Map.put_new_lazy(s.monitors, pid, fn -> Process.monitor(pid) end),
           reports: Map.put(s.reports, pid, {now(), report}),
           pending: Map.delete(s.pending, pid)
       }}
    else
      {:noreply, s}
    end
  end

  def handle_info({membership, :leave, :nodes, pids}, %{membership: membership} = s) do
    {:noreply, invalidate(s, pids)}
  end

  def handle_info({membership, :join, :nodes, pids}, %{membership: membership} = s) do
    # Query new members immediately without creating a second periodic timer chain.
    pending =
      Enum.reduce(pids, s.pending, fn pid, acc ->
        known = Map.has_key?(acc, pid) or Map.has_key?(s.reports, pid)
        count = MapSet.size(MapSet.new(Map.keys(acc) ++ Map.keys(s.reports)))

        if known or count < 256 do
          nonce = make_ref()
          send(pid, {:report, self(), nonce})
          Map.put(acc, pid, nonce)
        else
          acc
        end
      end)

    {:noreply, %{s | pending: pending}}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, s) do
    if s.monitors[pid] == ref, do: {:noreply, invalidate(s, [pid])}, else: {:noreply, s}
  end

  def handle_info(_, s), do: {:noreply, s}

  defp invalidate(s, pids) do
    Enum.each(pids, fn pid ->
      if ref = s.monitors[pid], do: Process.demonitor(ref, [:flush])
    end)

    %{
      s
      | reports: Map.drop(s.reports, pids),
        pending: Map.drop(s.pending, pids),
        monitors: Map.drop(s.monitors, pids)
    }
  end

  @impl true
  def handle_call(:limits, _from, s), do: {:reply, s.limits, s}
  def handle_call(:snapshots, _from, s), do: {:reply, fresh(s), s}

  def handle_call(:observation, _from, s) do
    members = :pg.get_members(Groups, :nodes) |> Enum.uniq() |> Enum.sort()
    time = now()

    reports =
      for pid <- Enum.take(members, 256) do
        case s.reports[pid] do
          nil ->
            %{node: node(pid), status: :not_reported, age_ms: :unknown}

          {received, report} ->
            age = max(0, time - received)

            Map.take(report, [
              :node,
              :ready,
              :execution_ready,
              :capabilities,
              :environments,
              :available
            ])
            |> Map.merge(%{
              age_ms: age,
              status: if(age <= s.limits.expiry_ms, do: :fresh, else: :stale)
            })
        end
      end

    result =
      {:ok,
       %{
         version: 1,
         source: node(),
         expiry_ms: s.limits.expiry_ms,
         reports: reports,
         complete: length(members) <= 256
       }}

    reply = if :erlang.external_size(result) <= 1_000_000, do: result, else: {:error, :limit}
    {:reply, reply, s}
  end

  def handle_call({:select, op}, _from, s) do
    target =
      fresh(s)
      |> Enum.filter(fn {_, r} -> ExecutorGateway.eligible?(op, r) end)
      |> Enum.sort_by(fn {pid, r} -> {r.utilization, node(pid), r.incarnation} end)
      |> List.first()

    reply =
      case target do
        nil -> :none
        {pid, r} -> {:ok, pid, r}
      end

    {:reply, reply, s}
  end

  defp fresh(s) do
    members = :pg.get_members(Groups, :nodes)

    for {pid, {time, report}} <- s.reports,
        now() - time <= s.limits.expiry_ms and pid in members,
        into: %{},
        do: {pid, report}
  end

  defp now, do: System.monotonic_time(:millisecond)
end

defmodule Beamlet.Runtime.NodeEndpoint do
  @moduledoc false
  use GenServer
  alias Beamlet.Runtime.{ExecutorGateway, Groups}
  def start_link(limits), do: GenServer.start_link(__MODULE__, limits, name: __MODULE__)
  @impl true
  def init(_limits) do
    gateway = Process.whereis(ExecutorGateway)
    if gateway, do: Process.monitor(gateway)
    :ok = :pg.join(Groups, :nodes, self())
    {:ok, %{gateway: gateway, incarnation: make_ref()}}
  end

  @impl true
  def handle_info({:gateway_ready, gateway}, state) do
    if gateway == Process.whereis(ExecutorGateway) and gateway != state.gateway do
      Process.monitor(gateway)
      {:noreply, %{state | gateway: gateway}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, _, :process, gateway, _}, %{gateway: gateway} = state),
    do: {:stop, :gateway_lost, state}

  def handle_info({:report, directory, nonce}, %{gateway: nil} = state) do
    report = %{
      gateway: nil,
      node: node(),
      incarnation: state.incarnation,
      ready: false,
      execution_ready: false,
      handlers: %{},
      capabilities: [],
      environments: [],
      available: %{},
      utilization: 0.0
    }

    send(directory, {:report, self(), nonce, report})
    {:noreply, state}
  end

  def handle_info({:admit, coordinator, _, attempt, _, _, _, _}, %{gateway: nil} = state) do
    send(coordinator, {:rejected, attempt, :ineligible})
    {:noreply, state}
  end

  def handle_info({:admit, coordinator, _, attempt, _, _, _, _, _}, %{gateway: nil} = state) do
    send(coordinator, {:rejected, attempt, :ineligible})
    {:noreply, state}
  end

  def handle_info(message, %{gateway: gateway} = state) when is_pid(gateway) do
    send(gateway, message)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
