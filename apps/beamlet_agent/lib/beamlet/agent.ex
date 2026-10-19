defmodule Beamlet.Agent do
  @typedoc """
  实例本地引用或持久化 UUID；尚无当前 turn 时为 nil。

  Turn tokens are incarnation-local references or persisted UUIDs.
  """
  @type turn :: reference() | binary() | nil
  @typedoc """
  保留存储/适配器及结构化 blocked 原因的错误，不据此自动重试。

  Errors preserve storage and adapter reasons, including structured blocked reasons.
  """
  @type error :: {:error, term()}
  @typedoc "返回值或明确错误的统一封装。"
  @type result(value) :: {:ok, value} | error()
  @typedoc """
  具体命令选择返回形状；raw command 保留开放响应边界。

  Open command reply: each command selects its own result, while raw command/2 remains an extension boundary.
  """
  @type command_result :: :ok | result(term())
  @typedoc """
  持久化 Repo/Agent ID 定位符，可附显式实时模型、工具和 Runtime 接线；读取本身不授权执行。

  A durable locator may additionally carry trusted live model, Tool and runtime configuration.
  """
  @type locator :: %{
          required(:repo) => module(),
          required(:agent_id) => binary(),
          optional(:model) => Beamlet.Agent.ModelBinding.t(),
          optional(:tools) => %{optional(binary()) => Beamlet.Agent.Integration.Caller.profile()},
          optional(:catalogue) => Beamlet.Harness.Catalogue.t(),
          optional(:runtime) => Beamlet.Agent.Durable.runtime(),
          optional(:source) => %{environment: :confirmed_stopped | :unconfirmed},
          optional(:environment) => term()
        }
  @typedoc "七字段实时替换快照；turn 与 terminal_turn 分别关联当前和结束轮次。"
  @type snapshot :: %{
          ref: Beamlet.Agent.Ref.t(),
          turn: turn(),
          terminal_turn: turn(),
          status: :idle | :running | :waiting | :paused | :done | :error | :stopped,
          steps: non_neg_integer(),
          final: term(),
          progress: term()
        }
  @typedoc "显式 authority、独立 options 和 input 的委派子项，不继承父绑定。"
  @type child_specification :: %{
          required(:authority) => node(),
          required(:options) => keyword(),
          required(:input) => binary(),
          optional(:launcher) => pid()
        }
  @spec start(node(), term()) :: result(Beamlet.Agent.Ref.t())
  @spec start_local(term()) :: result(Beamlet.Agent.Ref.t())
  @spec remote_start(node(), term()) :: result(Beamlet.Agent.Ref.t())
  @spec list(term()) :: result([Beamlet.Agent.Discovery.descriptor()])
  @spec lookup(term(), term()) :: result(Beamlet.Agent.Ref.t())
  @spec lookup(term()) :: result(Beamlet.Agent.Ref.t())
  @spec close(Beamlet.Agent.Ref.t()) :: :ok | error()
  @spec input(Beamlet.Agent.Ref.t(), term()) :: result(turn())
  @spec input(Beamlet.Agent.Ref.t(), term(), term()) :: result(turn())
  @spec delegate(Beamlet.Agent.Ref.t(), term(), keyword()) :: result(reference())
  @spec peer_request(Beamlet.Agent.Ref.t(), Beamlet.Agent.Ref.t(), term(), term()) ::
          result(reference())
  @spec peer_reply(Beamlet.Agent.Ref.t(), reference(), term()) :: :ok | error()
  @spec peer_take(Beamlet.Agent.Ref.t(), reference()) :: result(term())
  @spec inbox(Beamlet.Agent.Ref.t()) :: result(%{optional(reference()) => term()})
  @spec snapshot(Beamlet.Agent.Ref.t()) :: result(snapshot())
  @spec snapshot(Beamlet.Agent.Ref.t(), term()) :: result(Beamlet.Agent.Display.snapshot())
  @spec stop_turn(Beamlet.Agent.Ref.t()) :: :ok | error()
  @spec subscribe(Beamlet.Agent.Ref.t(), term()) :: :ok | error()
  @spec subscribe(Beamlet.Agent.Ref.t(), term(), term()) :: :ok | error()
  @spec unsubscribe(Beamlet.Agent.Ref.t(), term()) :: :ok | error()
  @spec ack(Beamlet.Agent.Ref.t(), term()) :: :ok | error()
  @spec restore(term(), term(), term()) :: result(Beamlet.Agent.Ref.t())
  @spec inactive(term()) :: :ok | {:error, :already_active}
  @spec start_restored(locator(), Beamlet.Agent.Durable.restored()) ::
          result(Beamlet.Agent.Ref.t())
  @spec fork(locator(), term(), term(), term()) :: result(Beamlet.Agent.Durable.forked())
  @spec history(term(), term(), term()) :: result(Beamlet.Agent.Core.Data.object())
  @spec export(map(), term(), term()) :: result(Beamlet.Agent.Core.Data.object())
  @spec continue(Beamlet.Agent.Ref.t(), term(), term(), term()) :: result(snapshot())
  @spec command(Beamlet.Agent.Ref.t(), term()) :: command_result()
  @moduledoc """
  显式 authority 上的有界异步 Agent。AuthoritySupervisor 提供身份与资源监督；模型绑定在实例生命周期内固定，工具通过 Runtime 执行。每实例一次活动 turn，最多 16 个模型步骤、8 个并行工具；完整回复和兄弟批次在发送前验证。不重试不确定执行；持久化恢复只激活为暂停状态，必须显式 continue。

  Explicit authority, bounded asynchronous Agents and opt-in paused durable recovery.
  """
  alias Beamlet.Agent.Durable
  alias Beamlet.Agent.History
  alias Beamlet.Agent.Ref
  alias Beamlet.Agent.Server
  alias Beamlet.Agent.Storage.AgentRecords
  alias Beamlet.Agent.TraceExport

  @doc "在显式 authority 创建临时实例；opts 必须含唯一 id 与有效固定 model 绑定，失败返回错误，不自动选替代 authority。"
  def start(authority, opts) when is_atom(authority) do
    if authority == node(), do: start_local(opts), else: remote_start(authority, opts)
  end

  @doc "在已启动的本地 AuthoritySupervisor 下创建实例并取得真实 Ref。"
  def start_local(opts) do
    case DynamicSupervisor.start_child(Beamlet.Agent.Agents, {Server, opts}) do
      {:ok, pid} -> GenServer.call(pid, :ref)
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, _ -> {:error, :authority_unavailable}
  end

  defp remote_start(authority, opts) do
    :erpc.call(authority, __MODULE__, :start_local, [opts], 5000)
  catch
    _, _ -> {:error, :authority_unavailable}
  end

  @doc """
  有限读取 authority 的安全身份描述符，最多等待 5 秒；不查询历史或执行。

  Safe observed authority-local identity descriptors; bounded to five seconds.
  """
  defdelegate list(authority), to: Beamlet.Agent.Discovery

  @doc """
  取得当前实例的真实 Ref；描述符形式额外拒绝替换 PID（stale_agent）。

  Obtain the present Server Ref explicitly by authority and ID.
  """
  defdelegate lookup(authority, id), to: Beamlet.Agent.Discovery

  @doc """
  取得当前实例的真实 Ref；描述符形式额外拒绝替换 PID（stale_agent）。

  Attach a listed descriptor, rejecting replacement PID with stale_agent.
  """
  defdelegate lookup(descriptor), to: Beamlet.Agent.Discovery

  @doc "关闭实例并请求清理所属工作；不删除持久化事实，也不证明外部副作用停止。"
  def close(ref), do: command(ref, :close)
  @doc "提交最多 65536 字节 UTF-8 输入；活动 turn 返回 busy，输入或上下文超限拒绝。持久化 command_id 相同则读取原响应，参数变化冲突。"
  def input(ref, text), do: command(ref, {:input, text})

  @doc """
  提交最多 65536 字节 UTF-8 输入；活动 turn 返回 busy，输入或上下文超限拒绝。持久化 command_id 相同则读取原响应，参数变化冲突。

  Durable input: the command identity makes a repeated submission replay instead of re-dispatch.
  """
  def input(ref, text, command_id), do: command(ref, {:input, text, command_id})
  @doc "启动 1..8 个显式 authority/options/input 子项；默认按原顺序汇总，continue: true 将结果加入上下文后继续模型。子项不继承父凭证。"
  def delegate(ref, children, opts \\ []), do: command(ref, {:delegate, children, opts})

  @doc "发送有界 mailbox 请求，返回关联 ID；TTL 为 1..60000ms，pending 与 inbox 合计最多 16，完整信封最多 8192 字节，不隐式触发输入或工具。"
  def peer_request(ref, target, payload, ttl \\ 30_000),
    do: command(ref, {:peer_request, target, payload, ttl})

  @doc "回复当前 turn 的 inbox 请求；过期/旧 turn 返回 stale_peer_request，超限返回 message_limit。"
  def peer_reply(ref, id, payload), do: command(ref, {:peer_reply, id, payload})
  @doc "取出并移除指定 inbox 项，缺失返回 {:ok, nil}。"
  def peer_take(ref, id), do: command(ref, {:peer_take, id})
  @doc "读取当前有界 mailbox，不执行其中内容。"
  def inbox(ref), do: command(ref, :inbox)
  @doc "读取当前替换快照；view: :display 额外提供有界展示投影，不是事件历史。"
  def snapshot(ref), do: command(ref, :snapshot)

  @doc """
  读取当前替换快照；view: :display 额外提供有界展示投影，不是事件历史。

  Read a bounded replacement display of live context; see Beamlet.Agent.Display.
  """
  def snapshot(ref, opts), do: command(ref, {:snapshot, opts})
  @doc "冻结当前 turn 并请求所属工作清理；返回 :ok 不证明远端终止，持久化活动 turn 记录中断后暂停。"
  def stop_turn(ref), do: command(ref, :stop)
  @doc "订阅初始快照及替换更新；最多 32 sink，各 16 未确认序号，慢消费者合并更新。ack 必须由 sink 自身调用。"
  def subscribe(ref, sink \\ self()), do: command(ref, {:subscribe, sink})

  @doc """
  订阅初始快照及替换更新；最多 32 sink，各 16 未确认序号，慢消费者合并更新。ack 必须由 sink 自身调用。

  Subscribe to replacement display snapshots using the existing sink-owned ack/2 credits.
  """
  def subscribe(ref, sink, opts), do: command(ref, {:subscribe, sink, opts})

  @doc "删除 sink 订阅；不停止 Agent。"
  def unsubscribe(ref, sink \\ self()), do: command(ref, {:unsubscribe, sink})
  @doc "由订阅 sink 确认序号释放额度；无订阅返回 not_subscribed。"
  def ack(ref, sequence), do: command(ref, {:ack, self(), sequence})

  @doc """
  读取并激活为暂停实例，不调用模型/工具；需有效实时绑定，已注册身份拒绝 already_active。

  Loads a paused instance from a durable locator (`%{repo:, agent_id:, model:,
  tools:, catalogue:, environment:, runtime:}`) plus `expected_version` and
  `command_id`; `runtime` is the optional live model/Tool dispatch wiring.
  Performs storage reads/activation, but no model or Tool invocation. Starting the
  live Server requires a valid model binding; missing live configuration rejects
  startup while the durable activation remains paused. For dependency-free,
  read-only reconstruction use `Beamlet.Agent.Durable.inspect/1`. An id that is
  still live returns `{:error, :already_active}` before activation. Old inventoried
  senders must be DOWN before a new generation is activated.
  """
  def restore(locator, expected_version, command_id) do
    with :ok <- inactive(locator),
         {:ok, restored} <- Durable.restore(locator, expected_version, command_id) do
      start_restored(locator, restored)
    end
  end

  defp inactive(%{repo: repo, agent_id: agent_id}) do
    case AgentRecords.fetch(repo, agent_id) do
      {:ok, %{"agent" => %{"alias" => alias_name} = agent}} ->
        if Registry.lookup(Beamlet.Agent.Registry, alias_name || agent["id"]) == [],
          do: :ok,
          else: {:error, :already_active}

      # An unknown Agent is the restore transaction's error to report.
      _ ->
        :ok
    end
  end

  defp inactive(_), do: :ok

  defp start_restored(locator, restored) do
    opts = [
      id: restored.alias || restored.durable.agent_id,
      model: locator[:model],
      tools: Map.get(locator, :tools, %{}),
      catalogue: Map.get(locator, :catalogue, %{}),
      durable: restored.durable,
      restored: %{control: restored.control, durable: restored.durable}
    ]

    case start_local(opts) do
      {:ok, ref} -> {:ok, ref}
      {:error, {:already_started, _pid}} -> {:error, :already_active}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  在安全已提交位置建立同 authority 的暂停引用分叉，不复制执行；默认环境风险未确认。

  Same-authority reference fork at a safe committed sequence; returns a paused locator.
  """
  def fork(locator, through_seq, expected_version, command_id),
    do: Durable.fork(locator, through_seq, expected_version, command_id)

  @doc """
  只读固定截止位历史；facts/turns 游标应原样传回，evidence 独立于 Agent seq。

  Read-only durable facts, context, operations and provenance without a live Agent.
  """
  def history(locator, filters \\ %{}, cursor \\ nil),
    do: History.query(locator, filters, cursor)

  @doc """
  捕获固定高水位并写 format2 轨迹到空目录；输出是敏感内容，缺失/脱敏不算完整，不授予执行权。

  Bounded trace export of one committed scope: fixes a high-water mark first, then
  streams a versioned manifest, JSONL events/inputs/operations/definition and referenced artifacts
  into `policy.dir`. Read-only; the package never grants import/execution.
  """
  def export(locator, scope, policy) when is_map(locator) do
    TraceExport.export(locator[:repo], scope || locator, policy)
  end

  @doc """
  显式继续暂停实例，校验版本并记录决策；不确定结果需逐项 resolution，claimed unresolved 不授权再次发送。

  Explicitly continues a paused durable instance: validates the expected version,
  records the decision and advances the stored continuation. Uncertain external
  effects stay blocked until `decisions` names the pending accepted Operation with
  `%{"operation_id" => id, "resolution" => "confirmed_failed" | "confirmed_executed"}`.
  Multiple uncertain siblings require `%{"resolutions" => [decision, ...]}`.
  Neither form authorizes dispatch of a claimed unresolved attempt.
  """
  def continue(ref, expected_version, decisions, command_id),
    do: command(ref, {:continue, expected_version, decisions, command_id})

  @doc "使用 Ref incarnation 关联的有限 5 秒命令调用；失联返回 unavailable，超时不证明副作用未发生。"
  def command(%Ref{} = ref, command) do
    GenServer.call(ref.pid, {ref.incarnation, command}, 5000)
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
