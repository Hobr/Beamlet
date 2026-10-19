defmodule Beamlet.Server.Application do
  @moduledoc false
  use Application

  @impl true
  @spec start(Application.start_type(), term()) :: Supervisor.on_start()
  def start(_type, _args) do
    case Beamlet.Server.configuration(Application.get_all_env(:beamlet_app_server)) do
      {:ok, settings} ->
        children =
          if settings[:enabled] do
            [{Beamlet.Node, settings[:node]}] ++
              storage(settings[:storage]) ++
              [
                {Beamlet.Server.Bootstrap,
                 peers: settings[:peers], allowed_nodes: settings[:allowed_nodes]}
              ]
          else
            []
          end

        Supervisor.start_link(children, strategy: :one_for_one, name: Beamlet.Server.Supervisor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The storage host opens the configured datasets and starts durable admission
  # after the roles exist. It is absent unless the operator configured storage.
  @spec storage(Beamlet.Node.Storage.configuration() | nil) :: [{module(), keyword()}]
  defp storage(nil), do: []
  defp storage(settings), do: [{Beamlet.Node.Storage, storage: settings}]
end
