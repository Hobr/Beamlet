defmodule Beamlet.Agent.Discovery do
  @moduledoc false
  alias Beamlet.Agent.Discovery.Endpoint
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
    cond do
      authority != node() and authority not in Node.list(:connected) ->
        {:error, :unavailable}

      authority == node() and is_nil(Process.whereis(Endpoint)) ->
        {:error, :unavailable}

      true ->
        # The stream controller monitors the public caller independently of the
        # blocking receive and kills its task on owner loss or fixed deadline.
        bounded_request(authority, query)
    end
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
    reply = :erlang.alias()

    try do
      case send_safe({Endpoint, authority}, {:offer, self(), reply}) do
        :ok -> receive_offer(reply, query, deadline)
        _ -> {:error, :unavailable}
      end
    after
      :erlang.unalias(reply)
    end
  end

  defp receive_offer(reply, query, deadline) do
    receive do
      {^reply, {:offer, endpoint, token}} when is_pid(endpoint) ->
        if remaining(deadline) > 0 do
          send_safe(endpoint, {:confirm, self(), reply, token, query, remaining(deadline)})
          receive_result(reply, deadline)
        else
          {:error, :timeout}
        end

      {^reply, {:error, reason}} ->
        if remaining(deadline) > 0, do: {:error, reason}, else: {:error, :timeout}
    after
      remaining(deadline) -> {:error, :timeout}
    end
  end

  defp receive_result(reply, deadline) do
    if remaining(deadline) > 0 do
      receive do
        {^reply, {:ping, controller, token}} ->
          budget = remaining(deadline)
          if budget > 0, do: send_safe(controller, {:pong, token, budget})
          receive_result(reply, deadline)

        {^reply, result} ->
          if remaining(deadline) > 0, do: result, else: {:error, :timeout}
      after
        remaining(deadline) -> {:error, :timeout}
      end
    else
      {:error, :timeout}
    end
  end

  def send_safe(destination, message),
    do: :erlang.send(destination, message, [:noconnect, :nosuspend])

  def local(:list, _deadline) do
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

  def local({:lookup, id, expected}, deadline) do
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
