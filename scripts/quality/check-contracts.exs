# 契约（typespec）覆盖与扫描器回归的入口脚本。
# 从仓库根目录运行：
#   elixir scripts/quality/check-contracts-test.exs   # 先验证扫描器自身的分类规则
#   elixir scripts/quality/check-contracts.exs        # 再检查全部 apps/*/lib/**/*.ex
# 退出码：1 表示缺失契约或无法分类的语法，2 表示命令行用法错误；也可加 --inventory 审阅清单。
Code.require_file("contracts.exs", __DIR__)
System.halt(Beamlet.Quality.Contracts.main(System.argv()))
