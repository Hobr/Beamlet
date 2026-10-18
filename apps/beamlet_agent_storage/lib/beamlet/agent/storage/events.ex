defmodule Beamlet.Agent.Storage.Events do
  @moduledoc "Version-one event vocabulary and reference-only control payload contract."
  alias Beamlet.Agent.Storage.Codec

  @agent ~w(agent.created input.accepted model.request_prepared tool.batch_prepared operation.result_consumed turn.interrupted agent.continue_decided agent.config_changed context.selected agent.forked context.inherited agent.activated)
  @body_keys ~w(messages assistant request reply result output payload content text arguments prompt tools schema)

  def version, do: 1
  def agent_types, do: @agent
  def supported?(type, version), do: version == 1 and type in @agent

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
