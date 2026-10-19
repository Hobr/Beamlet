defmodule Beamlet.Storage.MixProject do
  use Mix.Project

  # 通用存储库：不依赖任何兄弟应用，也没有 Application 回调；
  # 加载库不会启动 Repo、建库或迁移。
  # Ecto/SQL 与两种驱动固定精确版本，SQLite/PostgreSQL 共享同一套约束。
  def project do
    [
      app: :beamlet_storage,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: [
        {:ecto, "== 3.14.0"},
        {:ecto_sql, "== 3.14.0"},
        {:ecto_sqlite3, "== 0.25.0"},
        {:postgrex, "== 0.22.4"},
        {:jason, "== 1.4.5"}
      ]
    ]
  end

  def application, do: [extra_applications: [:crypto]]
end
