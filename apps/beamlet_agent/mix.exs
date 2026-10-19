defmodule Beamlet.Agent.MixProject do
  use Mix.Project

  # Agent 门面库：直接声明 Core/Actions/Runtime/Harness、两个持久化库、
  # Ecto 与 Jason；不依赖 Node 或任何宿主，也没有 Application 回调。
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
      # 持久化输入/消费与只读历史需要两个存储库；它们不反向依赖 Agent。
      {:beamlet_agent_storage, in_umbrella: true},
      {:beamlet_storage, in_umbrella: true},
      {:ecto, "== 3.14.0"},
      {:jason, "== 1.4.5"},
      # 纯归约/上下文归 Core；执行、契约与模型边界分别归 Runtime/Actions/Harness。
      {:beamlet_agent_core, in_umbrella: true},
      {:beamlet_actions, in_umbrella: true},
      {:beamlet_runtime, in_umbrella: true},
      {:beamlet_harness, in_umbrella: true}
    ]
  end
end
