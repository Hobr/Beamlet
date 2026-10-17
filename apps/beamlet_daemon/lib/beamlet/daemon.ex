defmodule Beamlet.Daemon do
  @moduledoc """
  Opt-in daemon host configuration. Roles are selected once at startup, with
  authority and executor enabled by default. One Node tree is supported per VM.
  """
  alias Beamlet.Node.Cluster

  @doc "Validate host policy and delegate resource/provider validation to Node."
  def configuration(settings) do
    with true <- keyword?(settings, [:enabled, :node, :allowed_nodes, :peers]),
         enabled when is_boolean(enabled) <- Keyword.get(settings, :enabled, false),
         node when is_list(node) <- Keyword.get(settings, :node, []),
         true <- Keyword.keyword?(node),
         true <- Enum.uniq(Keyword.keys(node)) == Keyword.keys(node),
         node = Keyword.put_new(node, :roles, [:authority, :executor]),
         true <- roles?(Keyword.fetch!(node, :roles)),
         {:ok, _children} <- Beamlet.Node.configuration(node),
         allowed = Keyword.get(settings, :allowed_nodes, []),
         {:ok, _connected} <- Cluster.connected(allowed),
         peers = Keyword.get(settings, :peers, []),
         true <- peers?(peers, allowed, 32, []) do
      {:ok, [enabled: enabled, node: node, allowed_nodes: allowed, peers: peers]}
    else
      _ -> {:error, :invalid_daemon_configuration}
    end
  end

  defp keyword?(settings, keys) do
    is_list(settings) and Keyword.keyword?(settings) and
      Keyword.keys(settings) -- keys == [] and
      Enum.uniq(Keyword.keys(settings)) == Keyword.keys(settings)
  end

  defp roles?([:authority]), do: true
  defp roles?([:executor]), do: true
  defp roles?([:authority, :executor]), do: true
  defp roles?([:executor, :authority]), do: true
  defp roles?(_), do: false

  defp peers?([], _allowed, _remaining, _seen), do: true

  defp peers?([name | rest], allowed, remaining, seen) when remaining > 0 do
    name in allowed and name not in seen and peers?(rest, allowed, remaining - 1, [name | seen])
  end

  defp peers?(_, _allowed, _remaining, _seen), do: false
end
