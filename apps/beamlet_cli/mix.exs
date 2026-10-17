defmodule Beamlet.CLI.MixProject do
  use Mix.Project

  def project do
    [
      app: :beamlet_cli,
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
      extra_applications: [:logger],
      mod: {Beamlet.CLI.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:beamlet_node, in_umbrella: true},
      {:beamlet_agent, in_umbrella: true},
      {:beamlet_runtime, in_umbrella: true, only: :test},
      {:beamlet_harness, in_umbrella: true, only: :test},
      {:jason, "~> 1.4", only: :test},
      {:owl, "~> 0.13"},
      {:ucwidth, "~> 0.2"}
    ]
  end
end
