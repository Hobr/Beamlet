defmodule Beamlet.Actions.MixProject do
  use Mix.Project

  # 纯契约库：不依赖任何兄弟应用，也没有 Application 回调。
  # 构建/依赖/配置路径全部指回 umbrella 根，与其余应用共享。
  def project do
    [
      app: :beamlet_actions,
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
  # 目前无需依赖：通用数据校验复用 OTP 自带 JSON，
  # 派发与 Handler 实现归 Runtime 及嵌入方。
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      # {:sibling_app_in_umbrella, in_umbrella: true}
    ]
  end
end
