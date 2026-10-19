defmodule Beamlet.Agent.ContextBuilder do
  @typep object :: Beamlet.Agent.Core.Data.object()
  @typep result(value) :: Beamlet.Agent.result(value)
  @spec complete_boundary(term()) :: :ok | {:error, :unsafe_position}
  @spec observation(term(), term()) :: result(binary())
  @spec reply(term()) :: result(Beamlet.Agent.Core.Context.decoded_reply())
  @spec build(module(), object(), Beamlet.Harness.Catalogue.t()) ::
          result(Beamlet.Agent.Core.Context.built())
  @spec materialize(module(), object()) :: result([Beamlet.Harness.Model.json_object()])
  @spec load(module(), object()) :: result(Beamlet.Agent.Core.Context.accumulator())
  @spec load_next(module(), object(), object(), {:ok, Beamlet.Agent.Core.Context.accumulator()}) ::
          {:cont, {:ok, Beamlet.Agent.Core.Context.accumulator()}}
          | {:halt, Beamlet.Agent.error()}
  @spec material(module(), object(), object()) :: result(object())
  @moduledoc """
  逐个读取、校验来源，再交给纯 Core 增量转换上下文；前缀超限或损坏后不再读取后续来源。未消费的输出不进入上下文。

  Loads and verifies context sources before applying the pure conversation policy.
  """
  alias Beamlet.Agent.Core.Context
  alias Beamlet.Agent.Loader
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.History
  alias Beamlet.Agent.Storage.Inheritance
  alias Beamlet.Agent.Storage.OperationRecords
  @doc "检查消息边界的完整工具调用配对，错误返回 unsafe_position。"
  defdelegate complete_boundary(messages), to: Context
  @doc "将已接受结果和显式决策转换为工具观察文本，未解决不确定结果拒绝。"
  defdelegate observation(result, resolution), to: Context
  @doc "解码已存模型回复，不丢弃未知字段。"
  defdelegate reply(value), to: Context

  @doc "按来源顺序校验并构建原生 request/sources/policy；时间线最多 128 项，最终遵守原生上下文限制。"
  def build(repo, control, catalogue) do
    with true <- length(control["timeline"]) <= 128,
         {:ok, acc} <- load(repo, control) do
      Context.finish(acc, catalogue)
    else
      false -> {:error, :context_limit}
      error -> error
    end
  end

  @doc "只从已选来源构造消息，不调用 provider，不把未消费输出加入上下文。"
  def materialize(repo, control) do
    with {:ok, acc} <- load(repo, control), do: Context.messages(acc)
  end

  defp load(repo, control) do
    with {:ok, acc} <- Context.start(control) do
      Enum.reduce_while(control["timeline"], {:ok, acc}, &load_next(repo, control, &1, &2))
    end
  end

  # 先转换当前来源再读取下一项，保证前缀超限优先于后续缺失/损坏错误。
  defp load_next(repo, control, source, {:ok, current}) do
    with {:ok, entry} <- material(repo, control, source),
         {:ok, next} <- Context.append(current, entry) do
      {:cont, {:ok, next}}
    else
      error -> {:halt, error}
    end
  end

  defp material(repo, _control, %{"type" => "inherited_input"} = ref) do
    with {:ok, payload} <- Inheritance.input(repo, ref),
         do: {:ok, %{"source" => ref, "input" => payload}}
  end

  defp material(repo, _control, %{"type" => "inherited_result"} = ref) do
    with {:ok, %{"operation" => op}} <-
           OperationRecords.fetch(repo, ref["reference"]["operation_id"]),
         :ok <- Inheritance.operation(repo, op, ref["reference"]) do
      {:ok, %{"source" => ref, "operation" => op, "resolution" => ref["resolution"]}}
    end
  end

  defp material(repo, control, %{"type" => "input"} = ref) do
    with {:ok, e} <- History.event(repo, control["agent_id"], ref["seq"]),
         true <- e["id"] == ref["event_id"] and e["type"] == "input.accepted",
         {:ok, digest} <- Codec.digest(e["payload"], :event),
         true <- digest == ref["digest"] do
      {:ok, %{"source" => ref, "input" => e["payload"]}}
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp material(repo, control, %{"type" => "accepted_result", "reference" => ref} = source) do
    with {:ok, %{"operation" => op}} <- Loader.operation(repo, control["agent_id"], ref) do
      {:ok,
       %{"source" => source, "operation" => op, "resolution" => control["resolutions"][op["id"]]}}
    end
  end
end
