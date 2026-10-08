defmodule Beamlet.Verification.MixProject do
  use Mix.Project

  # 这里只承载验证命令；空编译路径和依赖避免为工具入口建立运行时应用。
  def project do
    [
      app: :beamlet_verification,
      version: "0.1.0",
      elixirc_paths: [],
      deps: [],
      # 薄别名共用脚本编排；mix quint 无参数时由脚本选择核心 all。
      aliases: [
        quint: &quint/1,
        "quint.quick": &quint(["quick" | &1]),
        "quint.simulate": &quint(["simulate" | &1]),
        "quint.verify": &quint(["verify" | &1]),
        "quint.supplemental": &quint(["--suite", "supplemental" | &1])
      ]
    ]
  end

  defp quint(args) do
    Code.require_file("spec/quint/check.exs", __DIR__)

    case Beamlet.Quint.main(args) do
      0 ->
        :ok

      code ->
        # Mix.raise 将执行器失败传播为 CLI exit1，并保留原返回码供诊断。
        Mix.raise("Quint checks failed (runner exit #{code}); see the evidence directory above")
    end
  end
end
