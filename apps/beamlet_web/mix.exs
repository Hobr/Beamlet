defmodule BeamletWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :beamlet_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {BeamletWeb.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.12"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard,
       github: "phoenixframework/phoenix_live_dashboard",
       ref: "83a0bd137ed3e4c66b8037b140a2744803a48e13"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:petal_components, "~> 4.17.1"},
      # Upstream PR #35 only pins bitstring sizes for Elixir 1.20 compatibility.
      {:eqrcode,
       github: "tomciopp/eqrcode", ref: "6ea9910fcce048ff96e68a1c255343c04479c067", override: true},
      # Upstream Elixir 1.20 fixes not yet available in Hex releases.
      {:phoenix_html_helpers,
       github: "phoenixframework/phoenix_html_helpers",
       ref: "0b614ed6c8bf21a7bef49fcfd8a7da27a8acc57d",
       override: true},
      {:phoenix_ecto,
       github: "phoenixframework/phoenix_ecto",
       ref: "a0c342b5a57581037974cc992a23f4f89a77b29f",
       override: true},
      {:mdex, "~> 0.12"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext,
       github: "elixir-gettext/gettext", ref: "1b0d9e91fe55837b1eb31f1a364bf42ab323876b"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:phoenix_pubsub, "~> 2.0"},
      {:live_debugger, "~> 1.0", only: [:dev]},
      {:tidewave, "~> 0.9", only: [:dev]},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false, warn_if_outdated: true}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind beamlet_web", "esbuild beamlet_web"],
      "assets.deploy": [
        "compile",
        "tailwind beamlet_web --minify",
        "esbuild beamlet_web --minify",
        "phx.digest"
      ]
    ]
  end
end
