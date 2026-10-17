defmodule Beamlet.CLI.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    with {:ok, settings} <- Beamlet.CLI.configuration(Application.get_all_env(:beamlet_cli)) do
      children = if settings[:enabled], do: [{Beamlet.Node, roles: [:interaction]}], else: []
      Supervisor.start_link(children, strategy: :one_for_one, name: Beamlet.CLI.Supervisor)
    end
  end
end
