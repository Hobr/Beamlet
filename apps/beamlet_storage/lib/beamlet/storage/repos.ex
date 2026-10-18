defmodule Beamlet.Storage.SQLiteAuthorityRepo do
  @moduledoc "Explicitly started SQLite authority repository; no automatic migrations."
  alias Beamlet.Storage.Connections
  use Ecto.Repo, otp_app: :beamlet_storage, adapter: Ecto.Adapters.SQLite3
  @impl true
  def init(_, config), do: {:ok, Connections.sqlite(config)}
end

defmodule Beamlet.Storage.PostgresAuthorityRepo do
  @moduledoc "Explicitly started PostgreSQL authority repository."
  alias Beamlet.Storage.Connections
  use Ecto.Repo, otp_app: :beamlet_storage, adapter: Ecto.Adapters.Postgres
  @impl true
  def init(_, config) do
    {:ok,
     Keyword.merge(config,
       pool_size: 4,
       timeout: 5000,
       queue_target: 1000,
       after_connect: &Connections.verify_postgres/1
     )}
  end
end

defmodule Beamlet.Storage.ExecutorJournalRepo do
  @moduledoc "Executor-local SQLite evidence repository, separate from authority."
  alias Beamlet.Storage.Connections
  use Ecto.Repo, otp_app: :beamlet_storage, adapter: Ecto.Adapters.SQLite3
  @impl true
  def init(_, config), do: {:ok, Connections.sqlite(config)}
end
