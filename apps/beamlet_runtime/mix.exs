defmodule Beamlet.Runtime.MixProject do
  use Mix.Project

  def project do
    [
      app: :beamlet_runtime,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:beamlet_actions, in_umbrella: true},
      {:beamlet_storage, in_umbrella: true},
      {:beamlet_actions_storage, in_umbrella: true},
      {:ecto, "== 3.14.0"}
    ]
  end
end
