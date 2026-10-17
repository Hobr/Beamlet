defmodule Beamlet.Web.WorkbenchCommands do
  @moduledoc false
  alias Beamlet.Node.Cluster
  alias Beamlet.Web.{Agents, Handles, OwnedCall, Presets}

  def discover do
    allowed = Application.get_env(:beamlet_web, :host, []) |> Keyword.get(:allowed_nodes, [])
    {:ok, connected} = Cluster.connected(allowed)
    {:ok, remote} = Agents.discover(Enum.reject(connected, &(&1 == node())))

    case Beamlet.Agent.list(node()) do
      {:ok, local} ->
        %{remote | agents: local ++ remote.agents}

      {:error, :not_authority} ->
        remote

      {:error, reason} ->
        %{remote | complete: false, failures: Map.put(remote.failures, node(), reason)}
    end
    |> then(&{:ok, &1})
  end

  defp resolve(draft) do
    Presets.resolve(draft)
  catch
    :exit, _ -> :configuration_unavailable
  end

  def create(owner, tag, draft) do
    case resolve(draft) do
      {:ok, resolved} ->
        authority =
          if resolved.authority == :local,
            do: node(),
            else: String.to_existing_atom(resolved.authority)

        id = "web-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
        OwnedCall.deliver(owner, {:creation, tag, {:identity, authority, id}})

        case Beamlet.Agent.start(authority, Keyword.put(resolved.options, :id, id)) do
          {:ok, ref} ->
            OwnedCall.deliver(owner, {:creation, tag, {:confirmed, ref}})
            OwnedCall.deliver(owner, {:creation, tag, :input_pending})
            input = Agents.input(ref, resolved.task)
            OwnedCall.deliver(owner, {:creation, tag, {:input, input}})
            {:navigation, Handles.remember(%{authority: ref.authority, id: ref.id, pid: ref.pid})}

          _ ->
            :create_unknown
        end

      :configuration_unavailable ->
        :configuration_unavailable

      _ ->
        :invalid_draft
    end
  end
end
