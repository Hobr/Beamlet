defmodule Beamlet.CLI.MixProject do
  use Mix.Project

  # CLI 前台交互宿主：`mod:` 表示有 Application 回调，但普通加载只启动空树、
  # 不读 stdin。Runtime/Harness/Jason 仅在测试中使用（迁移后的 HTTP 集成夹具），
  # 发布闭包不含 Server/Web。测试环境额外编译 test/support。
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
      # 公共状态/原因词来自共享目录；Node/Agent 提供被调用的业务入口。
      {:beamlet_i18n, in_umbrella: true},
      {:beamlet_node, in_umbrella: true},
      {:beamlet_agent, in_umbrella: true},
      # 仅测试：集成夹具需要真实 Runtime/Harness 与 JSON。
      {:beamlet_runtime, in_umbrella: true, only: :test},
      {:beamlet_harness, in_umbrella: true, only: :test},
      {:jason, "~> 1.4", only: :test},
      # 终端专用文案、表格渲染与 CJK/emoji 列宽测量。
      {:gettext, "~> 1.0"},
      {:owl, "~> 0.13"},
      {:ucwidth, "~> 0.2"}
    ]
  end
end
