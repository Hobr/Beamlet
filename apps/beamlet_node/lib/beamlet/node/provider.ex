defmodule Beamlet.Node.Provider do
  alias Beamlet.Harness.Tools.WorkspaceRead

  @moduledoc "Executor-local profile ownership. Provider loss couples Runtime teardown before fresh readiness."
  use GenServer
  @spec start_link(Beamlet.Node.profiles()) :: GenServer.on_start()
  def start_link(profiles), do: GenServer.start_link(__MODULE__, profiles, name: __MODULE__)
  @impl true
  @spec init(Beamlet.Node.profiles()) ::
          {:ok, Beamlet.Node.profiles()} | {:stop, :provider_unavailable}
  def init(profiles) do
    if Enum.all?(profiles, fn {_, p} -> ready?(p) end),
      do: {:ok, profiles},
      else: {:stop, :provider_unavailable}
  end

  @spec ready?(Beamlet.Node.profile()) :: boolean()
  defp ready?(%{module: WorkspaceRead, settings: settings}) do
    match?({:ok, _}, WorkspaceRead.validate_root(settings[:root])) and
      Map.keys(settings) -- [:root, :max_bytes] == [] and
      valid_read_limit?(Map.get(settings, :max_bytes, 65_536))
  end

  defp ready?(_), do: true

  @spec valid_read_limit?(term()) :: boolean()
  defp valid_read_limit?(limit), do: is_integer(limit) and limit in 1..65_536
end
