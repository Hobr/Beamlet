defmodule Beamlet.Agent.Reducer do
  @typep state :: Beamlet.Agent.Core.Reducer.state()
  @spec version() :: pos_integer()
  @spec new(identity) :: %{optional(binary()) => identity | Beamlet.Agent.Core.Data.value()}
        when identity: var
  @spec decisions(value) :: [value | Beamlet.Agent.Core.Data.value()] when value: var
  @spec reduce(state(), term()) :: {:ok, state()} | Beamlet.Agent.Core.Reducer.error()
  @spec replay(state(), [term()]) :: {:ok, state()} | Beamlet.Agent.Core.Reducer.error()
  @spec decode(term()) :: :ok | Beamlet.Agent.Core.Reducer.error()
  @spec validate_payload(binary(), term()) :: :ok | {:error, atom()}
  @spec normalize(Beamlet.Agent.Core.Data.object()) :: Beamlet.Agent.Core.Data.object()
  @moduledoc """
  持久化事件信封到纯 Core 的适配层。先验证版本、标识与控制载荷，再传递标准化事件；不执行模型或工具，也不写入存储。

  Storage envelope adapter for the pure Agent reducer.
  """
  alias Beamlet.Agent.Core.Reducer, as: Core
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.Events
  @doc "返回支持的纯 reducer 版本。"
  defdelegate version(), to: Core
  @doc "建立空控制状态，尚未包含创建事件。"
  defdelegate new(id), to: Core
  @doc "提取单项或批量执行决策。"
  defdelegate decisions(payload), to: Core

  @doc "先校验事件信封，再应用一次纯归约。"
  def reduce(state, event) do
    with :ok <- decode(event), do: Core.reduce(state, normalize(event))
  end

  @doc "按序归约已提交事件，首个错误立即停止。"
  def replay(state, events) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, current} ->
      case reduce(current, event) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  @doc "验证存储信封与 Core 事件语义；不支持版本返回 schema_unsupported，损坏返回 invalid_history。"
  def decode(%{"schema_version" => 1, "type" => type, "payload" => payload} = event) do
    with true <- is_map(payload) and type in Events.agent_types(),
         true <- is_integer(event["seq"]) and event["seq"] > 0,
         true <- Codec.uuid?(event["id"]) and Codec.uuid?(event["scope_id"]),
         {:ok, _} <- Codec.encode(payload, :event) do
      with :ok <- validate_payload(type, payload),
           true <- event["operation_id"] == payload["operation_id"] do
        Core.decode(normalize(event))
      else
        _ -> {:error, :invalid_history}
      end
    else
      _ -> {:error, :invalid_history}
    end
  end

  def decode(%{"schema_version" => _}), do: {:error, :schema_unsupported}
  def decode(_), do: {:error, :invalid_history}

  defp validate_payload("input.accepted", _), do: :ok
  defp validate_payload(_, payload), do: Events.control(payload)

  defp normalize(%{"type" => "input.accepted", "payload" => payload} = event) do
    {:ok, digest} = Codec.digest(payload, :event)
    Map.put(event, "input_digest", digest)
  end

  defp normalize(event), do: event
end
