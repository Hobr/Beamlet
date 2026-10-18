defmodule Beamlet.Runtime.ExecutorGateway do
  @moduledoc false
  use GenServer
  alias Beamlet.Actions.{ExecutionHandle, Operation, Result}
  alias Beamlet.Runtime.{NodeEndpoint, Persistence, Report, Worker, Workers}
  alias Beamlet.Storage.{Codec, ExecutorJournal}
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
    persistence = Keyword.get(opts, :persistence)
    journal_ready = mark_restarted_attempts(persistence)
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
       persistence: persistence,
       journal_ready: journal_ready,
       ready: journal_ready
     }}
  end

  # A new executor boot never rebuilds a worker: prior start intents become
  # unknown_after_restart and stay non-terminal, and no capacity is restored.
  # At boot this gateway owns no live worker: `:one_for_all` has already killed any
  # previous ones, so every remaining start intent is orphaned regardless of which
  # boot id wrote it. Leaving a same-boot row at start_intent would make it
  # unreachable for both terminal and restart classification.
  defp mark_restarted_attempts(nil), do: true

  defp mark_restarted_attempts(%Persistence{} = persistence) do
    case safe_journal(fn ->
           ExecutorJournal.mark_unknown_after_restart(persistence.journal_repo, %{
             authority_id: persistence.authority_id,
             executor_id: persistence.executor_id
           })
         end) do
      {:ok, %{"marked" => _count}} -> true
      _ -> false
    end
  end

  # Facade errors stay safe atoms; an unavailable Repo must never crash admission.
  defp safe_journal(fun) do
    fun.()
  rescue
    _ -> {:error, :durable_unavailable}
  catch
    :exit, _ -> {:error, :durable_unavailable}
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

  def handle_info({:admit, _, _, _, _, _, _, _} = message, s), do: admit_message(message, s)
  def handle_info({:admit, _, _, _, _, _, _, _, _} = message, s), do: admit_message(message, s)

  def handle_info({:cancel, coordinator, attempt}, s) do
    {:noreply, stop_worker(s, {coordinator, attempt}, :cancelled)}
  end

  def handle_info({:execution_deadline, key, pid}, s) do
    if match?(%{task: %{pid: ^pid}}, s.attempts[key]),
      do: {:noreply, stop_worker(s, key, :deadline)},
      else: {:noreply, s}
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

        complete(s, key, entry, result, %{"kind" => "returned"})
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

        stopped = observed_stop?(entry, reason)

        result = %Result{
          operation_id: entry.id,
          execution_id: entry.handle.id,
          status: if(stopped, do: entry.stop_source, else: :error),
          reason: if(stopped, do: :worker_stopped, else: :worker_lost),
          source: :execution
        }

        complete(s, key, entry, result, termination(reason))

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

  defp observed_stop?(entry, reason) do
    :atomics.get(entry.cancellation, 1) == 1 and
      (reason == :shutdown or (reason == :killed and entry.kill_requested))
  end

  # The first trigger processed here owns provenance, including kill escalation.
  defp stop_worker(s, key, source) do
    case s.attempts[key] do
      %{task: task, cancellation: cancellation, stop_source: nil} = entry ->
        entry =
          if :atomics.exchange(cancellation, 1, 1) == 0 do
            entry = journal_stop(s, entry, source)
            Process.exit(task.pid, :shutdown)
            Process.send_after(self(), {:kill, key, task.pid}, s.limits.cancel_ms)
            entry
          else
            entry
          end

        put_in(s, [:attempts, key], %{entry | stop_source: source})

      _ ->
        s
    end
  end

  # The first durable stop cause is recorded before the worker can terminate; a
  # later competing trigger cannot replace it. A failed write never blocks stop.
  defp journal_stop(_s, %{journal: nil} = entry, _source), do: entry

  defp journal_stop(s, entry, source) do
    journal = entry.journal

    case safe_journal(fn ->
           ExecutorJournal.record_stop(s.persistence.journal_repo, %{
             authority_id: journal.authority_id,
             attempt_id: journal.attempt_id,
             stop_reason: source,
             expected_version: journal.lock_version
           })
         end) do
      {:ok, %{"state" => "start_intent", "lock_version" => version}} ->
        %{entry | journal: %{journal | lock_version: version}}

      _ ->
        entry
    end
  end

  defp admit_message({:admit, coordinator, id, attempt, incarnation, lease, op, remaining}, s)
       when is_pid(coordinator) and is_binary(id) and byte_size(id) in 1..128 and
              is_binary(attempt) and byte_size(attempt) in 1..128 do
    admission(s, admit_request(coordinator, id, attempt, incarnation, lease, op, remaining, nil))
  end

  defp admit_message(
         {:admit, coordinator, id, attempt, incarnation, lease, op, remaining, durable},
         s
       )
       when is_pid(coordinator) and is_binary(id) and byte_size(id) in 1..128 and
              is_binary(attempt) and byte_size(attempt) in 1..128 do
    admission(
      s,
      admit_request(coordinator, id, attempt, incarnation, lease, op, remaining, durable)
    )
  end

  defp admit_message(_, s), do: {:noreply, s}

  # The admit form carries the same eight fields as an Executor request; keeping
  # them in one map lets admission/2 stay a single readable decision.
  defp admit_request(coordinator, id, attempt, incarnation, lease, op, remaining, durable) do
    %{
      coordinator: coordinator,
      id: id,
      attempt: attempt,
      incarnation: incarnation,
      lease: lease,
      op: op,
      remaining: remaining,
      durable: durable
    }
  end

  defp admission(s, request) do
    key = {request.coordinator, request.attempt}
    remaining = remaining_budget(request.remaining, request.lease)

    cond do
      Map.has_key?(s.attempts, key) ->
        {:noreply, s}

      map_size(s.attempts) >= s.limits.attempts ->
        send(request.coordinator, {:rejected, request.attempt, :capacity})
        # Saturation invalidates old leases even when no tombstone slot is available.
        {:noreply, %{s | rejected_through: System.monotonic_time(:millisecond)}}

      not valid_admission?(s, request.incarnation, request.lease, request.op, remaining) ->
        send(request.coordinator, {:rejected, request.attempt, :ineligible})
        {:noreply, remember(s, key, :rejected)}

      true ->
        case claim_start(s, request.attempt, request.durable, request.op) do
          {:ok, journal} ->
            admit(s, key, request.id, request.op, remaining, journal)

          {:error, reason} ->
            # No journal start intent means no worker: capacity was never charged.
            send(request.coordinator, {:rejected, request.attempt, reason})
            {:noreply, remember(s, key, :rejected)}
        end
    end
  end

  defp claim_start(%{persistence: nil}, _attempt, nil, _op), do: {:ok, nil}

  defp claim_start(%{persistence: nil}, _attempt, _durable, _op),
    do: {:error, :durable_unavailable}

  defp claim_start(%{journal_ready: false}, _attempt, _durable, _op),
    do: {:error, :durable_unavailable}

  defp claim_start(_s, _attempt, nil, _op), do: {:error, :durable_unavailable}

  defp claim_start(s, attempt, durable, op) do
    persistence = s.persistence

    if valid_durable?(durable, attempt, persistence, op) do
      case safe_journal(fn ->
             ExecutorJournal.fetch(
               persistence.journal_repo,
               persistence.authority_id,
               durable.attempt_id
             )
           end) do
        {:ok, _stored} ->
          {:error, :duplicate_admission}

        {:error, _reason} ->
          start_intent(s, durable)
      end
    else
      {:error, :durable_unavailable}
    end
  end

  defp valid_durable?(durable, attempt, persistence, op) do
    is_map(durable) and not is_struct(durable) and
      durable[:attempt_id] == attempt and
      durable[:authority_id] == persistence.authority_id and
      durable[:executor_id] == persistence.executor_id and
      durable[:executor_boot_id] == persistence.executor_boot_id and
      is_binary(durable[:operation_id]) and is_binary(durable[:description_digest]) and
      digest_matches?(durable, op)
  end

  # The journal must describe the work actually executed, not whatever digest the
  # admit message claimed.
  defp digest_matches?(durable, %Operation{} = op) do
    description = Persistence.description(op)

    case Codec.digest(description, :operation) do
      {:ok, digest} -> digest == durable[:description_digest]
      _ -> false
    end
  rescue
    _ -> false
  end

  defp start_intent(s, durable) do
    persistence = s.persistence

    case safe_journal(fn ->
           ExecutorJournal.claim_start(persistence.journal_repo, %{
             id: Persistence.uuid(),
             authority_id: persistence.authority_id,
             operation_id: durable.operation_id,
             attempt_id: durable.attempt_id,
             description_digest: durable.description_digest,
             executor_id: persistence.executor_id,
             executor_boot_id: persistence.executor_boot_id
           })
         end) do
      {:ok, %{"state" => "start_intent", "lock_version" => version}} ->
        {:ok,
         %{
           authority_id: persistence.authority_id,
           operation_id: durable.operation_id,
           attempt_id: durable.attempt_id,
           description_digest: durable.description_digest,
           executor_id: persistence.executor_id,
           executor_boot_id: persistence.executor_boot_id,
           lock_version: version,
           receipt_id: Persistence.uuid()
         }}

      {:ok, _stored} ->
        {:error, :duplicate_admission}

      {:error, :conflict} ->
        {:error, :duplicate_admission}

      {:error, _reason} ->
        {:error, :durable_unavailable}
    end
  end

  defp remaining_budget(remaining, lease) when is_integer(remaining) and is_integer(lease),
    do: remaining - max(0, System.monotonic_time(:millisecond) - lease)

  defp remaining_budget(_, _), do: 0

  defp admit(s, {coordinator, attempt} = key, id, op, remaining, journal) do
    {module, settings} = Map.fetch!(s.handlers, op.kind)

    handle = %ExecutionHandle{
      id: Base.encode16(:crypto.strong_rand_bytes(16)),
      gateway: self(),
      incarnation: s.incarnation
    }

    cancellation = :atomics.new(1, [])

    # The start intent must be durable before the worker exists; claim_start above
    # already committed it, so only local supervision happens here.
    task =
      Task.Supervisor.async_nolink(Workers, Worker, :run, [
        module,
        op.payload,
        op.credentials,
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
      stop_source: nil,
      progress_dropped: false,
      cancellation: cancellation,
      journal: journal
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

  # Exactly one durable terminal observation exists per attempt and it commits
  # before the coordinator may hear a completion. If it cannot commit, nothing is
  # reported as durably complete.
  defp complete(s, key, entry, result, termination) do
    case record_terminal(s, entry, result, termination) do
      {:ok, receipt} ->
        message =
          if receipt,
            do: {:completed, elem(key, 1), entry.handle, result, receipt},
            else: {:completed, elem(key, 1), entry.handle, result}

        send(elem(key, 0), message)
        {:noreply, release(s, key)}

      {:error, _reason} ->
        # The handler may have run: report an unrecorded outcome, never a rejection.
        send(elem(key, 0), {:unrecorded, elem(key, 1), :durable_unavailable})
        {:noreply, release(s, key)}
    end
  end

  defp record_terminal(_s, %{journal: nil}, _result, _termination), do: {:ok, nil}

  defp record_terminal(s, entry, result, termination) do
    journal = entry.journal

    with {:ok, receipt} <- Persistence.receipt(journal, result, termination),
         {:ok, _stored} <-
           safe_journal(fn ->
             ExecutorJournal.record_terminal(s.persistence.journal_repo, %{
               authority_id: journal.authority_id,
               attempt_id: journal.attempt_id,
               expected_version: journal.lock_version,
               termination: termination,
               terminal_result: receipt.content["result"],
               terminal_artifacts: %{"version" => 1, "items" => %{}},
               receipt_id: receipt.id,
               receipt_digest: receipt.digest,
               receipt: receipt.content
             })
           end) do
      {:ok, receipt}
    end
  end

  defp termination(:normal), do: %{"kind" => "exit", "reason" => "normal"}
  defp termination(:shutdown), do: %{"kind" => "exit", "reason" => "shutdown"}
  defp termination(:killed), do: %{"kind" => "exit", "reason" => "killed"}
  defp termination(_reason), do: %{"kind" => "exit", "reason" => "other"}

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
