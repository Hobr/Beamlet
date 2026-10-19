defmodule Beamlet.I18n.MixProject do
  use Mix.Project

  # 共享文案叶子库：只依赖 Gettext，无兄弟应用依赖，也没有 Application 回调。
  # Web 与 CLI 都引用它，所以它不能反向依赖任何宿主。测试环境额外编译 test/support。
  def project do
    [
      app: :beamlet_i18n,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # 仅 Gettext：共享后端与语言规范化，不引入 Expo 或界库。
      {:gettext, "~> 1.0"}
    ]
  end
end
