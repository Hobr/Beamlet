defmodule Beamlet.Storage.Repo do
  @moduledoc """
  Declare an explicitly named trusted repository with the foundation connection
  settings. Example: `use Beamlet.Storage.Repo, adapter: :sqlite` (or `:postgres`).
  Each declared module is its own registered instance. Loading it starts nothing;
  Dataset opens it and Host may own its lifecycle. No migrations run in init.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    {adapter, configure} =
      case Keyword.fetch!(opts, :adapter) do
        :sqlite -> {Ecto.Adapters.SQLite3, :sqlite}
        :postgres -> {Ecto.Adapters.Postgres, :postgres}
        _ -> raise ArgumentError, "unsupported storage adapter"
      end

    quote do
      use Ecto.Repo, otp_app: :beamlet_storage, adapter: unquote(adapter)
      @impl true
      @spec init(:supervisor | :runtime, keyword()) :: {:ok, keyword()}
      def init(_, config) do
        {:ok, apply(Beamlet.Storage.Connections, unquote(configure), [config])}
      end
    end
  end
end
