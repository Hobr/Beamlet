defmodule Beamlet.Runtime.ExecutionSupervisor do
  @moduledoc false
  use Supervisor
  def start_link(args), do: Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  @impl true
  def init({opts, limits}) do
    Supervisor.init(
      [
        {Task.Supervisor, name: Beamlet.Runtime.Workers, max_children: limits.attempts},
        {Beamlet.Runtime.ExecutorGateway, {opts, limits}}
      ],
      strategy: :one_for_all
    )
  end
end
