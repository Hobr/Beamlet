defmodule Beamlet.Runtime.ExecutorGateway do
  @moduledoc false
  use GenServer
  alias Beamlet.Actions.{ExecutionHandle, Operation, Result}
  alias Beamlet.Runtime.{NodeEndpoint, Report, Worker, Workers}
  def start_link(args), do: GenServer.start_link(__MODULE__, args, name: __MODULE__)

  def eligible?(op, r) do
    r.ready and Map.has_key?(r.handlers, op.kind) and op.version == 1 and
      Enum.all?(op.capabilities, &(&1 in r.capabilities)) and
      (is_nil(op.environment) or op.environment in r.environments) and
      (is_nil(op.allowed_nodes) or r.node in op.allowed_nodes) and
      Enum.all?(op.claims, fn {pool, units} -> Map.get(r.available, pool, 0) >= units end)
  end

  @impl true
  def init({opts, limits}) do
    Report.validate_configuration!(opts, limits)
    handlers = Keyword.get(opts, :handlers, %{})
    pools = Keyword.get(opts, :pools, %{})

    unless is_map(handlers) and is_map(pools) and
             Enum.all?(pools, fn {k, v} -> is_binary(k) and is_integer(v) and v > 0 end),
           do: raise(ArgumentError, "invalid executor configuration")

    providers = Keyword.get(opts, :providers, [])
    monitors = Map.new(providers, fn pid -> {Process.monitor(pid), pid} end)
    if endpoint = Process.whereis(NodeEndpoint), do: send(endpoint, {:gateway_ready, self()})

    {:ok,
     %{
       limits: limits,
       handlers: handlers,
       pools: pools,
       available: pools,
       capabilities: Keyword.get(opts, :capabilities, []),
       environments: Keyword.get(opts, :environments, []),
       incarnation: make_ref(),
       attempts: %{},
       rejected_through: System.monotonic_time(:millisecond) - 1,
       tasks: %{},
       owners: %{},
       providers: monitors,
       ready: true
     }}
  end

  @impl true
  def handle_info({:report, endpoint, nonce}, s) do
    report = %{
      gateway: self(),
      handlers: Map.new(s.handlers, fn {k, _} -> {k, true} end),
      available: s.available,
      capabilities: if(s.ready, do: s.capabilities, else: []),
      environments: if(s.ready, do: s.environments, else: []),
      incarnation: s.incarnation,
      lease: System.monotonic_time(:millisecond),
      node: node(),
      ready: s.ready,
      execution_ready: s.ready,
      utilization: utilization(s)
    }

    send(endpoint, {:report, Process.whereis(NodeEndpoint), nonce, report})
    {:noreply, s}
  end

  def handle_info({:admit, coordinator, id, attempt, incarnation, lease, op, remaining}, s)
      when is_pid(coordinator) and is_binary(id) and byte_size(id) in 1..128 and
             is_binary(attempt) and byte_size(attempt) in 1..128 do
    admission(s, coordinator, id, attempt, incarnation, lease, op, remaining)
  end

  def handle_info({:cancel, coordinator, attempt}, s) do
    key = {coordinator, attempt}

    case s.attempts[key] do
      %{task: task, cancellation: cancellation} ->
        if :atomics.exchange(cancellation, 1, 1) == 0 do
          Process.exit(task.pid, :shutdown)
          Process.send_after(self(), {:kill, key, task.pid}, s.limits.cancel_ms)
        end

      _ ->
        :ok
    end

    {:noreply, s}
  end

  def handle_info({:execution_deadline, key, pid}, s) do
    if match?(%{task: %{pid: ^pid}}, s.attempts[key]),
      do: send(self(), {:cancel, elem(key, 0), elem(key, 1)})

    {:noreply, s}
  end

  def handle_info({:kill, key, pid}, s) do
    if match?(%{task: %{pid: ^pid}}, s.attempts[key]) do
      Process.exit(pid, :kill)
      {:noreply, put_in(s, [:attempts, key, :kill_requested], true)}
    else
      {:noreply, s}
    end
  end

  def handle_info({:expire, key}, s), do: {:noreply, %{s | attempts: Map.delete(s.attempts, key)}}

  def handle_info({ref, result}, s) when is_reference(ref) do
    case s.tasks[ref] do
      nil ->
        {:noreply, s}

      key ->
        entry = s.attempts[key]
        result = normalize(result, entry)

        result =
          if :erlang.external_size({:completed, elem(key, 1), entry.handle, result}) <=
               s.limits.result_bytes,
             do: result,
             else: %{
               result
               | status: :error,
                 value: nil,
                 reason: :invalid_or_oversize_result,
                 metadata: %{}
             }

        send(elem(key, 0), {:completed, elem(key, 1), entry.handle, result})
        {:noreply, release(s, key)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, s) do
    cond do
      Map.has_key?(s.providers, ref) ->
        Enum.each(s.tasks, fn {_, key} -> Process.exit(s.attempts[key].task.pid, :kill) end)
        {:noreply, %{s | ready: false, providers: Map.delete(s.providers, ref)}}

      Map.has_key?(s.tasks, ref) ->
        key = s.tasks[ref]
        entry = s.attempts[key]

        result = %Result{
          operation_id: entry.id,
          execution_id: entry.handle.id,
          status: :error,
          reason:
            if(
              :atomics.get(entry.cancellation, 1) == 1 and
                (reason == :shutdown or (reason == :killed and entry.kill_requested)),
              do: :worker_stopped,
              else: :worker_lost
            ),
          source: :execution
        }

        send(elem(key, 0), {:completed, elem(key, 1), entry.handle, result})
        {:noreply, release(s, key)}

      Map.has_key?(s.owners, ref) ->
        key = s.owners[ref]
        send(self(), {:cancel, elem(key, 0), elem(key, 1)})
        {:noreply, s}

      true ->
        {:noreply, s}
    end
  end

  def handle_info({:progress, pid, seq, value, counters}, s) do
    :atomics.sub(counters, 2, 1)

    case Enum.find(s.attempts, fn {_, entry} -> is_map(entry) and entry.task.pid == pid end) do
      {key, entry} ->
        message = {:progress, elem(key, 1), entry.handle, seq, value}

        if :erlang.external_size(message) <= s.limits.progress_bytes do
          send(elem(key, 0), message)
          {:noreply, s}
        else
          {:noreply, put_in(s, [:attempts, key, :progress_dropped], true)}
        end

      nil ->
        {:noreply, s}
    end
  end

  def handle_info(_, s), do: {:noreply, s}

  defp admission(s, coordinator, id, attempt, incarnation, lease, op, remaining) do
    key = {coordinator, attempt}
    remaining = remaining_budget(remaining, lease)

    cond do
      Map.has_key?(s.attempts, key) ->
        {:noreply, s}

      map_size(s.attempts) >= s.limits.attempts ->
        send(coordinator, {:rejected, attempt, :capacity})
        # Saturation invalidates old leases even when no tombstone slot is available.
        {:noreply, %{s | rejected_through: System.monotonic_time(:millisecond)}}

      not valid_admission?(s, incarnation, lease, op, remaining) ->
        send(coordinator, {:rejected, attempt, :ineligible})
        {:noreply, remember(s, key, :rejected)}

      true ->
        admit(s, key, id, op, remaining)
    end
  end

  defp remaining_budget(remaining, lease) when is_integer(remaining) and is_integer(lease),
    do: remaining - max(0, System.monotonic_time(:millisecond) - lease)

  defp remaining_budget(_, _), do: 0

  defp admit(s, {coordinator, attempt} = key, id, op, remaining) do
    {module, settings} = Map.fetch!(s.handlers, op.kind)

    handle = %ExecutionHandle{
      id: Base.encode16(:crypto.strong_rand_bytes(16)),
      gateway: self(),
      incarnation: s.incarnation
    }

    cancellation = :atomics.new(1, [])

    task =
      Task.Supervisor.async_nolink(Workers, Worker, :run, [
        module,
        op.payload,
        settings,
        self(),
        remaining,
        s.limits,
        cancellation
      ])

    Process.send_after(self(), {:execution_deadline, key, task.pid}, remaining)
    owner = Process.monitor(coordinator)

    entry = %{
      task: task,
      owner: owner,
      claims: op.claims,
      handle: handle,
      id: id,
      kill_requested: false,
      progress_dropped: false,
      cancellation: cancellation
    }

    send(coordinator, {:admitted, attempt, handle})

    {:noreply,
     %{
       s
       | attempts: Map.put(s.attempts, key, entry),
         tasks: Map.put(s.tasks, task.ref, key),
         owners: Map.put(s.owners, owner, key),
         available: charge(s.available, op.claims, -1)
     }}
  rescue
    _ ->
      send(coordinator, {:rejected, attempt, :capacity})
      {:noreply, remember(s, key, :rejected)}
  catch
    :exit, _ ->
      send(coordinator, {:rejected, attempt, :capacity})
      {:noreply, remember(s, key, :rejected)}
  end

  defp normalize({:worker_result, result, metadata}, e) do
    result = normalize(result, e)

    bounded(%{
      result
      | metadata:
          Map.merge(
            result.metadata,
            Map.put(metadata, :gateway_progress_dropped, e.progress_dropped)
          )
    })
  end

  defp normalize({:ok, value}, e),
    do:
      bounded(%Result{
        operation_id: e.id,
        execution_id: e.handle.id,
        status: :ok,
        value: value,
        source: :execution
      })

  defp normalize({:error, reason}, e),
    do:
      bounded(%Result{
        operation_id: e.id,
        execution_id: e.handle.id,
        status: :error,
        reason: reason,
        source: :execution
      })

  defp normalize(_, e), do: normalize({:error, :invalid_handler_result}, e)

  defp bounded(r) do
    if Result.valid?(r),
      do: r,
      else: %{r | status: :error, value: nil, reason: :invalid_or_oversize_result}
  end

  defp release(s, key) do
    e = s.attempts[key]
    Process.demonitor(e.task.ref, [:flush])
    Process.demonitor(e.owner, [:flush])

    s = %{
      s
      | available: charge(s.available, e.claims, 1),
        tasks: Map.delete(s.tasks, e.task.ref),
        owners: Map.delete(s.owners, e.owner)
    }

    remember(s, key, :terminal)
  end

  defp remember(s, key, value) do
    Process.send_after(
      self(),
      {:expire, key},
      max(s.limits.retention_ms, s.limits.expiry_ms) + s.limits.admission_ms
    )

    %{s | attempts: Map.put(s.attempts, key, value)}
  end

  defp charge(pools, claims, sign),
    do: Enum.reduce(claims, pools, fn {k, v}, acc -> Map.update!(acc, k, &(&1 + sign * v)) end)

  defp report(s),
    do: %{
      ready: s.ready,
      handlers: s.handlers,
      available: s.available,
      capabilities: s.capabilities,
      environments: s.environments,
      node: node()
    }

  defp valid_admission?(s, incarnation, lease, op, remaining) do
    valid_lease?(s, lease) and incarnation == s.incarnation and Operation.validate(op) == :ok and
      :erlang.external_size(op) <= s.limits.operation_bytes and
      eligible?(op, report(s)) and is_integer(remaining) and remaining > 0
  end

  defp valid_lease?(s, lease) do
    now = System.monotonic_time(:millisecond)

    is_integer(lease) and now - lease <= s.limits.expiry_ms and lease <= now and
      lease > s.rejected_through
  end

  defp utilization(s) do
    Enum.reduce(s.pools, 0.0, fn {k, v}, acc -> acc + (v - s.available[k]) / v end)
  end
end
