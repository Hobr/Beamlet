defmodule Beamlet.Actions.Storage.MixProject do
  use Mix.Project

  # Actions 领域持久化：只依赖 Actions 契约与通用 Storage，不依赖
  # Agent/Core/Runtime/Node 或任何宿主，也没有 Application 回调。
  # Ecto/SQL 与两种驱动固定精确版本；加载本库不会启动 Repo。
  def project do
    [
      app: :beamlet_actions_storage,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: [
        {:beamlet_actions, in_umbrella: true},
        {:beamlet_storage, in_umbrella: true},
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
