defmodule Beamlet.Storage.SQLiteRepo do
  @moduledoc "显式启动的中立 SQLite Repo；没有应用回调或自动安装。

Neutral explicitly started SQLite repository. No migrations on start."
  use Beamlet.Storage.Repo, adapter: :sqlite
end

defmodule Beamlet.Storage.PostgresRepo do
  @moduledoc "显式启动的中立 PostgreSQL Repo；须由宿主置备数据库，没有自动安装。

Neutral explicitly started PostgreSQL repository. No migrations on start."
  use Beamlet.Storage.Repo, adapter: :postgres
end
