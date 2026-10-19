defmodule Beamlet.Agent.Storage.Events do
  @moduledoc "Agent schema_version=1 的事件词汇与只含控制/引用的检查点策略。control 递归拒绝正文键并检查编码预算；不替代 Core 对事件时序和角色的语义验证。

Version-one event vocabulary and reference-only control payload contract."
  @spec version() :: 1
  @spec agent_types() :: [String.t()]
  @spec supported?(term(), term()) :: boolean()
  @spec control(term()) :: :ok | {:error, :invalid_data | :limit}
  @spec reference_only?(term()) :: boolean()
  alias Beamlet.Agent.Storage.Codec

  @agent ~w(agent.created input.accepted model.request_prepared tool.batch_prepared operation.result_consumed turn.interrupted agent.continue_decided agent.config_changed context.selected agent.forked context.inherited agent.activated)
  @body_keys ~w(messages assistant request reply result output payload content text arguments prompt tools schema)

  @doc "返回当前 Agent 事件信封版本 1。"
  def version, do: 1
  @doc "返回支持的 Agent 事件类型字符串列表，不包含 Operation 事件。"
  def agent_types, do: @agent
  @doc "仅当事件类型及版本均受支持时返回 true。"
  def supported?(type, version), do: version == 1 and type in @agent

  @doc "检查 map 的规范编码预算并递归拒绝正文键；仅验证控制结构，不执行 reducer 时序校验。"
  def control(value) when is_map(value) and not is_struct(value) do
    with {:ok, _} <- Codec.encode(value, :checkpoint) do
      if reference_only?(value), do: :ok, else: {:error, :invalid_data}
    end
  end

  def control(_), do: {:error, :invalid_data}

  defp reference_only?(map) when is_map(map) do
    Enum.all?(map, fn {key, value} -> key not in @body_keys and reference_only?(value) end)
  end

  defp reference_only?(list) when is_list(list), do: Enum.all?(list, &reference_only?/1)
  defp reference_only?(_), do: true
end
