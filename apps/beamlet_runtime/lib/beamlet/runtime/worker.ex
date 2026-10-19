defmodule Beamlet.Runtime.Worker do
  @moduledoc """
  在受监督任务内调用 Handler，独立转发辅助进度并限制生产额度。Handler 自行拥有其额外子进程及外部资源；协作取消标记不证明外部停止。

  MFA wrapper with finite producer credits. Auxiliary callbacks marshal through the wrapper.
  """
  @typedoc """
  Handler 原始返回与生产端进度丢弃计数；Gateway 随后验证业务返回。

  Handler results are validated by the gateway; arbitrary replies must remain representable here.
  """
  @type result :: {:worker_result, term(), %{producer_progress_dropped: non_neg_integer()}}
  @spec run(
          module(),
          term(),
          Beamlet.Actions.json_object(),
          term(),
          pid(),
          non_neg_integer(),
          Beamlet.Runtime.Limits.t(),
          :atomics.atomics_ref()
        ) :: result()
  @spec progress(
          pid(),
          pid(),
          :atomics.atomics_ref(),
          integer(),
          term(),
          Beamlet.Runtime.Limits.t()
        ) :: :ok | {:error, :progress_limit}
  @spec rate?(:atomics.atomics_ref(), non_neg_integer(), pos_integer(), non_neg_integer()) ::
          boolean()
  @spec marshal(pid()) :: :ok | {:marshaled, pid()}
  @doc "调用 Handler 并合并生产端进度丢弃计数；payload、credentials 与本地 settings 分开传递。"
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
