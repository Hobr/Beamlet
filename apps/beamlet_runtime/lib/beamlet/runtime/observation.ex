defmodule Beamlet.Runtime.Observation do
  @moduledoc false
  @type failure :: {:error, :timeout | :unavailable}
  @spec now() :: integer()
  @spec remaining(integer()) :: non_neg_integer()
  @spec read(GenServer.server(), term(), term()) :: term() | failure()
  @spec isolate((-> value), timeout()) :: value | failure() when value: var
  @spec call(GenServer.server(), term(), timeout()) :: term() | failure()
  def now, do: System.monotonic_time(:millisecond)
  def remaining(deadline), do: max(0, deadline - now())

  # Disposable linked tasks isolate replies and retire on caller loss. A remote
  # entry gets a relative budget on its own VM, even after delayed code loading.
  def read(server, command, budget) when budget in 1..5000 do
    isolate(fn -> call(server, command, budget) end, budget)
  end

  def read(_, _, _), do: {:error, :timeout}

  def isolate(fun, budget) do
    case Enum.to_list(Task.async_stream([fun], & &1.(), timeout: budget, on_timeout: :kill_task)) do
      [{:ok, result}] -> result
      _ -> {:error, :timeout}
    end
  end

  defp call(server, command, budget) do
    GenServer.call(server, command, budget)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _ -> {:error, :unavailable}
  end
end
