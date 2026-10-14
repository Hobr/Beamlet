defmodule BeamletRuntime.Scheduler do
  @moduledoc """
  Bounded periodic scans of durable candidates. Notifications are unnecessary for
  recovery. Cursor wraps to revisit changed work; workers and scans may overlap.
  Discovery is advisory: every change is guarded by an atomic Storage command.
  """
  use GenServer
  alias BeamletRuntime.{Coordinator, Worker}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  def tick(server), do: GenServer.call(server, :tick)

  def scan_once(coordinator, workers, cursor \\ "", limit \\ 100) do
    with {:ok, candidates} <- Coordinator.discover(coordinator, cursor, limit) do
      results =
        Enum.map(candidates, fn candidate ->
          {candidate.intent_id,
           safely(fn -> process_candidate(coordinator, workers, candidate.intent_id) end)}
        end)

      next = if length(candidates) == limit, do: List.last(candidates).intent_id, else: ""
      {:ok, %{cursor: next, results: results}}
    end
  end

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
    interval = Keyword.get(opts, :interval, 1_000)
    limit = Keyword.get(opts, :limit, 100)

    unless is_integer(interval) and interval > 0 and is_integer(limit) and limit in 1..1000,
      do: raise(ArgumentError, "invalid Scheduler interval or page size")

    state = %{
      coordinator: Keyword.fetch!(opts, :coordinator),
      workers: Keyword.fetch!(opts, :workers),
      interval: interval,
      limit: limit,
      cursor: "",
      task: nil
    }

    send(self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_call(:tick, _from, %{task: nil} = state), do: {:reply, :scheduled, start_scan(state)}
  def handle_call(:tick, _from, state), do: {:reply, :busy, state}
  def handle_call(_unsupported, _from, state), do: {:reply, {:error, :unsupported_request}, state}

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.interval)
    {:noreply, if(state.task, do: state, else: start_scan(state))}
  end

  def handle_info({ref, result}, %{task: ref} = state) do
    Process.demonitor(ref, [:flush])

    cursor =
      case result do
        {:ok, page} -> page.cursor
        _error -> state.cursor
      end

    {:noreply, %{state | task: nil, cursor: cursor}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: ref} = state),
    do: {:noreply, %{state | task: nil}}

  def handle_info(_unsupported, state), do: {:noreply, state}

  defp start_scan(state) do
    task =
      Task.Supervisor.async_nolink(BeamletRuntime.Tasks, fn ->
        scan_once(state.coordinator, state.workers, state.cursor, state.limit)
      end)

    %{state | task: task.ref}
  end

  defp process_candidate(c, workers, id) do
    Coordinator.recover(c, id)

    with {:ok, facts} <- Coordinator.read(c, id) do
      Enum.each(facts.intent.executions, fn {execution_id, execution} ->
        query_execution(c, id, execution_id, execution)
      end)

      Coordinator.recover(c, id)
      dispatch(c, workers, id)
    end
  end

  defp dispatch(c, workers, id) do
    with {:ok, commit} <- Coordinator.prepare(c, id) do
      dispatch_intent(workers, commit.facts.intent)
    end
  end

  defp query_execution(c, id, execution_id, execution) do
    if execution.phase in [:unknown, :waiting] and is_map(execution.binding) and
         is_map(execution.binding["query"]),
       do: Coordinator.query(c, id, execution_id)
  end

  defp dispatch_intent(workers, intent) do
    execution = intent.executions[intent.current_execution_id]

    if (intent.phase == :open and execution) && execution.phase in [:prepared, :start_authorized],
      do: dispatch_workers(workers, intent.id, execution.id),
      else: :no_dispatch
  end

  defp dispatch_workers(workers, id, execution_id) do
    Enum.reduce_while(workers, {:error, :no_available_worker}, fn worker, _previous ->
      dispatch_result(safely(fn -> Worker.run(worker, id, execution_id) end))
    end)
  end

  defp dispatch_result(result) when result in [:started, :already_started], do: {:halt, result}
  defp dispatch_result(error), do: {:cont, error}

  defp safely(fun) do
    fun.()
  rescue
    _error -> {:error, :runtime_unavailable}
  catch
    :exit, _reason -> {:error, :runtime_unavailable}
  end
end
