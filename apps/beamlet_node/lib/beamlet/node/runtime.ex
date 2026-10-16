defmodule Beamlet.Node.Runtime do
  alias Beamlet.Runtime.SharedSupervisor
  @moduledoc false
  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}

  def start_link(opts) do
    providers = [Process.whereis(Beamlet.Node.Provider) | Keyword.get(opts, :providers, [])]
    SharedSupervisor.start_link(Keyword.put(opts, :providers, providers))
  end
end
