defmodule Beamlet.Server.MixProject do
  use Mix.Project

  # 后台宿主应用：`mod:` 表示它有 Application 回调（其余后端库没有）。
  # 只直接依赖 Node 与通用 Storage：角色组合与业务 API 都经 Node 取得，
  # 不依赖 CLI、Phoenix 或 I18n。默认禁用，配置后也只启动空树或显式角色。
  def project do
    [
      app: :beamlet_app_server,
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
      extra_applications: [:logger],
      mod: {Beamlet.Server.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Node 提供角色组合与业务入口；Storage 用于宿主启动期的可选数据集配置校验。
      {:beamlet_node, in_umbrella: true},
      {:beamlet_storage, in_umbrella: true}
    ]
  end
end
