defmodule Beamlet.Runtime do
  @moduledoc "Opt-in, ephemeral, one-attempt distributed operations. See task handoff for wire events."
  alias Beamlet.Actions.{Operation, OperationRef}
  alias Beamlet.Runtime.{Directory, Observation, SharedSupervisor}

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
  """
  def submit(operation, opts \\ []) do
    with :ok <- Operation.validate(operation),
         true <-
           :erlang.external_size(operation) <= Directory.limits().operation_bytes,
         true <-
           is_pid(Keyword.get(opts, :owner, self())) and is_pid(Keyword.get(opts, :sink, self())),
         true <- valid_owner_guard?(opts) do
      id = Base.encode16(:crypto.strong_rand_bytes(16))

      args =
        {id, operation, Keyword.get(opts, :owner, self()), Keyword.get(opts, :sink, self()),
         Keyword.get(opts, :require_live_owner, false)}

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
      _ -> {:error, :invalid_operation}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

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
