defmodule Beamlet.Agent.Storage.MixProject do
  use Mix.Project

  def project do
    [
      app: :beamlet_agent_storage,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: [
        {:beamlet_actions_storage, in_umbrella: true},
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
