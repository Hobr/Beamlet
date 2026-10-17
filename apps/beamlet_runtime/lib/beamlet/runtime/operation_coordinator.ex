defmodule Beamlet.Runtime.OperationCoordinator do
  @moduledoc false
  use GenServer, restart: :temporary
  alias Beamlet.Actions.{Execution, ExecutionHandle, OperationRef, Result}
  alias Beamlet.Runtime.Directory

  def start_link({_, _, owner, _, true} = args) do
    if Process.alive?(owner), do: GenServer.start_link(__MODULE__, args), else: :ignore
  end

  def start_link(args), do: GenServer.start_link(__MODULE__, args)
  @impl true
  def init({id, op, owner, sink}), do: init({id, op, owner, sink, false})

  def init({id, op, owner, sink, guarded}) do
    Process.monitor(owner)

    if owner_alive?(owner, guarded),
      do: initialize(id, op, owner, sink, guarded),
      else: :ignore
  end

  defp initialize(id, op, owner, sink, guarded) do
    # Limits are supplied by the owning shared subtree, including retained coordinators.
    limits = Directory.limits()

    if owner_alive?(owner, guarded) do
      ready(id, op, owner, sink, guarded, limits)
    else
      :ignore
    end
  end

  defp ready(id, op, owner, sink, guarded, limits) do
    Process.send_after(self(), :deadline, op.budget_ms)
    send(self(), :dispatch)

    {:ok,
     %{
       id: id,
       op: op,
       sink: sink,
       owner: owner,
       guarded: guarded,
       limits: limits,
       execution: nil,
       result: nil,
       target: nil,
       gateway: nil,
       sequence: 0,
       progress_dropped: false,
       outstanding: MapSet.new(),
       started: System.monotonic_time(:millisecond),
       stopping: nil
     }}
  end

  @impl true
  def handle_info(:dispatch, %{result: nil, stopping: nil, execution: nil} = s) do
    if owner_alive?(s.owner, s.guarded) do
      selection = Directory.select(s.op)

      if owner_alive?(s.owner, s.guarded),
        do: dispatch(selection, s),
        else: {:stop, :normal, s}
    else
      {:stop, :normal, s}
    end
  end

  def handle_info(
        {:admitted, attempt, %ExecutionHandle{} = handle},
        %{result: nil, execution: %{attempt_id: attempt, handle: nil}} = s
      ) do
    if valid_handle?(handle, s) do
      {:noreply, %{s | execution: %{s.execution | handle: handle, state: :running}}}
    else
      {:noreply, s}
    end
  end

  def handle_info(
        {:rejected, attempt, reason},
        %{result: nil, execution: %{attempt_id: attempt}} = s
      ),
      do: {:noreply, finish(s, :error, reason)}

  def handle_info(
        {:completed, attempt, %ExecutionHandle{} = handle, %Result{} = result},
        %{result: nil, execution: %{attempt_id: attempt}} = s
      ) do
    valid = valid_completion?(result, handle, s)

    if valid do
      {:noreply,
       accept(%{s | execution: %{s.execution | handle: handle, state: :completed}}, result)}
    else
      {:noreply, s}
    end
  end

  def handle_info(
        {:progress, attempt, %ExecutionHandle{} = handle, seq, value},
        %{result: nil, execution: %{attempt_id: attempt}} = s
      ) do
    if valid_progress?(handle, seq, value, attempt, s) do
      send(s.sink, {:beamlet_operation, ref(s), {:progress, attempt, seq, value}})
      {:noreply, %{s | sequence: seq, outstanding: MapSet.put(s.outstanding, seq)}}
    else
      {:noreply, %{s | progress_dropped: true}}
    end
  end

  def handle_info(:admission_timeout, %{result: nil, execution: %{handle: nil}} = s),
    do: {:noreply, finish(s, :uncertain, :admission_timeout)}

  def handle_info(:deadline, %{result: nil} = s),
    do: {:noreply, finish(s, :deadline, :termination_unconfirmed)}

  def handle_info(:cancel_timeout, %{result: nil} = s),
    do: {:noreply, finish(s, :uncertain, :cancel_unconfirmed)}

  def handle_info({:DOWN, _, :process, pid, reason}, %{result: nil} = s) do
    if pid == s.owner or pid == s.target do
      {:noreply,
       finish(
         s,
         :uncertain,
         if(reason == :noconnection, do: :connection_lost, else: :infrastructure_lost)
       )}
    else
      {:noreply, s}
    end
  end

  def handle_info(:expire, s), do: {:stop, :normal, s}
  def handle_info(_, s), do: {:noreply, s}
  @impl true
  def handle_call({id, :status}, _, %{id: id} = s),
    do:
      {:reply,
       {:ok,
        %{
          execution: s.execution,
          result: s.result,
          stopping: s.stopping,
          progress_dropped: s.progress_dropped
        }}, s}

  def handle_call({id, :cancel}, _, %{id: id, result: nil, stopping: :requested} = s),
    do: {:reply, :ok, s}

  def handle_call({id, :cancel}, _, %{id: id, result: nil} = s) do
    cleanup(s)
    Process.send_after(self(), :cancel_timeout, s.limits.cancel_ms + 100)
    {:reply, :ok, %{s | stopping: :requested}}
  end

  def handle_call({id, {:ack, seq}}, _, %{id: id} = s),
    do: {:reply, :ok, %{s | outstanding: MapSet.delete(s.outstanding, seq)}}

  def handle_call(_, _, s), do: {:reply, {:error, :unavailable}, s}

  defp owner_alive?(_, false), do: true
  defp owner_alive?(owner, true), do: Process.alive?(owner)

  defp dispatch(selection, s) do
    case selection do
      :none ->
        {:noreply, finish(s, :error, :no_target)}

      {:ok, endpoint, report} ->
        attempt = Base.encode16(:crypto.strong_rand_bytes(16))
        Process.monitor(endpoint)

        execution = %Execution{
          operation_id: s.id,
          attempt_id: attempt,
          endpoint: endpoint,
          incarnation: report.incarnation
        }

        remaining = max(0, s.op.budget_ms - (System.monotonic_time(:millisecond) - s.started))

        send(
          endpoint,
          {:admit, self(), s.id, attempt, report.incarnation, report.lease, s.op, remaining}
        )

        Process.send_after(self(), :admission_timeout, s.limits.admission_ms)
        {:noreply, %{s | execution: execution, target: endpoint, gateway: report.gateway}}
    end
  end

  defp finish(s, status, reason) do
    cleanup(s)
    execution_id = if s.execution && s.execution.handle, do: s.execution.handle.id

    execution =
      if s.execution,
        do: %{
          s.execution
          | state: if(status in [:uncertain, :deadline], do: :uncertain, else: :completed)
        }

    s = %{s | execution: execution}

    accept(s, %Result{
      operation_id: s.id,
      execution_id: execution_id,
      status: status,
      reason: reason,
      source: :coordinator,
      metadata: %{attempt_id: if(s.execution, do: s.execution.attempt_id)}
    })
  end

  defp accept(s, result) do
    result = %{
      result
      | metadata:
          Map.merge(result.metadata, %{
            attempt_id: if(s.execution, do: s.execution.attempt_id),
            sink_progress_dropped: s.progress_dropped
          })
    }

    result =
      if Result.valid?(result) and
           :erlang.external_size({:beamlet_operation, ref(s), {:result, result}}) <=
             s.limits.result_bytes,
         do: result,
         else: %{
           result
           | status: :error,
             reason: :invalid_or_oversize_result,
             value: nil,
             metadata: %{}
         }

    send(s.sink, {:beamlet_operation, ref(s), {:result, result}})
    Process.send_after(self(), :expire, s.limits.retention_ms)
    %{s | result: result}
  end

  defp valid_completion?(result, handle, s) do
    Result.valid?(result) and result.source == :execution and
      result.operation_id == s.id and result.execution_id == handle.id and
      valid_handle?(handle, s) and matching_handle?(handle, s)
  end

  defp matching_handle?(handle, s), do: is_nil(s.execution.handle) or s.execution.handle == handle

  defp valid_progress?(handle, seq, value, attempt, s) do
    valid_handle?(handle, s) and matching_handle?(handle, s) and
      is_integer(seq) and seq > s.sequence and seq <= s.limits.progress_count and
      MapSet.size(s.outstanding) < s.limits.progress_credit and
      Beamlet.Actions.bounded?(%{sequence: seq, value: value}, s.limits.progress_bytes) and
      :erlang.external_size({:beamlet_operation, ref(s), {:progress, attempt, seq, value}}) <=
        s.limits.progress_bytes
  end

  defp valid_handle?(handle, s) do
    is_binary(handle.id) and byte_size(handle.id) in 1..128 and
      handle.gateway == s.gateway and
      handle.incarnation == s.execution.incarnation
  end

  defp cleanup(%{execution: nil}), do: :ok
  defp cleanup(s), do: send(s.target, {:cancel, self(), s.execution.attempt_id})
  defp ref(s), do: %OperationRef{id: s.id, pid: self()}
end
