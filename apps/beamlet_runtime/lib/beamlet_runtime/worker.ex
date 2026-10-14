defmodule BeamletRuntime.Worker do
  @moduledoc """
  Local Worker session. Each start generates a fresh incarnation; grants, started
  tombstones and unacknowledged reports are local to that session. Tasks perform
  external calls outside SQL. A tombstone is installed before task dispatch and
  never removed during this session. Capacity exhaustion refuses new calls.

  Report retry/lease renewal never invokes the Handler again. Crash can lose a
  result before Stored; recovery then requires original query/callback evidence
  or remains Unknown. deliver/2 is trusted local delivery, not a wire endpoint.
  """
  use GenServer
  alias Beamlet.{Domain, Identity, Lease, Report}
  alias BeamletRuntime.{Coordinator, Grant, Registry}
  alias BeamletRuntime.Storage.Commit

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  def session(worker), do: GenServer.call(worker, :session)
  def run(worker, id, execution_id), do: GenServer.call(worker, {:run, id, execution_id}, 30_000)
  def deliver(worker, grant), do: GenServer.call(worker, {:deliver, grant}, 30_000)
  def flush(worker), do: GenServer.call(worker, :flush, 30_000)

  @impl true
  def format_status(status) do
    status
    |> Map.replace(:state, :redacted)
    |> Map.replace(:message, :redacted)
    |> Map.replace(:reason, :redacted)
    |> Map.replace(:log, [])
  end

  @impl true
  def init(opts) do
    coordinator = Keyword.fetch!(opts, :coordinator)
    id = Keyword.fetch!(opts, :id)
    capacity = Keyword.get(opts, :capacity, 10_000)
    interval = Keyword.get(opts, :maintenance_interval, max(1, div(coordinator.ttl, 3)))

    if not Identity.valid_text?(id) or not is_integer(capacity) or capacity < 1 or
         not is_integer(interval) or interval < 1,
       do: raise(ArgumentError, "invalid Worker configuration")

    state = %{
      coordinator: coordinator,
      id: id,
      incarnation: Ecto.UUID.generate(),
      environment: Keyword.get(opts, :environment, %{}),
      capacity: capacity,
      interval: interval,
      started: MapSet.new(),
      tasks: %{},
      reports: %{}
    }

    Process.send_after(self(), :maintain, interval)
    {:ok, state}
  end

  @impl true
  def handle_call(:session, _from, state), do: {:reply, {state.id, state.incarnation}, state}
  def handle_call(:flush, _from, state), do: {:reply, :ok, flush_reports(state)}

  def handle_call({:run, id, execution_id}, _from, state) do
    key = {state.coordinator.collection, id, execution_id}

    cond do
      MapSet.member?(state.started, key) ->
        {:reply, :already_started, state}

      MapSet.size(state.started) >= state.capacity ->
        {:reply, {:error, :session_capacity_exhausted}, state}

      true ->
        case obtain_grant(state, id, execution_id) do
          {:ok, grant} -> deliver_grant(state, grant)
          error -> {:reply, error, state}
        end
    end
  end

  def handle_call({:deliver, %Grant{} = grant}, _from, state), do: deliver_grant(state, grant)
  def handle_call(_unsupported, _from, state), do: {:reply, {:error, :unsupported_request}, state}

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case Map.pop(state.tasks, ref) do
      {nil, _tasks} ->
        {:noreply, state}

      {{grant, report_id}, tasks} ->
        updated = %{state | tasks: tasks}
        {:noreply, result_report(updated, grant, report_id, result) |> flush_reports()}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state),
    do: {:noreply, %{state | tasks: Map.delete(state.tasks, ref)}}

  def handle_info(:maintain, state) do
    Enum.each(state.tasks, fn {_ref, {grant, _id}} ->
      Coordinator.renew(state.coordinator, grant.token)
    end)

    Process.send_after(self(), :maintain, state.interval)
    {:noreply, flush_reports(state)}
  end

  def handle_info(_unsupported, state), do: {:noreply, state}

  defp obtain_grant(state, id, execution_id) do
    c = state.coordinator

    with {:ok, facts} <- Coordinator.read(c, id),
         execution when not is_nil(execution) <- facts.intent.executions[execution_id],
         :ok <- preflight(state, facts.intent, execution),
         {:ok, token} <- obtain_token(state, id, execution),
         {:ok, commit} <- Coordinator.authorize(c, token, state.environment) do
      Coordinator.grant(commit)
    else
      nil -> {:error, :execution_not_found}
      error -> error
    end
  end

  defp preflight(state, intent, %{authorization: nil} = execution) do
    with {:ok, _binding} <-
           Registry.bind(state.coordinator.handlers, intent, execution, state.environment),
         do: :ok
  end

  defp preflight(_state, _intent, _execution), do: :ok

  defp obtain_token(state, id, %{authorization: nil} = execution) do
    lease = execution.lease

    replay =
      lease && not lease.invalidated && lease.token.worker == state.id &&
        lease.token.incarnation == state.incarnation

    generation = Lease.generation(lease) - if(replay, do: 1, else: 0)

    case Coordinator.claim(
           state.coordinator,
           id,
           execution.id,
           state.id,
           state.incarnation,
           generation
         ) do
      {:ok, %Commit{reply: {:claimed, token}}} -> {:ok, token}
      error -> error
    end
  end

  defp obtain_token(state, _id, %{authorization: token}) do
    if token.worker == state.id and token.incarnation == state.incarnation,
      do: {:ok, token},
      else: {:error, :foreign_incarnation}
  end

  defp deliver_grant(state, grant) do
    token = grant.token
    key = {token.collection, token.intent_id, token.execution_id}

    cond do
      token.worker != state.id or token.incarnation != state.incarnation ->
        {:reply, {:error, :foreign_incarnation}, state}

      token.collection != state.coordinator.collection or token.intent_id != grant.intent.id or
          token.collection != grant.intent.identity.collection ->
        {:reply, {:error, :grant_scope_mismatch}, state}

      MapSet.member?(state.started, key) ->
        {:reply, :already_started, state}

      MapSet.size(state.started) >= state.capacity ->
        {:reply, {:error, :session_capacity_exhausted}, state}

      true ->
        start_invocation(state, grant, key)
    end
  end

  defp start_invocation(state, grant, key) do
    with execution when not is_nil(execution) <- grant.intent.executions[grant.token.execution_id],
         true <- execution.binding === grant.binding,
         {:ok, _handler} <-
           Registry.validate_invocation(
             state.coordinator.handlers,
             grant.intent,
             grant.binding,
             state.environment
           ),
         :ok <-
           Domain.check_invocation(
             grant.intent,
             grant.token,
             Coordinator.invocation_context(state.coordinator)
           ) do
      started = MapSet.put(state.started, key)

      task =
        Task.Supervisor.async_nolink(BeamletRuntime.Tasks, fn ->
          invoke(state.coordinator, state.environment, grant)
        end)

      updated = %{
        state
        | started: started,
          tasks: Map.put(state.tasks, task.ref, {grant, Ecto.UUID.generate()})
      }

      {:reply, :started, updated}
    else
      nil -> {:reply, {:error, :execution_not_found}, state}
      false -> {:reply, {:error, :grant_binding_mismatch}, state}
      error -> {:reply, error, state}
    end
  end

  defp invoke(coordinator, environment, grant) do
    with {:ok, {module, config}} <-
           Registry.validate_invocation(
             coordinator.handlers,
             grant.intent,
             grant.binding,
             environment
           ),
         :ok <-
           Domain.check_invocation(
             grant.intent,
             grant.token,
             Coordinator.invocation_context(coordinator)
           ) do
      module.invoke(grant, config)
    else
      {:error, reason} -> {:uncertain, reason}
    end
  rescue
    _error -> {:uncertain, :handler_exception}
  catch
    _kind, _reason -> {:uncertain, :handler_exception}
  end

  defp result_report(state, grant, id, {kind, body})
       when kind in [:success, :failure, :pending] do
    report = %Report{
      id: id,
      token: grant.token,
      operation: grant.intent.definition.operation,
      kind: kind,
      body: body
    }

    with :ok <- Report.validate(report),
         :ok <- Registry.validate_report(state.coordinator.handlers, grant.intent, report) do
      %{state | reports: Map.put(state.reports, id, report)}
    else
      _error -> state
    end
  end

  defp result_report(state, _grant, _id, _uncertain), do: state

  defp flush_reports(state) do
    remaining =
      Enum.reject(state.reports, fn {_id, report} ->
        match?({:ok, %Commit{}}, Coordinator.worker_report(state.coordinator, report))
      end)

    %{state | reports: Map.new(remaining)}
  end
end
