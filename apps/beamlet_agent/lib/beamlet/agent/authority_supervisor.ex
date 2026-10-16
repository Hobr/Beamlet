defmodule Beamlet.Agent.AuthoritySupervisor do
  @moduledoc "Opt-in identity island; Registry loss invalidates all temporary Agents."
  use Supervisor
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_opts) do
    Supervisor.init(
      [
        {Registry, keys: :unique, name: Beamlet.Agent.Registry},
        {Beamlet.Agent.Resources, []},
        Supervisor.child_spec(
          {Task.Supervisor, name: Beamlet.Agent.Delegations, max_children: 1024},
          shutdown: 1000
        ),
        Supervisor.child_spec(
          {DynamicSupervisor,
           name: Beamlet.Agent.Agents, strategy: :one_for_one, max_children: 128},
          shutdown: 1000
        )
      ],
      strategy: :one_for_all
    )
  end
end
