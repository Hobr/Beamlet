defmodule Beamlet.CLI.Client do
  @moduledoc """
  基于真实 Agent Ref 的 IEx/发布客户端。创建与输入只尝试一次；watch 在订阅进程中消费并确认快照，超时不取消业务工作。

  Small IEx/release client over live Agent refs. Watch runs in the subscriber
  process, acknowledges consumed snapshots and never retries business work.
  """
  alias Beamlet.Agent
  alias Beamlet.CLI.Renderer

  @typep output :: (binary() -> term())
  @typep watch_result :: Agent.result(Agent.snapshot())
  @doc "在受信 authority 尝试创建一次实例并返回真实 Ref 或后端错误；不自动重试或选择替代 authority。"
  @spec create(node(), term()) :: Agent.result(Agent.Ref.t())
  def create(authority, options), do: Agent.start(authority, options)
  @doc "向精确 Ref 提交一轮文本，保留后端的忙碌、无效输入及不可用结果；不自动排队或重试。"
  @spec input(Agent.Ref.t(), term()) :: Agent.result(Agent.turn())
  def input(ref, text), do: Agent.input(ref, text)
  @doc "读取当前基础快照；不提供完整历史或令牌流。"
  @spec snapshot(Agent.Ref.t()) :: Agent.result(Agent.snapshot())
  def snapshot(ref), do: Agent.snapshot(ref)
  @doc "读取当前基础快照，与 snapshot 使用相同后端读取。"
  @spec status(Agent.Ref.t()) :: Agent.result(Agent.snapshot())
  def status(ref), do: Agent.snapshot(ref)
  @doc "请求停止当前轮次并保留实例；不承诺撤回外部副作用。"
  @spec stop(Agent.Ref.t()) :: :ok | Agent.error()
  def stop(ref), do: Agent.stop_turn(ref)
  @doc "显式关闭精确 Ref 指向的实例；关闭与停止轮次是不同操作。"
  @spec close(Agent.Ref.t()) :: :ok | Agent.error()
  def close(ref), do: Agent.close(ref)

  @doc """
  在当前订阅进程中显示并确认快照；timeout 默认 5000ms、范围 1..60000，events 默认 64、范围 1..256，output 默认 Owl.IO.puts/1。终态返回快照，超时或条数耗尽返回错误并退订，不停止 Agent。

  Watch up to 256 snapshots for at most 60 seconds; timeout never cancels work.
  """
  @spec watch(Agent.Ref.t(), term()) :: watch_result()
  def watch(ref, opts \\ [])

  def watch(ref, opts) when is_list(opts) do
    if Keyword.keyword?(opts) and
         Enum.all?(Keyword.keys(opts), &(&1 in [:timeout, :events, :output])) do
      do_watch(ref, opts)
    else
      {:error, :invalid_watch_options}
    end
  end

  def watch(_, _), do: {:error, :invalid_watch_options}

  @spec do_watch(Agent.Ref.t(), keyword()) :: watch_result()
  defp do_watch(ref, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)
    events = Keyword.get(opts, :events, 64)

    if is_integer(timeout) and timeout in 1..60_000 and is_integer(events) and
         events in 1..256 and is_function(Keyword.get(opts, :output, &Owl.IO.puts/1), 1) do
      with :ok <- Agent.subscribe(ref) do
        try do
          watch_events(
            ref,
            System.monotonic_time(:millisecond) + timeout,
            events,
            Keyword.get(opts, :output, &Owl.IO.puts/1)
          )
        after
          Agent.unsubscribe(ref)
        end
      end
    else
      {:error, :invalid_watch_options}
    end
  end

  @spec watch_events(Agent.Ref.t(), integer(), non_neg_integer(), output()) :: watch_result()
  defp watch_events(_ref, _deadline, 0, _output), do: {:error, :event_limit}

  defp watch_events(ref, deadline, remaining, output) do
    wait = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:beamlet_agent, ^ref, sequence, {:snapshot, snapshot}} ->
        # Same safe domain projection as status; Owl bounds per-event display.
        display = Renderer.render(snapshot)

        output.(
          display
          |> Owl.Data.truncate(4096)
          |> Owl.Data.to_chardata()
          |> IO.chardata_to_string()
          |> String.to_charlist()
          |> Enum.take(4096)
          |> List.to_string()
        )

        case Agent.ack(ref, sequence) do
          :ok ->
            if snapshot.status in [:done, :error, :stopped],
              do: {:ok, snapshot},
              else: watch_events(ref, deadline, remaining - 1, output)

          error ->
            error
        end
    after
      wait -> {:error, :timeout_or_loss}
    end
  end
end
