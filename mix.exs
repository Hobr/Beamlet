defmodule Beamlet.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      apps: backend_apps(),
      build_path:
        if(System.get_env("BEAMLET_BACKEND_BUILD") == "1", do: "_build/backend", else: "_build"),
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: [
        beamlet_node: [
          applications: [beamlet_node: :permanent],
          runtime_config_path: "config/backend_runtime.exs"
        ]
      ],
      listeners: if(backend_apps(), do: [], else: [Phoenix.CodeReloader])
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.16.0", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.5", only: [:dev, :test], runtime: false},
      {:sbom, "~> 0.8", only: :dev, runtime: false}
    ]
  end

  defp backend_apps do
    if System.get_env("BEAMLET_BACKEND_BUILD") == "1",
      do: [:beamlet_actions, :beamlet_runtime, :beamlet_harness, :beamlet_agent, :beamlet_node],
      else: nil
  end

  defp aliases do
    [
      sobelow: ["sobelow --root apps/beamlet_web --private"],
      bench: ["run --no-start bench/enum.exs"]
    ]
  end
end
