defmodule Beamlet.CLI.Application do
  @moduledoc false
  use Application

  # Host settings are validated strictly, so only the host keys are handed to
  # `Beamlet.CLI.configuration/1`. The app environment also carries creation
  # options (`:agent_options`) and the copy locale (`:locale`/`:default_locale`),
  # which are not host settings and must not be read as unknown keys.
  @host_keys [:enabled, :allowed_nodes]

  @impl true
  def start(_type, _args) do
    with {:ok, settings} <-
           Beamlet.CLI.configuration(
             Keyword.take(Application.get_all_env(:beamlet_cli), @host_keys)
           ) do
      children = if settings[:enabled], do: [{Beamlet.Node, roles: [:interaction]}], else: []
      Supervisor.start_link(children, strategy: :one_for_one, name: Beamlet.CLI.Supervisor)
    end
  end
end
