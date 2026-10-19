defmodule Beamlet.Runtime.ExecutionSupervisor do
  @moduledoc false
  # Workers 与 Gateway 以 one_for_all 共存亡，旧任务不能跨越新一代容量账本。
  use Supervisor

  @spec start_link({Beamlet.Runtime.options(), Beamlet.Runtime.Limits.t()}) ::
          Supervisor.on_start()
  @spec init({Beamlet.Runtime.options(), Beamlet.Runtime.Limits.t()}) ::
          {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}} | :ignore
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
