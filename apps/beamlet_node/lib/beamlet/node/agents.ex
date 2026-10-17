defmodule Beamlet.Node.Agents do
  @moduledoc """
  Eventual observed identities from an explicit set of trusted node atoms.

  Targets are already-resolved trusted nodes (use Cluster.authority/2); no string
  is atomized. Initially disconnected targets are rejected; OTP may reconnect
  after the connection precheck. An alive local VM is eligible as in
  Cluster.connected/1. At most32 unique targets,8 concurrent requests, one total
  five-second receive deadline and a complete serialized envelope of at most1MiB.
  `complete` covers only the requested set; every failed/limited node is explicit.
  """
  alias Beamlet.Agent.Discovery, as: D
  alias Beamlet.Node.Cluster

  def discover(nodes) do
    with true <- valid_nodes?(nodes),
         {:ok, connected} <- Cluster.connected(Enum.map(nodes, &Atom.to_string/1)) do
      discover_connected(nodes, connected)
    else
      _ -> {:error, :invalid_query}
    end
  end

  defp discover_connected(nodes, connected) do
    deadline = D.now() + D.budget()
    # One stream item provides a single outer deadline and caller ownership;
    # linked per-node workers cannot survive this scheduler's termination.
    case Enum.to_list(
           Task.async_stream(
             [nodes],
             fn targets ->
               collect(targets, connected, deadline)
             end,
             timeout: D.budget() + 100,
             on_timeout: :kill_task
           )
         ) do
      [{:ok, result}] -> {:ok, result}
      _ -> {:ok, %{agents: [], failures: Map.new(nodes, &{&1, :timeout}), complete: false}}
    end
  end

  defp valid_nodes?(nodes), do: valid_nodes?(nodes, 32, [])
  defp valid_nodes?([], _, _), do: true

  defp valid_nodes?([n | rest], left, seen) when is_atom(n) and left > 0 do
    n not in [nil, true, false] and n not in seen and
      valid_nodes?(rest, left - 1, [n | seen])
  end

  defp valid_nodes?(_, _, _), do: false

  defp collect(nodes, connected, deadline) do
    {eligible, missing} = Enum.split_with(nodes, &(&1 in connected))

    result = %{
      agents: [],
      failures: Map.new(missing, &{&1, :unavailable}),
      complete: missing == []
    }

    schedule(eligible, %{}, result, deadline)
  end

  defp schedule(queued, active, result, deadline) when map_size(active) < 8 and queued != [] do
    if D.remaining(deadline) == 0 do
      expire(queued, active, result)
    else
      [target | rest] = queued
      owner = self()

      pid =
        spawn_link(fn -> send(owner, {:listed, self(), target, Beamlet.Agent.list(target)}) end)

      schedule(rest, Map.put(active, pid, target), result, deadline)
    end
  end

  defp schedule([], active, result, _) when map_size(active) == 0, do: result

  defp schedule(queued, active, result, deadline) do
    receive do
      {:listed, pid, target, response} when is_map_key(active, pid) ->
        schedule(queued, Map.delete(active, pid), retain(result, target, response), deadline)
    after
      D.remaining(deadline) -> expire(queued, active, result)
    end
  end

  @doc false
  def retain(result, target, {:ok, agents}) do
    candidate = %{result | agents: result.agents ++ agents}
    # Reserve16KiB for ALL32 possible255-byte node names and static failures,
    # including nodes which have not replied yet. Count the complete tuple.
    if :erlang.external_size({:ok, candidate}) + 16_384 <= D.bytes(),
      do: candidate,
      else: retain(result, target, {:error, :limit})
  end

  def retain(result, target, {:error, reason})
      when reason in [
             :not_authority,
             :not_found,
             :unavailable,
             :timeout,
             :limit,
             :stale_agent,
             :invalid_query
           ],
      do: %{result | failures: Map.put(result.failures, target, reason), complete: false}

  def retain(result, target, _), do: retain(result, target, {:error, :unavailable})

  defp expire(queued, active, result) do
    Enum.each(active, fn {pid, _} ->
      monitor = Process.monitor(pid)
      Process.unlink(pid)
      Process.exit(pid, :kill)

      receive do
        {:DOWN, ^monitor, _, _, _} -> :ok
      end
    end)

    Enum.reduce(queued ++ Map.values(active), result, &retain(&2, &1, {:error, :timeout}))
  end
end
