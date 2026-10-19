defmodule Beamlet.Umbrella.MixProject do
  use Mix.Project

  # 根项目只声明 umbrella 布局与发布配置，没有自己的 lib/test/priv；
  # 每个应用的运行代码、测试与资源都在 apps/<app>/ 下。
  def project do
    [
      apps_path: "apps",
      # BEAMLET_BACKEND_BUILD=1 时切到隔离的 _build/backend 并只编译后端应用，
      # 使后端发布不会带入 Web/Phoenix 依赖闭包。
      apps: backend_apps(),
      build_path:
        if(System.get_env("BEAMLET_BACKEND_BUILD") == "1", do: "_build/backend", else: "_build"),
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # 保持默认警告并额外启用 :unmatched_returns 与 :unknown；项目不使用忽略文件。
      dialyzer: [plt_add_apps: [:mix], flags: [:unmatched_returns, :unknown]],
      aliases: aliases(),
      # 不带名称的 `mix release` 选择 server；三个命名 release 各自只含自己的依赖闭包。
      default_release: :beamlet_server,
      releases: [
        beamlet_server: [applications: [beamlet_app_server: :permanent]],
        beamlet_web: [applications: [beamlet_app_web: :permanent]],
        beamlet_cli: [
          applications: [beamlet_cli: :permanent],
          steps: [:assemble, &cli_entrypoint/1, :tar]
        ]
      ],
      # 后端构建不含 Web/Phoenix，因此只有非后端构建才注册代码重载监听器。
      listeners: if(backend_apps(), do: [], else: [Phoenix.CodeReloader])
    ]
  end

  # 根依赖只给开发/分析工具用，不会成为任何 apps/ 子应用的运行时依赖。
  # 子应用的实际依赖写在各应用自己的 mix.exs，而不是只写在 umbrella 根。
  #
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

  # CLI 发布需要在 `start` 时进入前台 Runner 循环，而默认 start 只启动应用。
  # 这里改写生成的启动脚本；`rpc` 等控制命令不受影响。
  defp cli_entrypoint(release) do
    path = Path.join([release.path, "bin", "beamlet_cli"])
    script = File.read!(path)
    script = String.replace(script, ~s|start "elixir" --no-halt
|, ~s|start "elixir" --no-halt -e 'Beamlet.CLI.Runner.main()'
|)
    File.write!(path, script)
    release
  end

  # 后端选择器：十二个后端应用，刻意不含 Web；未设置环境变量时返回 nil，
  # 表示按 apps_path 编译完整 umbrella。
  defp backend_apps do
    if System.get_env("BEAMLET_BACKEND_BUILD") == "1",
      do: [
        :beamlet_actions,
        :beamlet_storage,
        :beamlet_actions_storage,
        :beamlet_agent_storage,
        :beamlet_runtime,
        :beamlet_harness,
        :beamlet_agent_core,
        :beamlet_agent,
        :beamlet_node,
        :beamlet_app_server,
        :beamlet_i18n,
        :beamlet_cli
      ],
      else: nil
  end

  # sobelow 只在 Web 应用内运行；bench 以 --no-start 运行示例基准，
  # 避免为了比较 Enum/推导式而启动整个 umbrella。
  defp aliases do
    [
      sobelow: ["sobelow --root apps/beamlet_app_web --private"],
      bench: ["run --no-start bench/enum.exs"]
    ]
  end
end
