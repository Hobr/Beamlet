defmodule Beamlet.Agent.Discovery do
  @moduledoc false
  alias Beamlet.Agent.Ref
  @budget 5000
  @bytes 1_048_576

  def budget, do: @budget
  def bytes, do: @bytes
  def now, do: System.monotonic_time(:millisecond)
  def remaining(deadline), do: max(0, deadline - now())
  def valid_id?(id), do: is_binary(id) and byte_size(id) in 1..128 and String.valid?(id)

  def list(authority), do: query(authority, :list)

  def lookup(authority, id, expected \\ nil) do
    if valid_id?(id) and (is_nil(expected) or (is_pid(expected) and node(expected) == authority)),
      do: query(authority, {:lookup, id, expected}),
      else: {:error, :invalid_query}
  end

  def lookup(%{authority: authority, id: id, pid: pid} = descriptor)
      when map_size(descriptor) == 3 and is_pid(pid),
      do: lookup(authority, id, pid)

  def lookup(_), do: {:error, :invalid_query}

  def query(authority, query) when is_atom(authority) and authority not in [nil, true, false] do
    if authority != node() and authority not in Node.list(:connected),
      do: {:error, :unavailable},
      else: bounded_request(authority, query)
  end

  def query(_, _), do: {:error, :invalid_query}

  defp bounded_request(authority, query) do
    deadline = now() + @budget
    task = fn q -> request(authority, q, deadline) end

    case Enum.to_list(Task.async_stream([query], task, timeout: @budget, on_timeout: :kill_task)) do
      [{:ok, result}] -> result
      _ -> {:error, :timeout}
    end
  end

  defp request(authority, query, deadline) do
    budget = remaining(deadline)

    if budget == 0 do
      {:error, :timeout}
    else
      if authority == node(),
        do: query_local(query, budget),
        else: :erpc.call(authority, __MODULE__, :query_local, [query, budget], budget)
    end
  catch
    :error, {:erpc, :timeout} -> {:error, :timeout}
    _, _ -> {:error, :unavailable}
  end

  # Relative budgets are interpreted on the executing VM. OTP may complete this
  # finite read after its caller has abandoned the response; it is not cancelled.
  def query_local(query, budget) when is_integer(budget) and budget in 1..@budget do
    deadline = now() + budget

    if valid_query?(query) do
      registry = Process.whereis(Beamlet.Agent.Registry)

      cond do
        is_nil(Process.whereis(Beamlet.Agent.AuthoritySupervisor)) ->
          {:error, :not_authority}

        is_nil(registry) ->
          {:error, :unavailable}

        true ->
          validate_result(local(query, deadline), registry, deadline)
      end
    else
      {:error, :invalid_query}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def query_local(_, _), do: {:error, :invalid_query}

  defp validate_result(result, registry, deadline) do
    cond do
      Process.whereis(Beamlet.Agent.Registry) != registry -> {:error, :unavailable}
      remaining(deadline) == 0 -> {:error, :timeout}
      :erlang.external_size(result) > @bytes -> {:error, :limit}
      true -> result
    end
  end

  defp valid_query?(:list), do: true

  defp valid_query?({:lookup, id, expected}),
    do: valid_id?(id) and (is_nil(expected) or (is_pid(expected) and node(expected) == node()))

  defp valid_query?(_), do: false

  defp local(:list, _deadline) do
    entries =
      Registry.select(Beamlet.Agent.Registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])

    if length(entries) <= 128 do
      {:ok,
       for(
         {id, pid} <- entries,
         valid_id?(id),
         Process.alive?(pid),
         do: %{authority: node(), id: id, pid: pid}
       )}
    else
      {:error, :limit}
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  defp local({:lookup, id, expected}, deadline) do
    case Registry.lookup(Beamlet.Agent.Registry, id) do
      [{pid, _}] when not is_nil(expected) and pid != expected -> {:error, :stale_agent}
      [{pid, _}] -> fetch_ref(pid, id, deadline)
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  defp fetch_ref(pid, id, deadline) do
    if remaining(deadline) > 0,
      do: call_ref(pid, id, deadline),
      else: {:error, :timeout}
  end

  defp call_ref(pid, id, deadline) do
    case GenServer.call(pid, :ref, remaining(deadline)) do
      {:ok, %Ref{authority: authority, id: ^id, pid: ^pid, incarnation: inc} = ref}
      when authority == node() and is_reference(inc) ->
        {:ok, ref}

      _ ->
        {:error, :stale_agent}
    end
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _ -> {:error, :unavailable}
  end
end
