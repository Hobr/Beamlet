defmodule Beamlet.Runtime.Worker do
  @moduledoc "MFA wrapper with finite producer credits. Auxiliary callbacks marshal through the wrapper."
  def run(module, payload, credentials, settings, gateway, remaining, limits, cancellation) do
    wrapper = self()
    counters = :atomics.new(4, [])
    started = System.monotonic_time(:millisecond)

    marshal =
      spawn_link(fn ->
        Process.monitor(wrapper)
        Process.monitor(gateway)
        marshal(gateway)
      end)

    context = %{
      settings: settings,
      credentials: credentials,
      remaining_ms: remaining,
      cancelled?: fn -> :atomics.get(cancellation, 1) == 1 end,
      progress: fn value -> progress(wrapper, marshal, counters, started, value, limits) end
    }

    result = module.run(payload, context)
    send(marshal, {:stop, self()})

    receive do
      {:marshaled, ^marshal} -> :ok
    end

    {:worker_result, result,
     %{producer_progress_dropped: max(0, :atomics.get(counters, 1) - :atomics.get(counters, 4))}}
  end

  defp progress(wrapper, gateway, counters, started, value, limits) do
    count = :atomics.add_get(counters, 1, 1)
    elapsed = System.monotonic_time(:millisecond) - started
    rate_allowed = rate?(counters, div(elapsed, 1000), limits.progress_rate, 10)
    credit = :atomics.add_get(counters, 2, 1)

    if count <= limits.progress_count and rate_allowed and
         credit <= limits.progress_credit and
         :erlang.external_size({:progress, wrapper, count, value, counters}) <=
           limits.progress_bytes and
         Beamlet.Actions.bounded?(value, limits.progress_bytes) do
      :atomics.add(counters, 4, 1)
      message = {:progress, wrapper, count, value, counters}

      send(gateway, {:aux_progress, message})

      :ok
    else
      :atomics.sub(counters, 2, 1)
      {:error, :progress_limit}
    end
  end

  defp rate?(_counters, _window, _limit, 0), do: false

  defp rate?(counters, window, limit, retries) do
    old = :atomics.get(counters, 3)
    count = if div(old, 10_000_000) == window, do: rem(old, 10_000_000), else: 0

    if count >= limit do
      false
    else
      case :atomics.compare_exchange(counters, 3, old, window * 10_000_000 + count + 1) do
        :ok -> true
        _ -> rate?(counters, window, limit, retries - 1)
      end
    end
  end

  defp marshal(gateway) do
    receive do
      {:aux_progress, message} ->
        send(gateway, message)
        marshal(gateway)

      {:stop, worker} ->
        send(worker, {:marshaled, self()})

      {:DOWN, _, :process, _, _} ->
        :ok
    end
  end
end
