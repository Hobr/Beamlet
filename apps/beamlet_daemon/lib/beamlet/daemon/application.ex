defmodule Beamlet.Daemon.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    case Beamlet.Daemon.configuration(Application.get_all_env(:beamlet_daemon)) do
      {:ok, settings} ->
        children =
          if settings[:enabled] do
            [{Beamlet.Node, settings[:node]}] ++
              storage(settings[:storage]) ++
              [
                {Beamlet.Daemon.Bootstrap,
                 peers: settings[:peers], allowed_nodes: settings[:allowed_nodes]}
              ]
          else
            []
          end

        Supervisor.start_link(children, strategy: :one_for_one, name: Beamlet.Daemon.Supervisor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The storage host opens the configured datasets and starts durable admission
  # after the roles exist. It is absent unless the operator configured storage.
  defp storage(nil), do: []
  defp storage(settings), do: [{Beamlet.Storage.Host, storage: settings}]
end
