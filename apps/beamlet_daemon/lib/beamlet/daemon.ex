defmodule Beamlet.Daemon do
  @moduledoc """
  Opt-in daemon host configuration. Roles are selected once at startup, with
  authority and executor enabled by default. One Node tree is supported per VM.
  """
  alias Beamlet.Node.Cluster

  @doc """
  Validate host policy, delegate resource/provider validation to Node, and
  validate the optional durable-storage block for the configured roles.

  `storage:` is absent by default, so the host stays ephemeral and starts no
  database. When present, `Beamlet.Storage.Host` validates it and the host opens
  only the datasets the roles need: `:authority` needs the authority dataset,
  `:executor` needs the executor journal, and neither is started for a role set
  that needs none. `storage:` itself never implies durable admission; admission
  comes from a live probe of the opened dataset.
  """
  def configuration(settings) do
    with true <- keyword?(settings, [:enabled, :node, :allowed_nodes, :peers, :storage]),
         enabled when is_boolean(enabled) <- Keyword.get(settings, :enabled, false),
         node when is_list(node) <- Keyword.get(settings, :node, []),
         true <- Keyword.keyword?(node),
         true <- Enum.uniq(Keyword.keys(node)) == Keyword.keys(node),
         node = Keyword.put_new(node, :roles, [:authority, :executor]),
         true <- roles?(Keyword.fetch!(node, :roles)),
         {:ok, _children} <- Beamlet.Node.configuration(node),
         {:ok, storage} <- storage(Keyword.get(node, :roles), Keyword.get(settings, :storage)),
         allowed = Keyword.get(settings, :allowed_nodes, []),
         {:ok, _connected} <- Cluster.connected(allowed),
         peers = Keyword.get(settings, :peers, []),
         true <- peers?(peers, allowed, 32, []) do
      {:ok,
       [enabled: enabled, node: node, allowed_nodes: allowed, peers: peers, storage: storage]}
    else
      _ -> {:error, :invalid_daemon_configuration}
    end
  end

  defp storage(_roles, nil), do: {:ok, nil}

  # The release runtime config stores the normalized settings; boot re-validates its
  # own environment, so an already-normalized block is checked structurally instead
  # of being re-read as the operator's raw keyword.
  defp storage(_roles, %{adapter: adapter, executor_id: executor_id} = config)
       when adapter in [:sqlite, :postgres] and is_binary(executor_id) do
    if Map.keys(config) -- [:adapter, :executor_id, :authority, :journal] == [],
      do: {:ok, config},
      else: {:error, :invalid_daemon_configuration}
  end

  defp storage(roles, config) do
    case Beamlet.Storage.Host.configuration(roles, config) do
      {:ok, settings} -> {:ok, settings}
      {:error, _reason} -> {:error, :invalid_daemon_configuration}
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
