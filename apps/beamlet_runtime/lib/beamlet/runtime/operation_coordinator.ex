defmodule Beamlet.Runtime.OperationCoordinator do
  @moduledoc false
  use GenServer, restart: :temporary
  alias Beamlet.Actions.{Execution, ExecutionHandle, OperationRef, Result}
  alias Beamlet.Runtime.{Directory, Persistence}

  def start_link({_, _, owner, _, true, _} = args) do
    if Process.alive?(owner), do: GenServer.start_link(__MODULE__, args), else: :ignore
  end

  def start_link(args), do: GenServer.start_link(__MODULE__, args)
  @impl true
  def init({id, op, owner, sink}), do: init({id, op, owner, sink, false, nil})
  def init({id, op, owner, sink, guarded}), do: init({id, op, owner, sink, guarded, nil})

  def init({id, op, owner, sink, guarded, durable}) do
    Process.monitor(owner)

    if owner_alive?(owner, guarded),
      do: initialize(id, op, owner, sink, guarded, durable),
      else: :ignore
  end

  defp initialize(id, op, owner, sink, guarded, durable) do
    # Limits are supplied by the owning shared subtree, including retained coordinators.
    limits = Directory.limits()

    if owner_alive?(owner, guarded) do
      ready(id, op, owner, sink, guarded, limits, durable)
    else
      :ignore
    end
  end

  defp ready(id, op, owner, sink, guarded, limits, durable) do
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
       stopping: nil,
       durable: durable_state(durable)
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

  # The worker ran but its durable terminal record could not commit. Nothing may be
  # reported as durable completion, and the outcome must stay uncertain instead of
  # becoming a definite error that reads like "never executed".
  def handle_info(
        {:unrecorded, attempt, reason},
        %{result: nil, execution: %{attempt_id: attempt}} = s
      ),
      do: {:noreply, finish(s, :uncertain, reason)}

  def handle_info(
        {:completed, attempt, %ExecutionHandle{} = handle, %Result{} = result},
        %{result: nil, execution: %{attempt_id: attempt}} = s
      ) do
    if valid_completion?(result, handle, s) do
      {:noreply,
       accept(%{s | execution: %{s.execution | handle: handle, state: :completed}}, result)}
    else
      {:noreply, s}
    end
  end

  def handle_info(
        {:completed, attempt, %ExecutionHandle{} = handle, %Result{} = result, receipt},
        %{result: nil, execution: %{attempt_id: attempt}} = s
      ) do
    if valid_completion?(result, handle, s) and valid_receipt?(receipt) do
      {:noreply,
       accept(
         %{s | execution: %{s.execution | handle: handle, state: :completed}},
         result,
         receipt
       )}
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
          progress_dropped: s.progress_dropped,
          durable: durable_status(s.durable)
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
        case claim_dispatch(s) do
          :ok ->
            Process.monitor(endpoint)
            admit(s, endpoint, report)

          {:error, reason} ->
            # A claim that did not commit is never treated as permission to send.
            {:noreply, finish(s, :error, reason)}
        end
    end
  end

  defp admit(s, endpoint, report) do
    attempt =
      if s.durable, do: s.durable.attempt_id, else: Base.encode16(:crypto.strong_rand_bytes(16))

    execution = %Execution{
      operation_id: s.id,
      attempt_id: attempt,
      endpoint: endpoint,
      incarnation: report.incarnation
    }

    remaining = max(0, s.op.budget_ms - (System.monotonic_time(:millisecond) - s.started))

    send(endpoint, admit_message(s, attempt, report, remaining))

    Process.send_after(self(), :admission_timeout, s.limits.admission_ms)

    durable = if s.durable, do: %{s.durable | claimed: true}, else: nil

    {:noreply,
     %{s | execution: execution, target: endpoint, gateway: report.gateway, durable: durable}}
  end

  defp admit_message(s, attempt, report, remaining) do
    message =
      {:admit, self(), s.id, attempt, report.incarnation, report.lease, s.op, remaining}

    case s.durable do
      nil ->
        message

      durable ->
        persistence = durable.persistence

        Tuple.insert_at(message, tuple_size(message), %{
          authority_id: persistence.authority_id,
          operation_id: durable.operation_id,
          attempt_id: durable.attempt_id,
          description_digest: durable.description_digest,
          executor_id: persistence.executor_id,
          executor_boot_id: persistence.executor_boot_id
        })
    end
  end

  # The send claim commits before any admit can leave this process; a failure or an
  # already claimed attempt keeps the operation undelivered.
  defp claim_dispatch(%{durable: nil}), do: :ok

  defp claim_dispatch(s) do
    durable = s.durable

    case Beamlet.Storage.OperationRecords.claim_dispatch(durable.persistence.authority_repo, %{
           operation_id: durable.operation_id,
           attempt_id: durable.attempt_id,
           expected_version: durable.attempt_version
         }) do
      {:ok, _claim} -> :ok
      {:error, _reason} -> {:error, :durable_unavailable}
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

  defp accept(s, result), do: accept(s, result, nil)

  defp accept(s, result, receipt) do
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

    s = %{s | durable: persist(s.durable, result, receipt)}

    if s.durable == nil or s.durable.accepted do
      send(s.sink, {:beamlet_operation, ref(s), {:result, result}})
    end

    Process.send_after(self(), :expire, s.limits.retention_ms)
    %{s | result: result}
  end

  defp persist(nil, _result, _receipt), do: nil

  defp persist(durable, result, receipt) do
    persistence = durable.persistence

    with :ok <- persist_evidence(persistence, durable, receipt),
         {:ok, accepted} <- persist_result(persistence, durable, result, receipt) do
      %{durable | accepted: true, accept_error: nil, operation_version: accepted["lock_version"]}
    else
      {:error, reason} -> %{durable | accepted: false, accept_error: reason}
    end
  end

  defp persist_evidence(_persistence, _durable, nil), do: :ok

  defp persist_evidence(persistence, durable, receipt) do
    case Beamlet.Storage.OperationRecords.record_evidence(persistence.authority_repo, %{
           id: receipt.id,
           operation_id: durable.operation_id,
           attempt_id: durable.attempt_id,
           executor_id: persistence.executor_id,
           evidence_id: receipt.id,
           content: Persistence.evidence(receipt)
         }) do
      {:ok, _evidence} -> :ok
      {:error, _reason} -> {:error, :durable_unavailable}
    end
  end

  defp persist_result(persistence, durable, result, receipt) do
    attrs = %{
      operation_id: durable.operation_id,
      expected_version: durable.operation_version,
      result: Persistence.result_payload(result),
      evidence_id: receipt && receipt.id,
      event: %{
        id: Persistence.uuid(),
        type: "operation.result_accepted",
        payload: %{
          "status" => Atom.to_string(result.status),
          "attempt_id" => durable.attempt_id
        }
      }
    }

    attrs =
      case persistence.owner do
        nil ->
          attrs

        owner ->
          Map.put(attrs, :agent, accept_identity(owner))
      end

    case Beamlet.Storage.OperationRecords.accept_result(persistence.authority_repo, attrs) do
      {:ok, accepted} -> {:ok, accepted}
      {:error, _reason} -> {:error, :durable_unavailable}
    end
  end

  # An owner carries exactly one Agent position: the strict version CAS or the
  # position a whole batch reserved for this Operation's accepted Result.
  defp accept_identity(owner) do
    agent = %{expected_generation: owner.expected_generation}

    case owner[:accept_seq] do
      nil -> Map.put(agent, :expected_version, owner.expected_version)
      seq -> Map.put(agent, :accept_seq, seq)
    end
  end

  defp durable_state(nil), do: nil

  defp durable_state({persistence, prepared}) do
    %{
      persistence: persistence,
      operation_id: prepared["operation_id"],
      description_digest: prepared["description_digest"],
      attempt_id: prepared["attempt_id"],
      attempt_version: prepared["attempt_version"] || 0,
      operation_version: prepared["lock_version"],
      claimed: false,
      accepted: false,
      accept_error: nil
    }
  end

  defp durable_status(nil), do: nil

  defp durable_status(durable) do
    Map.take(durable, [:operation_id, :attempt_id, :claimed, :accepted, :accept_error])
  end

  defp valid_receipt?(receipt) do
    is_map(receipt) and not is_struct(receipt) and is_binary(receipt[:id]) and
      is_binary(receipt[:digest]) and is_map(receipt[:content]) and
      not is_struct(receipt[:content])
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
