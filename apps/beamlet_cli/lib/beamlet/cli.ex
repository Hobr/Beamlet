defmodule Beamlet.CLI do
  @moduledoc "Opt-in interaction host. No stdin or Node startup on ordinary loading."
  alias Beamlet.Node.Cluster

  @typedoc "Validated opt-in interaction host settings."
  @type settings :: [{:enabled, boolean()} | {:allowed_nodes, [binary()]}]
  @spec configuration(term()) :: {:ok, settings()} | {:error, :invalid_configuration}
  def configuration(settings) do
    with true <- is_list(settings) and Keyword.keyword?(settings),
         keys = Keyword.keys(settings),
         true <- keys -- [:enabled, :allowed_nodes] == [] and keys == Enum.uniq(keys),
         enabled = Keyword.get(settings, :enabled, false),
         true <- is_boolean(enabled),
         allowed = Keyword.get(settings, :allowed_nodes, []),
         {:ok, _} <- Cluster.connected(allowed) do
      {:ok, [enabled: enabled, allowed_nodes: allowed]}
    else
      _ -> {:error, :invalid_configuration}
    end
  end
end
