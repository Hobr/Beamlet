defmodule Beamlet.Runtime do
  @moduledoc """
  Opt-in, one-attempt distributed operations, ephemeral by default.

  Supplying `persistence: %Beamlet.Runtime.Persistence{}` keeps the existing
  in-memory worker/supervision model but adds authority prepare/claim/accept and
  an executor-local attempt journal around it. Omitting it keeps today's
  behaviour exactly.
  """
  alias Beamlet.Actions.{Operation, OperationRef}
  alias Beamlet.Runtime.{Directory, Observation, Persistence, SharedSupervisor}

  @doc """
  Safe Directory-owned report observation, `{:ok, %{version: 1, source: node,
  expiry_ms: integer, reports: list, complete: boolean}}`.

  Reports contain node, status (`fresh`, `stale`, `not_reported`) and age_ms
  (nonnegative receipt age on this VM, or `unknown`). Received reports also
  contain ready/execution_ready booleans, capabilities/environments lists and
  available pool quantities. These are advisory available quantities, never
  totals, utilization or reservations. Missing reports do not establish death.
  Empty reports means no observed members. Stale reports remain until departure.
  At most256 reports and1,000,000 full serialized reply bytes; count overflow
  sets complete=false, byte overflow returns `{:error, :limit}`.
  Finite5s read; static errors are timeout/unavailable/limit. No work is submitted.
  This is a non-atomic observation; no private leases or timestamps are exported.
  """
  def observation, do: Observation.read(Directory, :observation, 5000)

  def child_spec(opts), do: SharedSupervisor.child_spec(opts)

  @doc """
  Submits one operation using the current deployment limits.

  Owner and sink default to the caller. Optional `require_live_owner: true`
  requires a local owner PID and rejects dead ownership at startup and before
  dispatch, including after blocking Directory reads. Startup rejection returns
  `{:error, :unavailable}`. The default permits remote owners as before.

  Optional `persistence: %Beamlet.Runtime.Persistence{}` enables the durable path:
  the immutable Operation and one prepared attempt are committed before any admit
  is sent, and a failed authority write returns `{:error, :invalid_operation |
  :unavailable}` having dispatched nothing. Without it the operation stays
  ephemeral and in-memory. The struct is authoritative input, so an invalid one
  raises instead of returning a tuple.

  Optional `prepared:` dispatches an attempt another authority transaction already
  committed (a whole Tool batch prepares its Operations together). The map is the
  committed `operation_id`, `attempt_id`, `attempt_version`, `description_digest`
  and `lock_version`; this call then writes no Operation row of its own and no
  unrelated id can appear in the caller's batch.
  """
  def submit(operation, opts \\ []) do
    with :ok <- Operation.validate(operation),
         true <-
           :erlang.external_size(operation) <= Directory.limits().operation_bytes,
         true <-
           is_pid(Keyword.get(opts, :owner, self())) and is_pid(Keyword.get(opts, :sink, self())),
         true <- valid_owner_guard?(opts),
         :ok <- coordinators_available(Keyword.get(opts, :persistence)),
         persistence <- Persistence.new(Keyword.get(opts, :persistence)),
         {:ok, prepared} <- prepare(persistence, operation, Keyword.get(opts, :prepared)) do
      {id, durable} =
        case prepared do
          nil -> {Base.encode16(:crypto.strong_rand_bytes(16)), nil}
          prepared -> {prepared["operation_id"], {persistence, prepared}}
        end

      args =
        {id, operation, Keyword.get(opts, :owner, self()), Keyword.get(opts, :sink, self()),
         Keyword.get(opts, :require_live_owner, false), durable}

      case DynamicSupervisor.start_child(
             Beamlet.Runtime.Coordinators,
             {Beamlet.Runtime.OperationCoordinator, args}
           ) do
        {:ok, pid} -> {:ok, %OperationRef{id: id, pid: pid}}
        {:error, :max_children} -> {:error, :capacity}
        {:error, _} -> {:error, :unavailable}
        :ignore -> {:error, :unavailable}
      end
    else
      {:error, reason} when reason in [:invalid_operation, :unavailable] -> {:error, reason}
      _ -> {:error, :invalid_operation}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @doc """
  Read-only Evidence query using stable IDs only: the authority Operation and one
  attempt, plus the executor journal row when this attempt was claimed there.

  No coordinator, dispatch, sink or retry is involved. `journal: :not_found`
  means this journal has no row; it is not proof that the handler never ran, and
  `journal: :unavailable` means the journal could not be read at all.
  """
  def evidence(%Persistence{} = persistence, operation_id, attempt_id) do
    with {:ok, authority} <-
           Beamlet.Storage.OperationRecords.fetch(persistence.authority_repo, operation_id) do
      journal =
        case Beamlet.Storage.ExecutorJournal.fetch(
               persistence.journal_repo,
               persistence.authority_id,
               attempt_id
             ) do
          {:ok, row} -> row
          # An absent row and a journal that cannot be read are different facts:
          # `:not_found` must never be produced by a storage outage.
          {:error, :conflict} -> :not_found
          {:error, _reason} -> :unavailable
        end

      {:ok, %{authority: authority, journal: journal}}
    end
  end

  defp prepare(nil, _operation, nil), do: {:ok, nil}

  defp prepare(%Persistence{} = persistence, operation, nil) do
    Persistence.prepare(persistence, operation)
  end

  # An attempt committed with its Operation is dispatched as it stands: preparing
  # again would mint an unrelated Operation and leave the caller's row unaccepted.
  defp prepare(%Persistence{}, _operation, prepared), do: prepared(prepared)

  defp prepare(nil, _operation, _prepared), do: {:error, :invalid_operation}

  defp prepared(prepared) when is_map(prepared) and not is_struct(prepared) do
    valid =
      Beamlet.Storage.Codec.uuid?(prepared["operation_id"]) and
        Beamlet.Storage.Codec.uuid?(prepared["attempt_id"]) and
        is_binary(prepared["description_digest"]) and
        non_negative?(prepared["attempt_version"]) and
        non_negative?(prepared["lock_version"])

    if valid, do: {:ok, prepared}, else: {:error, :invalid_operation}
  end

  defp prepared(_), do: {:error, :invalid_operation}

  defp non_negative?(value), do: is_integer(value) and value >= 0

  # A durable submit commits an Operation and a prepared attempt, so refuse before
  # writing when no coordinator can ever pick it up: an orphan prepared attempt has
  # no id the caller could reconcile with. A host that configured durable storage
  # also gates this on live durable admission, which is a fresh probe of the
  # dataset and never the cached readiness of a registered Repo.
  defp coordinators_available(nil), do: :ok

  defp coordinators_available(%Persistence{}) do
    with :ok <- Beamlet.Storage.Admission.consult(),
         true <- Process.whereis(Beamlet.Runtime.Coordinators) != nil do
      :ok
    else
      _refused -> {:error, :unavailable}
    end
  end

  defp coordinators_available(_), do: :ok

  defp valid_owner_guard?(opts) do
    case Keyword.get(opts, :require_live_owner, false) do
      false -> true
      true -> node(Keyword.get(opts, :owner, self())) == node()
      _ -> false
    end
  end

  def status(%OperationRef{} = ref), do: control(ref, :status)
  def cancel(%OperationRef{} = ref), do: control(ref, :cancel)
  def ack(%OperationRef{} = ref, sequence), do: control(ref, {:ack, sequence})

  defp control(ref, command) do
    GenServer.call(ref.pid, {ref.id, command})
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
