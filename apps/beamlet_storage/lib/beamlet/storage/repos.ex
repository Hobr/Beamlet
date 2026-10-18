defmodule Beamlet.Storage.SQLiteRepo do
  @moduledoc "Neutral explicitly started SQLite repository. No migrations on start."
  use Beamlet.Storage.Repo, adapter: :sqlite
end

defmodule Beamlet.Storage.PostgresRepo do
  @moduledoc "Neutral explicitly started PostgreSQL repository. No migrations on start."
  use Beamlet.Storage.Repo, adapter: :postgres
end
