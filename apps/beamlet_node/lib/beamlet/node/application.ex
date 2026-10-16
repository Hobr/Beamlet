defmodule Beamlet.Node.Application do
  @moduledoc false
  use Application
  @impl true
  def start(_type, _args) do
    options = Application.get_env(:beamlet_node, :boot, [])
    children = if options == [], do: [], else: [{Beamlet.Node, options}]
    Supervisor.start_link(children, strategy: :one_for_one, name: Beamlet.Node.Supervisor)
  end
end
