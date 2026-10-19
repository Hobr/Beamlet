defmodule Beamlet.Node.Runtime do
  alias Beamlet.Runtime.SharedSupervisor
  @moduledoc false
  # Provider 先启动，再将其 PID 纳入 Runtime 监控；Provider 丢失后旧执行资源必须拆除。
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    providers = [Process.whereis(Beamlet.Node.Provider) | Keyword.get(opts, :providers, [])]
    SharedSupervisor.start_link(Keyword.put(opts, :providers, providers))
  end
end
