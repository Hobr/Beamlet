defmodule Beamlet.Agent.MixProject do
  use Mix.Project

  def project do
    [
      app: :beamlet_agent,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:beamlet_actions, in_umbrella: true},
      {:beamlet_runtime, in_umbrella: true},
      {:beamlet_harness, in_umbrella: true}
    ]
  end
end
