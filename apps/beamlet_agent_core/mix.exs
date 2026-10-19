defmodule Beamlet.Agent.Core.MixProject do
  use Mix.Project

  # 纯归约核心：只依赖 Harness 契约与 Jason，不依赖存储/Runtime，
  # 也没有 Application 回调；本库不启动进程、不执行 I/O。
  def project do
    [
      app: :beamlet_agent_core,
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
      # 目的是继续使用 Harness 的消息/模型契约类型，不调用具体提供者实现。
      {:beamlet_harness, in_umbrella: true},
      {:jason, "~> 1.4"}
    ]
  end
end
