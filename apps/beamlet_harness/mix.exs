defmodule Beamlet.Harness.MixProject do
  use Mix.Project

  # 原生 Harness：没有兄弟应用依赖，也没有 Application 回调；
  # 加载库不会启动进程、沙箱或读取凭据。
  def project do
    [
      app: :beamlet_harness,
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
      # 固定精确版本：HTTP 实现不在内部重试/重定向，升级需单独审阅。
      {:req, "== 0.7.5"},
      {:jason, "~> 1.4"}
    ]
  end
end
