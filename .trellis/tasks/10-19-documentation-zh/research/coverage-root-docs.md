# root-docs 组件交接（中文阶段）

状态：COMPLETE（仅 root-docs 组件；不代表中文阶段集成验收或父任务验收）。未启动英文阶段。
范围：根中文文档、术语表、架构/持久化中文说明、部署使用说明，以及根/应用 `mix.exs`、`config/*.exs`、`scripts/quality`、`scripts/deployment` 的解释性注释。
约束遵守：只改文档、注释与文档属性文本；未改任何可执行表达式、类型/spec/签名、配置值、Gettext/UI 文案、测试、依赖；未改他人应用 `lib/`、应用 README 或 Web 专题；未提交、未切分支、未激活/归档任务、未运行全项目格式化。

## 1. 交付的文档路径

| 路径 | 动作 | 实际覆盖内容 |
| --- | --- | --- |
| `README_zh.md` | 新建 | WIP 状态与已实现/未验证边界；13 个应用链接到各自 `README_zh.md`；`flake.nix`/1.20 工具链、首次联网（Hex、esbuild 从 npm registry、Tailwind 从 GitHub Releases）、Python3.11+ 仅部署脚本；`nix develop` → `mix deps.get` → `mix compile` 构建流程与 `BEAMLET_BACKEND_BUILD=1` 的十二应用隔离构建；应用子目录 Mix 任务不可靠的真实原因；Web/Server/CLI/嵌入 Node 四条 opt-in 启动路径；显式 format3 安装与三个 release；证据边界与致谢 |
| `GLOSSARY_zh.md` | 新建 | 先给"概念 → 归属应用 → 主模块/表"速查表，再列 20 个术语（Agent、Authority、definition、Generation、Operation、Execution、Result、execution evidence、acceptance、consumption、command、checkpoint、model context、continuation、recovery、reconciliation、fork、rewind、trace、dispatch scope/epoch、journal attempt），每条含定义与"避免"说法；标识符、错误标签与持久化字段保持原拼写 |
| `architecture_zh.md` | 修订 | 目标架构定位与双语头保留；"authority 使用格式 2"改为 format3（轨迹 format2）并指向中文持久化文档；新增"与当前实现的关系"（已实现/名称已变化/未验证/后续语言阶段）；§3 加现名说明（13 应用、`beamlet_app_web`、三个 storage 库、`beamlet_agent_core`）；§5 补三个命名 release 与"未做物理部署验收"；§12 历史基线列表加实现说明 |
| `docs/architecture/agent-operation-persistence_zh.md` | 新建 | 按源码核对的中文持久化设计；表清单补 `agent_operation_projections` 只读视图与 `commands`/`checkpoints` 实际字段含义；事件 schema 版本固定为 1 并指向 `Codec`/`Reducer`；消费去重补 `evidence_resolution`；§10 证据归属改为"历史任务取得、本次未重跑" |
| `docs/architecture/persistence-delivery_zh.md` | 新建 | A–E 验收维度、存储必须保留的约束、需求追踪；范围段把"authority 格式 2 / journal 格式 1"修正为统一 format3（1/100/300、1/200）；§5 明确为归档任务的历史记录并给出 `final-acceptance.md`、`independent-check.md` 链接与重新验证入口 |
| `scripts/deployment/README_zh.md` | 新建 | 英文部署说明的中文版本：破坏性迁移表、单产物三种启动配置、runtime.exs/RELEASE_NAME 语义、资源与 Web 构建顺序、服务/集群引导、CLI 会话与 `id64:`、durable 存储、检查脚本范围；开头补"本地检查 ≠ 部署/跨机/付费验收" |

中文文档不链接不存在的英文目标：`README_zh.md`、`scripts/deployment/README_zh.md` 指向的文件确实是英文；`architecture_zh.md` 的 `architecture.md` 是英文；`GLOSSARY_zh.md` 与两份 `docs/architecture/*_zh.md` 只用"语言状态"说明同目录无后缀文件目前仍是中文原文，英文对照留待后续阶段。

## 2. 源码/构建/配置注释审阅与决策

### 根与应用 `mix.exs`（14 个文件）

| 路径 | 已审阅声明 | 补充的中文说明 | 未逐项加注的理由 |
| --- | --- | --- | --- |
| `mix.exs` | `project/0`、`deps/0`、`cli_entrypoint/1`、`backend_apps/0`、`aliases/0` | umbrella 无根 lib/test/priv；`BEAMLET_BACKEND_BUILD` 与 `_build/backend`；`dialyzer` 的两个额外 warning flag；`default_release`/三个 release 闭包；`listeners` 仅在非后端构建注册；根依赖只供开发/分析；`cli_entrypoint` 为何改写 `start` 行；`backend_apps` 返回 nil 的含义；`sobelow`/`bench` 别名范围 | `releases` 内每个应用项由上面三条说明覆盖，不重复逐行 |
| `apps/beamlet_actions/mix.exs` | `project/0`、`application/0`、`deps/0` | 纯契约库、无兄弟依赖、无 Application 回调、共享 umbrella 路径 | 空的 deps 列表已由一行说明覆盖，不注释占位 |
| `apps/beamlet_actions_storage/mix.exs` | `project/0`、`application/0` | 只依赖 Actions + Storage；不依赖 Agent/Runtime/Node/宿主；Ecto 与驱动精确版本；加载不启 Repo | 各驱动条目名称即语义 |
| `apps/beamlet_agent_core/mix.exs` | `project/0`、`application/0`、`deps/0` | 纯归约核心；Harness 仅用于消息/模型契约；无进程与 I/O | `jason` 条目不单注 |
| `apps/beamlet_agent/mix.exs` | `project/0`、`application/0`、`deps/0` | 门面库依赖分组（持久化 / 契约与执行）；不依赖 Node 或宿主 | 每个兄弟应用职责已在分组注释中 |
| `apps/beamlet_agent_storage/mix.exs` | `project/0`、`application/0` | 只依赖 Actions Storage + Storage；永不反依赖 Agent/Core/Runtime/Node/宿主 | Ecto/驱动条目同上 |
| `apps/beamlet_app_server/mix.exs` | `project/0`、`application/0`、`deps/0` | `mod:` 表示宿主回调；只依赖 Node + Storage；默认禁用 | Node 内部模块不在本文件范围 |
| `apps/beamlet_app_web/mix.exs` | `project/0`、`application/0`、`elixirc_paths/1`、`deps/0`、`aliases/0` | 宿主回调与"业务库不反依赖 Phoenix"；`~> 1.17` 是历史下界、以 1.20 为准；test-only Runtime、dev-only 工具、资源 profile 名 `beamlet_web`；别名只在应用目录注册 | 单个 Phoenix 依赖无需逐条解释 |
| `apps/beamlet_cli/mix.exs` | `project/0`、`application/0`、`deps/0` | 宿主回调但普通加载空树；Runtime/Harness/Jason 仅测试；发布闭包不含 Server/Web；i18n/Gettext/Owl/Ucwidth 的用途 | 同上 |
| `apps/beamlet_harness/mix.exs` | `project/0`、`application/0`、`deps/0` | 无兄弟依赖、无回调；`req` 精确版本因不内部重试/重定向 | — |
| `apps/beamlet_i18n/mix.exs` | `project/0`、`application/0`、`elixirc_paths/1`、`deps/0` | 叶子库，只依赖 Gettext，不能反依赖宿主 | 测试路径两子句自明 |
| `apps/beamlet_node/mix.exs` | `project/0`、`application/0`、`deps/0` | 库而非宿主；三个存储库与 Ecto 用于显式配置/描述符；不依赖宿主 | — |
| `apps/beamlet_runtime/mix.exs` | `project/0`、`application/0`、`deps/0` | 依赖 Actions/Storage/Actions Storage；不依赖 Agent/Harness/宿主 | — |
| `apps/beamlet_storage/mix.exs` | `project/0`、`application/0` | 无兄弟依赖、加载不启 Repo；SQLite/PostgreSQL 共享约束 | — |

### `config/*.exs`（5 个文件）

| 文件 | 已审阅内容 | 补充的中文说明 |
| --- | --- | --- |
| `config/config.exs` | 共享 umbrella 配置、`namespace`、`default_locale`、Endpoint、esbuild/Tailwind profile、logger、`json_library`、末尾 `import_config` | umbrella 共享语义与"移出 umbrella"的建议；`zh_CN` 默认与 `en` 归属；profile 名 `beamlet_web` ≠ OTP app 名；环境配置必须最后导入 |
| `config/dev.exs` | loopback 绑定、`check_origin`、reloader、固定 dev secret、watchers、LiveView 调试、LiveDebugger、`dev_routes` | dev secret 不得用于生产；watcher 使用 `beamlet_web` profile；`dev_routes` 是编译期开关 |
| `config/prod.exs` | `cache_static_manifest`、`force_ssl` 与本机排除 | 必须先 `mix phx.digest`；`force_ssl` 编译期生效需重建；白名单需自行审阅 |
| `config/runtime.exs` | `RELEASE_NAME` 分支、prod Web secret 检查、IPv6 监听、SSL 注释 | 发布与源码共用、按 release 只启用一个宿主；后端 release 不需要 Web 密钥但源码方式仍检查 |
| `config/test.exs` | `server: false`、端口、测试 secret | 测试不监听端口，端口的实际作用 |

### `scripts/quality`（3 个文件）

| 文件 | 已审阅内容 | 补充的中文说明 |
| --- | --- | --- |
| `check-contracts.exs` | 两行入口：`Code.require_file` + `System.halt` | 运行方式、退出码 1/2、先跑回归再扫生产、`--inventory` |
| `check-contracts-test.exs` | `ExUnit.start(seed: 631_927)` 与全部夹具 | 回归测试先证明分类规则；夹具不是生产 API 承诺 |
| `contracts.exs` | `@moduledoc`、全部类型、`scan/1`、`main/1`、`walk_*`、`collect*`、`render*` 与现有英文注释 | `@moduledoc` 增中文段（parse-only、无豁免、只证明声明存在）；`def/defp/...` 分支补 guard 与静态归属注释 | 私有辅助（`alias_context`、`module_name`、`signature`、`collect_event`、`decorate`）已有英文注释且名字自明，不再重复 |

### `scripts/deployment`（11 个文件）

| 文件 | 已审阅内容 | 补充的中文说明 |
| --- | --- | --- |
| `check-local.sh` | 全部 50 行门禁与两条负例 | 文件头说明门禁顺序、日志与"本地通过≠部署验收"；两条负例（退役 release 名、缺失 Web 密钥）必须失败否则中止 |
| `check-release.sh` | 复制、指纹、闭包禁止项、`eval` 断言、named/CLI/Web 子检查 | 复制产物检查范围与"同主机证据"；先复制再检查与指纹用途。Web 段内嵌 Python 已有英文注释，不再加注 |
| `durable-e2e.sh` | 两个 OS 进程阶段、`DURABLE_E2E_DIR` | 中文头段（阶段一/阶段二语义、不含断电/跨机），英文原文保留 |
| `check-named-release.py` | `Service`、`report_cleanup_failures`、`stop_services`、`daemon_smoke`、`vm_running`、`main` 与九条非法配置 | 模块 docstring 补中文（夹具只改副本 runtime.exs、清理保留主错误） | 方法体逐分支逻辑已由既有英文注释与断言表达 |
| `check-cli-release.py` | 全部会话/身份/PTY 断言 | docstring 补中文（`BEAMLET_LANG=en` 的原因与语言切换归属） | — |
| `http-fixture.py` | `Handler`、`main` | docstring 补中文（不访问真实提供方、先 Tool 后摘要） | — |
| `test-cli-pty.py` | `terminal/6`、`__main__` 向量 | docstring 补中文（PTY 与 finally 清理） | — |
| `test-check-named-release.py` | `CleanupTest` 全部用例 | docstring 补中文（清理组合语义、不代表服务已停） | — |
| `server.example.exs` / `cli.example.exs` / `agent-options.example.exs` | 全部示例配置 | 中文说明"示例不会被自动加载"、启动无需模型凭据、`roles` 省略语义、`allowed_nodes` 可信来源、`agent_options` 是可信可执行代码 | 示例字段本身由取值自明 |

刻意未加注释：Python 服务类方法与构造函数中命名已表达意图的分支（如 `Service.command`、`Service.start` 的就绪轮询）；shell 中已有英文注释的循环；`scripts/deployment/__pycache__`（生成物，不触碰）；`benchee` 示例 `bench/enum.exs` 已有"不是性能基线"的说明，不在本组件范围内改动。

## 3. 聚焦验证（全部从仓库根目录执行）

实际执行与结果：

- `mix format mix.exs apps/*/mix.exs config/*.exs scripts/quality/*.exs scripts/deployment/{agent-options,cli,server}.example.exs` 后 `mix format --check-formatted <同 25 个文件>`：通过。只对本次编辑的 Elixir 文件格式化，未运行全项目格式化。
- `mix compile --warnings-as-errors`：通过，无输出。
- `elixir scripts/quality/check-contracts.exs`：`Files: 148; functions: 1345; covered: 1345; missing: 0; errors: 0`。
- `/tmp/root_docs_ast.exs`（自写临时脚本，不入库）：25 个被编辑的 Elixir 文件与 `HEAD` 的 AST 在去除位置元数据与 `@doc/@moduledoc/@typedoc` 后相同；`config`、`mix.exs` 与脚本的取值、顺序、别名均未变。
- Python/shell 语法：`bash -n` 三个 shell 脚本通过；`python3 -m py_compile` 五个 Python 文件通过。
- `git diff --check`：通过（无空白错误）。
- 链接检查（自写临时脚本）：6 份中文 Markdown 的全部相对链接存在。
- 示例核对：`mix run --no-start /tmp/readme_snippet.exs` 执行 `README_zh.md` 的 Node 嵌入示例，返回 `configured: true`、roles 与 ready 服务；`Beamlet.Server.configuration(enabled: true, node: [roles: [:authority, :executor]])` 与 `Beamlet.Node.configuration(roles: [...])` 均返回 `{:ok, ...}`，与 README 片段一致。

未执行（交由集成阶段，非本组件的文件范围）：`mix test` 全量、`mix credo`/`--strict --all`、`mix dialyzer`、`mix sobelow`、`mix gettext.extract --check-up-to-date`、三个 release 构建、`check-release.sh`/`check-local.sh`/`durable-e2e.sh`。理由是这些门禁覆盖全项目与同主机重活，且本组件只改注释文本；`check-local.sh` 会重新构建产物，不在单组件阶段运行。

工具限制记录：编辑器路径的语言分析（pi-lens/elixir analysis）对 `apps/beamlet_node/lib/beamlet/node.ex`（非本组件文件）多次返回 "unavailable/inconclusive"，另在 `apps/beamlet_cli/mix.exs` 一次返回 unavailable；这些**没有**被当作干净结果。本组件以 `Code.string_to_quoted!` + `mix format --check-formatted` + `mix compile --warnings-as-errors` + 契约扫描 + AST 等价比对替代判断。

## 4. 剩余事项与集成建议

1. **宿主组件遗留的断链**（不在本组件可改范围）：`apps/beamlet_app_server/README_zh.md`、`apps/beamlet_app_web/README_zh.md`、`apps/beamlet_cli/README_zh.md`、`apps/beamlet_i18n/README_zh.md` 都写了 `[English](README.md)`，但这四个应用没有 `README.md`。需由 hosts 所有者或集成阶段修正（去掉链接或改为说明"英文待补"）。
2. **无后缀中文同源文件**：`GLOSSARY.md`、`docs/architecture/agent-operation-persistence.md`、`docs/architecture/persistence-delivery.md` 目前仍是中文原文。本组件按计划只新建 `_zh.md` 作为维护版本并在文首说明语言状态，短期存在内容重复；英文阶段应把它们翻译为英文并保留 `_zh.md` 的互链。
3. **架构基线未重写**：`architecture_zh.md` 仍保留 §3 六应用表与 §12 历史排除项，仅加实现说明与现名导航。这是"目标架构"文档的定位；不要把目标能力改写成已实现清单。
4. **未验证声明**：本组件未执行任何部署、release 构建、跨机或付费调用；相关文档一律标注"未验证/同主机证据"。
5. **英文阶段输入**：中文基线为本组件 6 份文档 + 前五个组件的 13 份应用 README/专题与源码中文说明；英文阶段应逐项对照，发现中文有误时先改中文再改英文。
6. 未修改共享 `coverage.md`、`verification.md`、其他组件交接或任务状态。
