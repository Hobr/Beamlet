defmodule Beamlet.Harness.Context do
  @moduledoc """
  可选的受信本地进度/取消钩子及有界消息追加策略。钩子异常仍属调用者异常；这里不实现执行超时。

  Bounded conversation policy and optional local neutral hooks.
  """
  defstruct progress: nil, cancelled?: nil

  @typedoc """
  只在本地调用的钩子结构，不属于便携请求。

  Optional trusted local hooks; emit/2 passes through the hook's arbitrary return value.
  """
  @type t :: %__MODULE__{progress: nil | (map() -> any()), cancelled?: nil | (-> boolean())}

  @doc """
  没有钩子时返回 false；只有钩子返回 true 才视为取消。
  """
  @spec cancelled?(t()) :: boolean()
  def cancelled?(%__MODULE__{cancelled?: nil}), do: false
  def cancelled?(%__MODULE__{cancelled?: callback}), do: callback.() == true

  @doc """
  无钩子时直接返回 :ok；有钩子时检查事件为 map 且 JSON 最多 8192 字节，再透传钩子返回值。校验失败为 progress_limit。
  """
  @spec emit(t(), term()) :: term()
  def emit(%__MODULE__{progress: nil}, _), do: :ok

  def emit(%__MODULE__{progress: callback}, event) do
    with true <- is_map(event),
         {:ok, json} <- Jason.encode(event),
         true <- byte_size(json) <= 8192 do
      callback.(event)
    else
      _ -> {:error, :progress_limit}
    end
  end

  @doc """
  追加消息且不驱逐旧记录；整体最多 128 条、JSON 最多 1048576 字节。这里只检查大小，语义配对由 Model 校验，失败为 context_limit。
  """
  @spec append(term(), term()) :: {:ok, list()} | {:error, :context_limit}
  def append(messages, additions) when is_list(messages) and is_list(additions) do
    all = messages ++ additions

    with true <- length(all) <= 128,
         {:ok, json} <- Jason.encode(all),
         true <- byte_size(json) <= 1_048_576 do
      {:ok, all}
    else
      _ -> {:error, :context_limit}
    end
  rescue
    _ -> {:error, :context_limit}
  end

  def append(_, _), do: {:error, :context_limit}
end
