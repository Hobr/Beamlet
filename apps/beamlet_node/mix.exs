defmodule Beamlet.Node.MixProject do
  use Mix.Project

  # 显式监督的角色组合库：没有 Application 回调，也不依赖任何宿主
  # （CLI/Server/Web 都反向依赖 Node）。三个持久化库与 Ecto 用于
  # 显式存储配置校验与数据集描述，普通加载不会启动 Repo。
  def project do
    [
      app: :beamlet_node,
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
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # 显式持久化资源与两个 domain profile（authority/journal）。
      {:beamlet_storage, in_umbrella: true},
      {:beamlet_actions_storage, in_umbrella: true},
      {:beamlet_agent_storage, in_umbrella: true},
      {:ecto, "~> 3.14"},
      # 角色组合所需的契约、执行与模型/工具边界。
      {:beamlet_actions, in_umbrella: true},
      {:beamlet_runtime, in_umbrella: true},
      {:beamlet_harness, in_umbrella: true},
      {:beamlet_agent, in_umbrella: true}
    ]
  end
end
