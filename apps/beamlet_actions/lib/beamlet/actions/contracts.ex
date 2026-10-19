defmodule Beamlet.Actions.OperationRef do
  @moduledoc """
  协调器的瞬时地址；不能持久化或用于重放。

  Ephemeral coordinator address; never persisted or replayed.
  """
  @enforce_keys [:id, :pid]
  defstruct [:id, :pid]
  @typedoc "操作 ID 与当前协调器 PID 的瞬时引用。"
  @type t :: %__MODULE__{id: binary(), pid: pid()}
end

defmodule Beamlet.Actions.ExecutionHandle do
  @moduledoc """
  准入已确认的工作身份；不能用预准入 attempt_id 替代。

  An admitted worker identity, distinct from the pre-admission attempt.
  """
  @enforce_keys [:id, :gateway, :incarnation]
  defstruct [:id, :gateway, :incarnation]
  @typedoc "工作 ID、网关 PID 与 incarnation 共同标识已准入执行。"
  @type t :: %__MODULE__{id: binary(), gateway: pid(), incarnation: reference()}
end

defmodule Beamlet.Actions.Execution do
  @moduledoc """
  一次尝试的观察状态；准入确认前 handle 为 nil，uncertain 不证明执行已结束。

  One attempt; handle remains nil until admission is observed.
  """
  defstruct [
    :operation_id,
    :attempt_id,
    :endpoint,
    :incarnation,
    :handle,
    state: :awaiting_admission
  ]

  @typedoc "包含等待准入、运行、完成及不确定的尝试状态。"
  @type t :: %__MODULE__{
          operation_id: binary(),
          attempt_id: binary(),
          endpoint: pid(),
          incarnation: reference(),
          handle: Beamlet.Actions.ExecutionHandle.t() | nil,
          state: :awaiting_admission | :running | :completed | :uncertain
        }
end

defmodule Beamlet.Actions.Result do
  @moduledoc """
  单次有界终态观察。uncertain 不证明远端终止，也不授权重试；source 区分协调器与执行侧。

  Single bounded terminal observation. Uncertainty never implies remote termination.
  """
  defstruct [:operation_id, :execution_id, :status, :reason, :value, :source, metadata: %{}]

  @typedoc "终态观察；执行 ID 可为空，但执行侧来源必须提供它。"
  @type t :: %__MODULE__{
          operation_id: binary(),
          execution_id: binary() | nil,
          status: :ok | :error | :cancelled | :deadline | :uncertain,
          reason: term(),
          value: term(),
          source: :coordinator | :execution,
          metadata: map()
        }

  @doc """
  校验操作身份、执行侧必需的 execution_id、状态、来源及普通 map 元数据。普通字段和整个结构均最多 1048576 个 Erlang 序列化字节；返回布尔值。
  """
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = result) do
    identity?(result) and is_map(result.metadata) and not is_struct(result.metadata) and
      result.status in [:ok, :error, :cancelled, :deadline, :uncertain] and
      result.source in [:coordinator, :execution] and
      Beamlet.Actions.bounded?(Map.from_struct(result), 1_048_576) and
      :erlang.external_size(result) <= 1_048_576
  end

  def valid?(_), do: false

  @spec identity?(%__MODULE__{}) :: boolean()
  defp identity?(result) do
    id?(result.operation_id) and
      (is_nil(result.execution_id) or id?(result.execution_id)) and
      (result.source != :execution or id?(result.execution_id))
  end

  @spec id?(term()) :: boolean()
  defp id?(id), do: is_binary(id) and byte_size(id) in 1..128
end

defmodule Beamlet.Actions.Handler do
  @moduledoc """
  执行器本地行为契约，返回成功数据或安全错误原因。settings 与钩子只在本地解析；credentials 默认空对象，不能泄漏到普通输出、进度或诊断。

    Executor-local handler. Return {:ok, data} or {:error, safe_reason}.

  Context contains local `settings`, invocation `credentials` (default `%{}`),
  `remaining_ms`, and `progress`/`cancelled?` callbacks. Credentials are generic
  data and must not be copied into ordinary outputs or diagnostics.
  """
  @typedoc """
  本地设置、专用凭据、剩余预算及进度/取消钩子。进度信用耗尽返回 progress_limit，不能据此推断任务终止。

  Executor-local hooks. Progress reports its own finite-credit rejection; handler payloads and reasons remain open.
  """
  @type context :: %{
          settings: term(),
          credentials: Beamlet.Actions.json_object(),
          remaining_ms: non_neg_integer(),
          progress: (term() -> :ok | {:error, :progress_limit}),
          cancelled?: (-> boolean())
        }
  @doc "执行一次本地处理；检查取消钩子并遵守剩余预算，返回值仍须通过 Result 有界数据校验。"
  @callback run(term(), context()) :: {:ok, term()} | {:error, term()}
end
