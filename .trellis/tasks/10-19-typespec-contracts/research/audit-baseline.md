# Typespec / Dialyzer 审查基线

## 来源与时间边界

本文件保留本会话在任务创建前完成的只读审查结论；不是实施后验收结果。审查对象为 dev 分支 HEAD `7ccec06`，当时工作区干净。任务创建后只写入规划文件。审查没有执行全量测试或强制重建 PLT。

## 一手参考

- https://elixir.hexdocs.pm/typespecs.html — 抓取时为 Elixir v1.20.4。typespec 是独立于正在发展的集合论类型系统的机制；文档介绍 @type/@typep/@opaque/@spec/@callback 等，不要求所有私有函数都必须声明，也不规定排版风格。
- https://www.erlang.org/doc/system/typespec.html — 抓取时为 OTP 29.1.2。mandatory map association 要求对应关联存在；optional association 允许该键类型不出现。
- https://www.erlang.org/doc/apps/dialyzer/dialyzer.html — 抓取时为 OTP 29.1.2。默认及可选 warning 的语义；成功类型分析不是业务正确性证明。
- 本地 `deps/dialyxir/README.md` — 无 spec 仍可进行分析；spec 能提供额外信息，默认不包含全部可选 warnings。

## 代码与配置证据

- `mix.exs:13`：`dialyzer: [plt_add_apps: [:mix]]`，没有额外 flags 或项目 ignore 配置。
- `mix.exs:35`：Dialyxir `~> 1.4`，dev/test，runtime false。
- `.pre-commit-config.yaml:29–34`：本地 mix dialyzer hook，pass_filenames false，匹配 Elixir 与 mix.lock。
- `scripts/deployment/check-local.sh:16`：本地集成检查执行 mix dialyzer。
- Git 跟踪的 `.github/` 文件只有 dependabot.yml；没有仓库内 GitHub Actions 检查 workflow。未核验仓库外 CI。
- 13 个 app 均有子 `.formatter.exs`；根 formatter 委托 apps/*。
- 148 个生产 `.ex` 文件的 Elixir AST 属性计数：spec=0，type=7，typep=0，opaque=0，typedoc=0，callback=5，macrocallback=0，behaviour=6，impl=68，dialyzer=0。计数仅统计显式源码属性，不包含宏展开生成声明；不是函数数量统计。
- `apps/beamlet_actions/lib/beamlet/actions/operation.ex:18,22`：credentials/claims 使用 `%{binary() => ...}`；构造器的有效默认值均为空 map，需审查 optional association 的正确表达。
- `apps/beamlet_actions/lib/beamlet/actions/contracts.ex`：OperationRef/ExecutionHandle/Execution/Result 有 t 类型，Handler callback 参数仍为 term()/map()。
- `apps/beamlet_harness/lib/beamlet/harness/model.ex:5–6`、`apps/beamlet_harness/lib/beamlet/harness.ex:7–8`：Model/Tool callbacks 使用宽泛 map()。实际校验器依赖固定请求字段、invocation 字段和 tagged reply 结构。
- `apps/beamlet_agent/lib/beamlet/agent/ref.ex:4`：自有 Ref struct 没有显式类型。
- `apps/beamlet_storage/lib/beamlet/storage/transaction.ex:26,30,83`：participate/write/read 没有显式参数或返回契约。

## 已执行结果

工具链：Elixir 1.20.4 / OTP 29（Dialyzer PLT 名称为 erlang-29.1.2_elixir-1.20.4）。

1. `mix format --check-formatted`：exit 0。
2. `mix dialyzer`：exit 0，Total errors: 0, Skipped: 0, Unnecessary Skips: 0。检查现有 PLT并报告 up to date，未强制重建。
3. `mix dialyzer --unmatched_returns --format short`：exit 2，68 unmatched_return findings，Skipped: 0。完整本地临时日志 `/tmp/beamlet-dialyzer-extra.li3c26`（临时路径不保证跨机器/会话可用；验收应重新运行并保留任务内证据）。
4. `mix run --no-start` 调用 `Operation.new(%{kind: "audit"})`：exit 0，成功返回 credentials/claims 均为空 map 的 Operation。
5. 审查结束时 git status 干净。

## 68 条告警的已知分类线索（未逐条定性）

- 大量来自 `apps/beamlet_i18n/lib/beamlet/i18n/catalogue.ex` 的 msgid 提取声明；注释写明不在运行时调用。
- 多条来自 migration DSL 和 `SQL.query!` 成功结果的丢弃；有意副作用不等于业务 bug。
- 其余包括 CLI/locale、Web、Runtime 的返回值丢弃。例如 OperationCoordinator 的晚到证据持久化结果需要根据 best-effort 设计及测试逐项确认。
- 不得把 68 条全部定为缺陷，也不得为了清零机械地添加 `_ =`。

## 证据限制

图工具曾报告索引基于旧 commit a8acffdc；本审查的关键结论来自直接文件读取与当前工具执行，不将旧图推导当作当前准确引用关系。没有 LSP 全工作区清洁声明、覆盖率证明、全量测试通过声明或 fresh-PLT 验收声明。
