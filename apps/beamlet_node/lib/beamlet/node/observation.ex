defmodule Beamlet.Node.Observation do
  @moduledoc false
  alias Beamlet.Runtime.Directory
  alias Beamlet.Runtime.Observation, as: Read

  @typedoc "Advisory source-local facts; readiness means registration only."
  @type local_observation :: %{
          version: 1,
          node: node(),
          configured: boolean(),
          roles: [Beamlet.Node.role()] | :unknown,
          services: services() | :not_configured,
          runtime: {:ok, Beamlet.Runtime.observation()} | {:error, atom()}
        }
  @type services :: %{
          routes: readiness(),
          runtime: readiness(),
          authority: readiness(),
          executor: readiness()
        }
  @type readiness :: :ready | :unavailable | :not_configured
  @type aggregate :: %{
          nodes: %{optional(node()) => local_observation()},
          failures: %{optional(node()) => atom()},
          complete: boolean()
        }
  @typep active :: %{optional(pid()) => node()}
  @typep response :: {:ok, local_observation()} | {:error, atom()}
  @spec local() :: response()
  def local, do: Read.isolate(fn -> local_read(5000) end, 5000)

  # Fixed erpc entry: every delayed execution starts a finite source-local budget.
  @spec local_read(term()) :: response()
  def local_read(budget) when is_integer(budget) and budget in 1..5000 do
    deadline = Read.now() + budget
    owner = Process.whereis(Beamlet.Node)

    source_read(owner, deadline)
  end

  def local_read(_), do: {:error, :invalid_query}

  @spec source_read(pid() | nil, integer()) :: response()
  defp source_read(nil, _) do
    {:ok,
     %{
       version: 1,
       node: node(),
       configured: false,
       roles: :unknown,
       services: :not_configured,
       runtime: {:error, :not_configured}
     }}
  end

  defp source_read(owner, deadline) do
    with {:ok, roles} <- Read.read(Beamlet.Node.Routes, :roles, Read.remaining(deadline)) do
      runtime = Read.read(Directory, :observation, Read.remaining(deadline))
      source_result(owner, roles, runtime)
    end
  end

  @spec source_result(
          pid(),
          [Beamlet.Node.role()],
          {:ok, Beamlet.Runtime.observation()} | {:error, atom()}
        ) :: response()
  defp source_result(owner, roles, runtime) do
    if owner == Process.whereis(Beamlet.Node) do
      {:ok,
       %{
         version: 1,
         node: node(),
         configured: true,
         roles: roles,
         services: services(roles),
         runtime: runtime
       }}
    else
      {:error, :unavailable}
    end
  end

  @spec services([Beamlet.Node.role()]) :: services()
  defp services(roles) do
    %{
      routes: ready([Beamlet.Node.Routes]),
      runtime: ready([Beamlet.Runtime.SharedSupervisor, Directory, Beamlet.Runtime.NodeEndpoint]),
      authority:
        role_ready(roles, :authority, [
          Beamlet.Agent.AuthoritySupervisor,
          Beamlet.Agent.Registry,
          Beamlet.Agent.Resources,
          Beamlet.Agent.Agents,
          Beamlet.Agent.Delegations
        ]),
      executor:
        role_ready(roles, :executor, [
          Beamlet.Node.Provider,
          Beamlet.Runtime.ExecutionSupervisor,
          Beamlet.Runtime.ExecutorGateway,
          Beamlet.Runtime.Workers
        ])
    }
  end

  @spec role_ready([Beamlet.Node.role()], Beamlet.Node.role(), [atom()]) :: readiness()
  defp role_ready(roles, role, names) do
    if role in roles, do: ready(names), else: :not_configured
  end

  @spec ready([atom()]) :: :ready | :unavailable
  defp ready(names) do
    if Enum.all?(names, &is_pid(Process.whereis(&1))), do: :ready, else: :unavailable
  end

  @spec observe(term()) :: {:ok, aggregate()} | {:error, :invalid_query}
  def observe(nodes) do
    if valid?(nodes, 32, []) do
      deadline = Read.now() + 5000
      connected = [node() | Node.list(:connected)]

      aggregate_result(Read.isolate(fn -> collect(nodes, connected, deadline) end, 5000), nodes)
    else
      {:error, :invalid_query}
    end
  end

  @spec aggregate_result(aggregate() | {:error, term()}, [node()]) :: {:ok, aggregate()}
  defp aggregate_result({:error, _}, nodes),
    do: {:ok, %{nodes: %{}, failures: Map.new(nodes, &{&1, :timeout}), complete: false}}

  defp aggregate_result(result, _), do: {:ok, result}

  @spec valid?(term(), integer(), [node()]) :: boolean()
  defp valid?([], _, _), do: true

  defp valid?([n | rest], left, seen) when is_atom(n) and left > 0 do
    n not in [nil, true, false] and n not in seen and valid?(rest, left - 1, [n | seen])
  end

  defp valid?(_, _, _), do: false

  @spec collect([node()], [node()], integer()) :: aggregate()
  defp collect(nodes, connected, deadline) do
    {eligible, missing} = Enum.split_with(nodes, &(&1 in connected))

    result = %{
      nodes: %{},
      failures: Map.new(missing, &{&1, :unavailable}),
      complete: missing == []
    }

    schedule(eligible, %{}, result, deadline)
  end

  @spec schedule([node()], active(), aggregate(), integer()) :: aggregate()
  defp schedule([target | rest] = queued, active, result, deadline) when map_size(active) < 8 do
    if Read.remaining(deadline) == 0 do
      expire(queued, active, result)
    else
      owner = self()
      pid = spawn_link(fn -> send(owner, {:observed, self(), request(target, deadline)}) end)
      schedule(rest, Map.put(active, pid, target), result, deadline)
    end
  end

  defp schedule([], active, result, _) when map_size(active) == 0, do: result

  defp schedule(queued, active, result, deadline) do
    receive do
      {:observed, pid, response} when is_map_key(active, pid) ->
        schedule(queued, Map.delete(active, pid), retain(result, active[pid], response), deadline)
    after
      Read.remaining(deadline) -> expire(queued, active, result)
    end
  end

  @spec request(node(), integer()) :: response()
  defp request(target, deadline) do
    budget = Read.remaining(deadline)

    cond do
      budget == 0 -> {:error, :timeout}
      target == node() -> local_read(budget)
      true -> :erpc.call(target, __MODULE__, :local_read, [budget], budget)
    end
  catch
    :error, {:erpc, :timeout} -> {:error, :timeout}
    _, _ -> {:error, :unavailable}
  end

  @doc false
  @spec retain(aggregate(), node(), term()) :: aggregate()
  def retain(result, target, {:ok, observation}) do
    candidate = %{result | nodes: Map.put(result.nodes, target, observation)}

    if :erlang.external_size({:ok, candidate}) + 16_384 <= 1_048_576 do
      retain_completeness(candidate, target, observation)
    else
      retain(result, target, {:error, :limit})
    end
  end

  def retain(result, target, {:error, reason}) when reason in [:timeout, :unavailable, :limit] do
    %{result | failures: Map.put(result.failures, target, reason), complete: false}
  end

  def retain(result, target, _), do: retain(result, target, {:error, :unavailable})

  @spec retain_completeness(aggregate(), node(), local_observation()) :: aggregate()
  defp retain_completeness(result, _, %{configured: false}), do: result
  defp retain_completeness(result, _, %{runtime: {:ok, %{complete: true}}}), do: result

  defp retain_completeness(result, target, %{runtime: {:error, reason}}),
    do: retain(result, target, {:error, reason})

  defp retain_completeness(result, target, _), do: retain(result, target, {:error, :limit})

  @spec expire([node()], active(), aggregate()) :: aggregate()
  defp expire(queued, active, result) do
    Enum.each(active, fn {pid, _} ->
      ref = Process.monitor(pid)
      Process.unlink(pid)
      Process.exit(pid, :kill)
      receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
    end)

    Enum.reduce(queued ++ Map.values(active), result, &retain(&2, &1, {:error, :timeout}))
  end
end
