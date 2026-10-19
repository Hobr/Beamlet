# 中文文档与注释阶段验证记录

状态：**STATUS: COMPLETE**。中文覆盖与适用门禁均已完成；原阻塞的 `mix gettext.extract --check-up-to-date` 已解决（见 §10）。**用户在中文阶段完成后放弃英文阶段**：英文子任务已撤销，英文文档与英文源码说明不再补齐，本报告即最终验收记录。

初始核对于 `HEAD = 87fd45781e783a36e7a1101a420b30813f9c02ab`、`dev` 工作区；本报告 §10 记录收尾处理。所有命令均在仓库根目录 `/mnt/data/Project/Beamlet` 执行；未切换分支、未改动测试/依赖/配置值/产品文案。

环境：Elixir 1.20.4 / Erlang OTP 29（nix store 工具链），`deps` 已安装；**无 PostgreSQL**（`BEAMLET_PG_SOCKET_DIR` 未设置）、无命名节点/物理跨机、无付费模型、未执行部署或发布打包。

## 1. 覆盖实测

| 项目 | 实测结果 | 依据 |
| --- | --- | --- |
| 生产源文件 | `apps/*/lib/**/*.ex` 共 148 个，`git status` 中 148 个均有改动，无遗漏 | `git status --porcelain`；与 `find` 清单 `comm` 差集为空 |
| 模块与文档块 | 163 个模块；111 个可见模块有中文 `@moduledoc`；52 个保持 `@moduledoc false` | 编译后 `Code.fetch_docs/1` 全量导出（13 应用、148 文件） |
| 中文 API/类型说明 | 554 条（函数/宏/回调/类型 `@doc`/`@typedoc` 含 CJK） | 同上 |
| 保留英文说明 | 86 条（框架生成/既有英文；本阶段未新增英文翻译） | 同上 |
| 隐藏文档 | `:hidden` 260 条，与 `@doc false`/`@moduledoc false` 语义一致 | 同上 |
| 未加注条目 | 449 = 框架/宏生成 194（Ecto Repo 4×42、Endpoint 10、Router 4、Gettext 9、`embed_templates` 2、模板 `render/1` 1）+ 隐藏模块内部形状 255 | 同上；可见模块中已无“有说明义务却未加注”的项目函数 |
| 逐文件对照 | 148 个文件在本任务 `research/coverage-*.md` 中均有模块/API 组与隐藏/生成边界的说明 | 见父任务 `research/coverage.md` 的逐文件表 |

中文文档入口（21 份）：`README_zh.md`、`GLOSSARY_zh.md`、`architecture_zh.md`、`docs/architecture/*_zh.md`（2）、`scripts/deployment/README_zh.md`、13 个 `apps/*/README_zh.md`、`apps/beamlet_app_web/HOST_zh.md`、`WORKBENCH_zh.md`。全部存在且已核对；7 个应用（actions、actions_storage、harness、app_server、app_web、cli、i18n）**尚无英文 README**，中文页用语言状态说明代替链接，未制造断链。

## 2. 本次核对修正（仅文档/注释）

1. **断链（4 处）**：`apps/beamlet_app_server/README_zh.md`、`apps/beamlet_app_web/README_zh.md`、`apps/beamlet_cli/README_zh.md`、`apps/beamlet_i18n/README_zh.md` 原先写 `[English](README.md)`，但四个应用没有 `README.md`。已替换为简洁语言状态说明（与 `GLOSSARY_zh.md`、`docs/architecture/*_zh.md` 一致的写法）。修正后 34 份文档 169 条相对链接/锚点 **0 断链**。
2. **缺失中文说明（3 个公开 API 组）**：`Beamlet.Agent.Storage.History.checkpoint_at/3`、`checkpoint_page/3`（原仅英文说明）与 `Beamlet.Agent.Integration.Caller.operation/3`（原无说明）补中文段落；保留原英文，未改签名/类型。
3. 复核宿主组件（上游 503 后恢复的 40 文件 / 6 文档）：重复 `@doc`、私有 `@doc`、模板化 `@typedoc` 已在组件轮次修正，本次静态复扫 173 个 Elixir 文件 **0 处**重复或私有文档属性；40 个源文件保持原 `@moduledoc false`/`@doc false` 数量。

未发现需要删除的虚假能力声明。核对到的关键数字均与源码一致（抽样：Actions 预算 1..3_600_000/262_144/16_384；Runtime 256 报告/1_000_000 字节/5 s/16 未确认序号/30 s 保留；Agent 128 实例/65_536 输入/1_048_000 快照预算/1 024 资源组/65 s；Storage Codec 深度 32/节点 100_000/4 MiB；TerminalArtifacts 64 项/16 MiB/24 MiB；Agent Storage 分页 100/500/4 MiB、继承 128/1 024/5 s；Handles 4 096/1 h/60 s/24 随机字节；Presets 32/64/2 048/65 536）。`trace export` 的英文说明原写 “JSONL events/checkpoints”，源码实际写出 `events/inputs/operations/definition`（`records/1`、`@files`），中文阶段已按源码改正（`checkpoints` 由控制缓存单独读取）。

## 3. 行为不变证据

| 检查 | 结果 |
| --- | --- |
| 忽略 `@doc`/`@moduledoc`/`@typedoc` 与位置元数据的 AST 对比 | **173/173 相同，0 差异**（148 生产 `.ex` + 14 `mix.exs` + 5 `config/*.exs` + 6 `scripts/**/*.exs`）。对比脚本递归移除位置元数据（含 `args=nil`、`.` 节点、关键字对）后逐节点比较；先以“文档属性替换为哨兵再剔除”的方式消除行号与属性数量漂移。 |
| 既有英文文档保留 | 197 条被改写为 heredoc 的单行文档属性，其英文正文在结果文件中逐条子串比对全部仍存在（0 丢失）。 |
| 可见性标记 | 148 个文件逐一比较 `@doc false`/`@moduledoc false` 出现次数：**全部一致**（脚本遍历，无输出）。 |
| 非 Elixir 差异 | 3 个 `.sh` 仅新增中文注释；5 个 `.py` 仅 docstring；3 个 `.example.exs` AST 相同；Markdown 仅文档内容；`.heex`、`assets/`、`priv/gettext`、测试、依赖、`mix.lock` **未改动**。 |
| 空白/冲突 | `git diff --check` exit 0。 |

源码行为、类型/spec、签名、消息字符串、配置值、依赖与 API 可见性均未改变。

## 4. 门禁与命令（实际结果）

| 检查 | 命令 | 结果 | 说明 |
| --- | --- | --- | --- |
| 差异空白 | `git diff --check` | **通过**（exit 0，无输出） | |
| 格式化 | `mix format --check-formatted` | **通过**（exit 0） | 全仓库，非仅改动文件 |
| 编译（dev） | `mix compile --force --warnings-as-errors` | **通过**（exit 0，13 应用全量重编译，无 warning） | 强制重编译，非“已是最新”空跑 |
| 编译（test） | `MIX_ENV=test mix compile --warnings-as-errors` | **通过**（exit 0） | 测试环境含 test-only 依赖 |
| 契约夹具回归 | `elixir scripts/quality/check-contracts-test.exs` | **通过**（40 passed） | |
| 契约扫描器 | `elixir scripts/quality/check-contracts.exs` | **通过**（`Files: 148; functions: 1345; covered: 1345; missing: 0; errors: 0`） | 仅证明声明存在，不代替语义审阅 |
| Credo | `mix credo --strict --all` | **通过**（242 源文件，2803 mods/funs，no issues） | |
| Dialyzer | `mix dialyzer` | **通过**（`Total errors: 0, Skipped: 0`，PLT 已就绪） | 未超时 |
| Sobelow | `mix sobelow` | **通过**（exit 0，SCAN COMPLETE，无检出） | 只读扫描，未修改代码 |
| 链接/锚点 | 自写 Python 相对链接检查（34 份 Markdown） | **通过**（169 链接，0 断链） | 含标题锚点 |
| 文档示例（无副作用） | `mix run --no-start` 执行 actions / harness / agent_core / i18n README 的 Elixir 代码块 | **通过**（4 个代码块全部执行成功，无网络/写库） | CLI `Command.parse`、`identity_token`、`Locale.normalize/put`、`Vocabulary.status` 另在单次 `mix run` 中逐条断言通过 |
| README API 存在性 | 解析全部中文/英文文档中的 31 个 Elixir 代码块，逐个检查 `Module.function/arity` 导出 | **通过**（除标准库/未加载模块的解析噪声外无缺失；`Path.join/2`、`Map.put/3`、`DateTime.utc_now/0`、`Ecto.UUID.generate/0`、`Tools.Deterministic.invoke/2` 另行确认存在） | 写库类示例未执行，仅按源码/测试核对（与组件交接一致） |
| 根命令核对 | `mix help phx.server/tailwind/esbuild/phx.digest/beamlet.storage.migrate` | **通过**（均可用） | `mix help setup`/`assets.deploy` 在根目录**不可用**，文档已据此改写 |
| 测试 | `mix test --exclude postgres_db --seed 631927` | **部分失败（环境）**：13 个应用套件，**519 passed / 46 excluded / 24 failed** | 24 个失败全部是 `Beamlet.Agent.Storage.PostgresContractTest` 的 `** (System.EnvError) could not fetch environment variable "BEAMLET_PG_SOCKET_DIR"`；该模块未打 `postgres_db` 标签，默认 exclude 无法跳过。**不记作通过**。其余 12 个应用套件（harness 35、actions 28、i18n 15、storage 15、agent_core 10、actions_storage 10、runtime 66、agent 109、node 78、app_server 15、app_web 73、cli 25）全部通过 |
| doctest | — | **不适用** | 仓库内无 `iex>` doctest，也无 `doctest` 声明；本阶段未新增 doctest |
| Web/I18n 边界 | `mix gettext.extract --check-up-to-date` | **失败**（exit 1） | 报告 `priv/gettext/default.pot`、`errors.pot` 过期；见 §8 |
| POT 基线归因 | 在 `HEAD` 临时 worktree 运行同一命令；再复制当前 `lib/` 后重跑 extract 并 `git diff` POT | HEAD **通过**（exit 0）；当前树失败；POT 差异 386 行**全部是 `#:` 来源行号**，`msgid`/`msgstr` 完全一致 | 证明失败由本阶段文档/注释插入行号引起，不是产品文案差异；未在主工作区生成或修改任何 `.pot`/`.po` |
| 部署/发布/跨机 | `check-local.sh`、`check-release.sh`、`durable-e2e.sh`、release 构建 | **未执行** | 需发布打包、同主机复制产物与两进程 E2E；本阶段只改文档，父计划将这些列为部署边界，且本记录不声称已通过 |
| 命名节点/物理跨机/付费模型/断电 | — | **未执行** | 无此环境；文档中相应能力均标注“未验证” |

超时：以上命令均在有界时间内完成，**无超时/不确定结果**。

## 5. 中文基线

| 项 | 值 |
| --- | --- |
| 基线提交 | `87fd45781e783a36e7a1101a420b30813f9c02ab` |
| 中文文档（21 份 SHA-256 清单）聚合摘要 | `c25c26a594f03273696cbd6327808bf99100e96b289073a1623711090ba5bc7a`（复现：`sha256sum README_zh.md GLOSSARY_zh.md architecture_zh.md docs/architecture/*_zh.md scripts/deployment/README_zh.md apps/*/README_zh.md apps/beamlet_app_web/HOST_zh.md apps/beamlet_app_web/WORKBENCH_zh.md \| sha256sum`） |
| 生产源码文档差异摘要 | `git diff -- 'apps/*/lib/**/*.ex' \| sha256sum` = `ae31dff2f5986ac55f6d4fbdbe6cd5b1c4b0d09b09ad52cc5a225721a9687167` |
| 构建/配置/脚本差异摘要 | `git diff -- mix.exs 'apps/*/mix.exs' 'config/*.exs' 'scripts/**' \| sha256sum` = `f527a2d09e5262cc5898476d7083d5ef4c33482d2d6fc8128c866ef3fe56c3cb` |
| 已跟踪 Markdown 差异摘要 | `git diff -- '*.md' \| sha256sum` = `9176b55fa995d956976c00d53eb33f026c0d2a36fd3cfebfa46610394b34a1f7` |
| 工作区状态 | 182 个已跟踪文件修改 + 23 个未跟踪（20 份新中文文档 + 3 个任务目录），无暂存 |

## 6. 语义核对方式（不是“文件被编辑过”）

- 逐文件阅读：148 个生产源文件的模块正文、公开函数/宏/回调/类型；对本阶段新增/改写的中文说明，对照源码常量、调用方与测试核对数值、错误标签、生命周期与“不重试/不确定”边界（抽样核对范围见 §2，覆盖 Actions/Harness/Agent/Runtime/Node/Storage/Web/CLI/I18n 各至少 2 个模块）。
- 文档入口核对：13 个应用 README 的依赖声明与各自 `mix.exs` 的 `deps` 对照；“无 Application 回调/默认禁用/显式安装”等声明与 `application/0`、`mod:`、启动路径对照；数字上限与源码常量逐个抽查；示例代码实际执行或按源码/测试核对。
- 假能力声明：检查“已实现 vs 未验证”表述；物理跨机、断电、付费模型、真实部署在所有文档中都标为未验证；`scripts/deployment/` 只声称同主机复制产物证据。

## 7. 未执行与不推断

- 写库类 README 示例（storage / actions_storage / agent_storage / server / web）未实际执行，只按源码与既有测试核对；执行会产生本地数据库文件与潜在锁竞争，组件交接亦未执行。
- 部署脚本、release 构建、命名节点、物理跨机、付费 provider、断电、浏览器端到端未运行；不得据此推断通过。
- 未新增业务测试、未修改测试、未新增依赖或文档生成站点（ExDoc）。

## 8. 阻塞项与残留风险

1. ~~**POT 基线过期**~~ **已解决**：见 §10。重生成只改动 `#:` 来源行，`msgid`/`msgstr` 完全一致，`--check-up-to-date` 现已通过。
2. ~~**七个应用缺英文 README**~~ **已撤销**：用户放弃英文阶段，不再补齐；中文页用语言状态说明代替链接，未制造断链。
3. **环境限制**：无 PostgreSQL，24 个 `PostgresContractTest` 在 setup 失败（`BEAMLET_PG_SOCKET_DIR` 未设置），已记录为环境限制而非通过；命名节点/跨机/断电/付费模型/部署未验证。
4. **既有英文瑕疵（非本阶段引入）**：`runtime.ex` 的 “At most256 … and1,000,000”“Finite5s”、`node.ex` 的 “at most32”、`session.ex` 的 “at most128” 在 `HEAD` 已存在；英文阶段已撤销，本次未修改这些英文文本。
5. **文档声明未复跑**：`scripts/deployment/` 的行为说明沿用既有英文专题，本阶段未重新演练；`docs/architecture/persistence-delivery_zh.md` 明确标注 §5 数字为历史任务记录。

## 9. 结论

- 中文覆盖无“有说明义务却未说明”的实质缺口：148/148 源文件已审阅并记录，可见模块公开 API 仅剩框架/宏生成项目未手写文档，隐藏边界全部保留。
- 行为不变、类型/契约/可见性不变已用 AST 与标记对比证明；格式、编译、契约、Credo、Dialyzer、Sobelow、链接与无副作用示例均通过。
- 因 §8.1 的 POT 决策未定（且英文阶段按计划未开始），本阶段不宣称验收通过：**STATUS: INCOMPLETE**。父会话决定 POT 处理方式与英文阶段是否启动。

## 10. 收尾处理（父会话）

1. **Gettext 目录**：在仓库根运行 `mix gettext.extract --merge`，重生成 14 个 `.pot`/`.po`。逐文件对比 `HEAD` 与当前内容（剔除 `#:` 行）确认 **`msgid`/`msgstr` 完全一致**；差异仅为来源行号（2316 行 `#:` 变更）。随后 `mix gettext.extract --check-up-to-date` **exit 0 通过**。
2. **英文阶段**：用户明确表示“放弃英文”。英文子任务已解除父子关联并删除（未实施、无产品改动）；父任务 PRD/design/implement 已把验收范围收敛为中文，七个缺失英文 README 的应用保持原状。
3. **测试环境限制不变**：24 个 `PostgresContractTest` 仍因 `BEAMLET_PG_SOCKET_DIR` 未设置而在 setup 失败，记录为环境限制而非通过；未执行部署、发布、命名节点、物理跨机或付费模型验收。
4. **最终结论**：中文覆盖无实质缺口；行为、类型/契约、配置值与可见性标记未变；可用门禁（格式、编译、契约、Credo、Dialyzer、Sobelow、链接、Gettext 目录）全部通过。剩余失败仅限上文已声明的环境限制。
