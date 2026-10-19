# hosts 组件覆盖与交接

组件范围：`apps/beamlet_cli`、`apps/beamlet_app_server`、`apps/beamlet_app_web`、`apps/beamlet_i18n`。
所有者：hosts 车道（`research/lanes.md`）。本记录只描述上述应用的中文源码说明与六份中文文档；不修改其他车道文件。

## 1. 本轮恢复方式与结论

上一轮 hosts 运行在上游 503 前已写入 40 个 `lib/**/*.ex` 修改和 6 份中文文档，但没有交接记录。本轮没有重写，而是：

1. 逐份读取 40 个生产源文件全文、6 份中文文档全文；
2. 读取实际调用方/配置/测试：四个应用与根 `mix.exs`、`config/*.exs`、`scripts/deployment/README.md`、`priv/examples/host.exs`、`workbench_live.html.heex`、`assets/js/app.js`，以及 Node/Agent 的被引用契约（`Cluster`、`Observation`、`Node.Storage`、`Agent`、`Display`）；
3. 逐条核对文档措辞，修正不准确、重复或复制粘贴错误的说明；
4. 用编译、测试、AST 对比、链接检查验证。

结论：上一轮的模块说明与大部分函数说明方向正确、可保留；但存在**重复 `@doc`（后写覆盖前写，英文被吞）、`@defp` 上的非法 `@doc`、模板化的 `@typedoc` 填充语、以及一处从其他模块误粘贴的函数说明**。这些已在本轮修正。另有 3 处中文文档与源码/根任务入口不符，已改正（见 §4）。

## 2. 逐文件覆盖（40 个源文件）

记号：**既有已核** = 上一轮已写入、本轮核对后保留或仅微调；**本轮修正** = 本轮改动语义或结构；**本轮新增** = 上一轮没有、本轮补充。
所有文件均保持原有 `@moduledoc false` / `@doc false` 可见性；没有新增公开 API。

### beamlet_i18n（4）

| 文件 | 模块与已审阅/已说明的公开 API | 决策 |
| --- | --- | --- |
| `lib/beamlet/i18n.ex` | `Beamlet.I18n`；`gettext/1,2`、`dgettext/2,3` | 模块说明既有已核；两个函数的中英说明既有已核。**本轮修正**：删除 `gettext/2` 上重复的第二个 `@doc`（原会覆盖中英双语块）。 |
| `lib/beamlet/i18n/catalogue.ex` | `Beamlet.I18n.Catalogue`；`statuses/0`、`reasons/0`、`declare/0` | 模块说明既有已核；`reasons/0`、`declare/0` 既有已核。**本轮修正**：删除 `statuses/0` 上重复 `@doc`。私有 `shared_statuses/0`、`shared_reasons/0` 的提取用途由既有英文注释说明，无需新增。 |
| `lib/beamlet/i18n/locale.ex` | `Beamlet.I18n.Locale`；类型 `t/0`，`default/0`、`locales/0`、`options/0`、`normalize/1`、`canonicalize/1`、`put/1`、`html_lang/1` | 模块与函数说明既有已核。**本轮修正**：`t/0` 的 `@typedoc` 原为“本模块公开数据结构…”填充语，且上方错放了一个 `@doc` 和重复 `@doc`；改为准确的“规范语言标识”中英说明，并移除重复。私有 `aliases/1` 为简单别名表，无需说明。 |
| `lib/beamlet/i18n/vocabulary.ex` | `Beamlet.I18n.Vocabulary`；`status/1`、`reason/1` | 模块说明与 `reason/1` 既有已核。**本轮修正**：删除 `status/1` 上从 `CLI.Client.status/1` 误粘贴的“读取当前基础快照…”说明。私有 `word/3` 两分支由既有代码结构自明，无需注释。 |

### beamlet_app_server（3）

| 文件 | 模块与公开 API | 决策 |
| --- | --- | --- |
| `lib/beamlet/server.ex` | `Beamlet.Server`；类型 `settings/0`，`configuration/1` | **本轮修正**：原文件把 `@doc` 放在 `@typedoc`/`@type` 之前又补了一个单语 `@doc`，导致英文说明被覆盖。已整理为 `@typedoc` → `@type` → 单一中英 `@doc` → `@spec`，并保留原英文对存储/准入的全部约束。 |
| `lib/beamlet/server/application.ex` | `Beamlet.Server.Application`（隐藏） | 既有注释已核：先启动角色、再按显式存储打开数据集、普通加载空树。`start/2` 为框架回调，不再加注。 |
| `lib/beamlet/server/bootstrap.ex` | `Beamlet.Server.Bootstrap`（隐藏） | 既有注释已核：监督启动确认后逐个连接一次、失败继续本地、宿主消失清理调用者、不重试。私有 `run/1` 的序号日志与 `Cluster.connect/2` 预算由既有英文注释覆盖。 |

### beamlet_cli（9）

| 文件 | 模块与公开 API | 决策 |
| --- | --- | --- |
| `lib/beamlet/cli.ex` | `Beamlet.CLI`；类型 `settings/0`，`configuration/1` | 模块、类型、函数说明既有已核；配置仅接受 `enabled`/`allowed_nodes` 与源码一致。 |
| `lib/beamlet/cli/application.ex` | `Beamlet.CLI.Application`（隐藏） | 既有注释已核：只把宿主键交给严格验证器，创建选项与语言键独立归属。 |
| `lib/beamlet/cli/client.ex` | `Beamlet.CLI.Client`；`create/2`、`input/2`、`snapshot/1`、`status/1`、`stop/1`、`close/1`、`watch/2` | 模块说明既有已核。**本轮修正**：`create/2` 原说明误用 Web 的“输入/导航结果”措辞，改为 CLI 实际语义（一次创建、返回真实 Ref 或错误、不重试/不换 authority）；`watch/2` 增补 `output` 选项。`snapshot/status` 关系由说明区分。 |
| `lib/beamlet/cli/command.ex` | `Beamlet.CLI.Command`；类型 `t/0`，`max_bytes/0`、`parse/1`、`identity_token/1` | 模块与三个函数说明既有已核。**本轮修正**：`t/0` 的 `@typedoc` 原为填充语，改为“解析后的固定命令元组；参数数量由语法校验”。私有解析子句无需逐个说明。 |
| `lib/beamlet/cli/gettext.ex` | `Beamlet.CLI.Gettext`；Gettext 后端 | 模块说明既有已核（终端专用文案所有权）。 |
| `lib/beamlet/cli/locale.ex` | `Beamlet.CLI.Locale`；`options/0`、`normalize/1`、`locale/0`、`put/1` | 模块与函数说明既有已核。**本轮修正**：删除 `options/0` 上重复 `@doc`。 |
| `lib/beamlet/cli/renderer.ex` | `Beamlet.CLI.Renderer`；`render/1` | 模块说明既有已核（每页 8 条、id64、错误白名单）。**本轮修正**：`render/1` 原说明过于笼统且与 Web 措辞相同，改为按参数形态（help/发现/身份/快照/节点/错误）描述。私有 `safe_reason/1`、`table/1`、`bounded/2` 的既有注释已说明为什么不能渲染任意 term，无需新增。 |
| `lib/beamlet/cli/runner.ex` | `Beamlet.CLI.Runner`；类型 `options/1`，`main/0`、`run/2`、`read_line/1` | 模块说明既有已核（EOF/quit=0、读取错误=1、退出不关闭 Agent）。**本轮修正**：私有 `read_line/3` 上原有一个 `@doc`（Elixir 会丢弃并可能产生警告），改为解释字节循环与“整行拒绝”的普通注释；把临时 Latin-1 与恢复编码的说明扩成中英 `@doc` 挂在公开 `read_line/1` 上。 |
| `lib/beamlet/cli/session.ex` | `Beamlet.CLI.Session`；类型 `t/0`，`new/1`、`execute/3` | 模块与函数说明既有已核。**本轮修正**：`t/0` 的 `@typedoc` 原为填充语，改为字段含义（别名映射/允许节点/一次发现结果）。私有 `dispatch/3` 各子句由命令语法自明，不再逐条加注。 |

### beamlet_app_web（24）

| 文件 | 模块与公开 API | 决策 |
| --- | --- | --- |
| `lib/beamlet_web.ex` | `Beamlet.Web`；`static_paths/0`、`router/0`、`channel/0`、`controller/0`、`live_view/0`、`live_component/0`、`html/0`、`verified_routes/0`、`__using__/1` | 模块与各宏说明既有已核；共享引用片段只含 imports/uses/aliases 的约束已写入。私有 `html_helpers/0` 为引用片段，无需说明。 |
| `lib/beamlet_web/agents.ex` | `Beamlet.Web.Agents`；类型 `input_result/0`、`creation_result/0`，`discover/1`、`attach/1`、`create/1`、`input/2` | 模块、类型、函数说明既有已核：一次创建/输入、`create_unknown` 不重试、导航与输入分别报告。 |
| `lib/beamlet_web/application.ex` | `Beamlet.Web.Application`（隐藏） | 既有注释已核：Host 与 Endpoint 分开监督；配置变更只转交 Endpoint。 |
| `lib/beamlet_web/components/core_components.ex` | `Beamlet.Web.CoreComponents`；`flash/1`、`button/1`、`input/1`、`header/1`、`table/1`、`list/1`、`icon/1`、`show/2`、`hide/2`、`translate_error/1`、`translate_errors/2` | 组件说明既有已核。**本轮修正**：`flash/1`、`table/1`、`list/1` 各有重复 `@doc`（中文覆盖英文），已合并进原有多行说明；`assigns/0` 的 `@typedoc` 改为准确的框架 assigns 描述；恢复两处被误删的文档空行；模块说明改为“先按字段使用状态过滤，再经 errors 域翻译”。私有 `error/1` 为输入组件的内部片段，无需公开说明。 |
| `lib/beamlet_web/components/layouts.ex` | `Beamlet.Web.Layouts`；`app/1`、`flash_group/1`、`locale_switcher/1`、`theme_toggle/1` | 模块与函数说明既有已核。**本轮修正**：删除 `app/1` 上重复 `@doc`，恢复文档空行。模板由 `embed_templates` 编译，不在此文件逐模板说明。 |
| `lib/beamlet_web/components/observation_components.ex` | `Beamlet.Web.ObservationComponents`；`activities/1`、`text/1`、`turn/1` | 模块与函数说明既有已核：转义/有界、未知不 inspect、轮次标签散列且不重建历史。 |
| `lib/beamlet_web/controllers/error_html.ex` | `Beamlet.Web.ErrorHTML`；`render/2` | 模块与函数说明既有已核：仅返回状态文字，忽略异常 assigns。 |
| `lib/beamlet_web/controllers/error_json.ex` | `Beamlet.Web.ErrorJSON`；`render/2` | 同上；并说明不构成业务 API 校验协议。 |
| `lib/beamlet_web/controllers/page_controller.ex` | `Beamlet.Web.PageController`；`home/2` | 既有说明已核：保留脚手架控制器，根路由实际由 `WorkbenchLive` 处理。 |
| `lib/beamlet_web/controllers/page_html.ex` | `Beamlet.Web.PageHTML` | 既有说明已核：模板容器。 |
| `lib/beamlet_web/endpoint.ex` | `Beamlet.Web.Endpoint` | 既有说明已核：签名 cookie 可读不可篡改、开发运行时工具仅开发启用。socket/session 值未改。 |
| `lib/beamlet_web/gettext.ex` | `Beamlet.Web.Gettext` | 既有说明已核：Web 专用文案所有权，共享词走运行时查询。 |
| `lib/beamlet_web/handles.ex` | `Beamlet.Web.Handles`；类型 `navigation/0`，`start_link/1`、`remember/1`、`fetch/1` | 模块/类型/函数说明既有已核：4096 条、1 小时空闲、每次 fetch 重核、绝不拥有 Agent、句柄非授权。 |
| `lib/beamlet_web/host.ex` | `Beamlet.Web.Host`；类型 `settings/0`，`configuration/1`、`start_link/1` | 模块/函数说明既有已核。**本轮修正**：`settings/0` 的 `@typedoc` 原为通用填充语，改为“含私有已解析目录的 Web 宿主策略”。 |
| `lib/beamlet_web/host/bootstrap.ex` | `Beamlet.Web.Host.Bootstrap`（隐藏） | 既有注释已核：仅启动时对受信 peers 顺序连接一次，浏览器事件无连接路径。 |
| `lib/beamlet_web/live/management_live.ex` | `Beamlet.Web.ManagementLive`；`render/1`、`node_results/1`、`runtime_reports/1`、`preset_results/1` | 模块说明与三个子组件说明既有已核。**本轮修正**：`render/1` 原说明与其他模块通用措辞重复，改为只读页面语义（范围/状态/上次观测/未知事实、无命令入口）。`handle_event/3` 仅 refresh 的守卫由模块说明覆盖。 |
| `lib/beamlet_web/live/management_reads.ex` | `Beamlet.Web.ManagementReads`；类型 `result/0`，`nodes/0` | 模块、类型、函数说明既有已核：32 目标上限、excluded、分别解释连接/就绪/新鲜度。私有 `resolve/1` 的“信任一次验证”注释既有且准确。 |
| `lib/beamlet_web/live/owned_call.ex` | `Beamlet.Web.OwnedCall`；`start/4`、`deliver/2`、`observe/4` | 模块与函数说明既有已核：有限调用者、杀死调用者≠取消业务、sink 消费后 ack、离开只清理观察。私有守护循环的既有注释准确。 |
| `lib/beamlet_web/live/workbench_commands.ex` | `Beamlet.Web.WorkbenchCommands`（隐藏） | 既有注释已核：私有解析留在调用者内；守护者按序报告身份/确认/输入/导航；不确定反馈不重发。`discover/0`、`create/3` 为隐藏模块接口，普通注释足够，不加 `@doc`。 |
| `lib/beamlet_web/live/workbench_live.ex` | `Beamlet.Web.WorkbenchLive` | 既有模块说明已核：代际/pending 隔离、替换快照、离开只退订。回调 `mount/3`、`handle_params/3`、`handle_info/2`、`handle_event/3` 由模块说明与模板呈现覆盖；私有 `observe/2`、`command/3` 的既有代码结构自明。 |
| `lib/beamlet_web/locale.ex` | `Beamlet.Web.Locale`；类型 `option/0`，`resolve/2`、`default/0`、`html_lang/1`、`options/2`、`path_for/2`、`on_mount/4`、`on_params/3` | 模块/类型/函数说明既有已核：查询→会话→配置→默认；有效查询写签名会话；语言只影响呈现。私有 `persist_param/2`、`session_value/1`、`uri_path/1` 为简单适配，无需说明。 |
| `lib/beamlet_web/presets.ex` | `Beamlet.Web.Presets`；类型 `preset/0`、`model/0`、`tool/0`、`environment/0`、`authority/0`、`entry/0`、`configuration/0`、`public_entry/0`、`public_entries/0`、`description/0`、`draft/0`、`resolved/0`，`start_link/1`、`describe/0,1`、`reset/1,2`、`resolve/1,2`、`configuration/3` | 模块说明既有已核：私有目录不可外泄。**本轮修正**：`preset/0` 的中文原写成“公开预设默认引用”，与私有条目语义不符，改为“受信私有目录中的预设条目”；`describe/1`、`reset/2`、`resolve/2` 原与进程版重复同一段文字，改为分别说明“纯函数、供启动校验/测试”。私有校验谓词（`model?/2`、`tool?/2`、`entries?/3`、`label?/1` 等）名字即契约，无需注释。 |
| `lib/beamlet_web/router.ex` | `Beamlet.Web.Router` | 既有模块说明已核：管线顺序、CSRF/源检查/CSP nonce、API 管线无路由。私有 `put_csp_nonce/2` 的既有注释已说明开发/生产差异，无需新增。 |
| `lib/beamlet_web/telemetry.ex` | `Beamlet.Web.Telemetry`；`start_link/1`、`metrics/0` | 既有模块/函数说明已核：当前周期测量为空、只提供度量定义、不持久保存轨迹。 |

## 3. 文档路径与核对结果（6 份）

| 文档 | 覆盖内容 | 本轮结果 |
| --- | --- | --- |
| `apps/beamlet_app_server/README_zh.md` | 职责/边界、显式启用、storage 与准入、peers/bootstrap、发布、根命令 | 既有已核；**本轮新增** `[English](README.md)` 导航。配置示例、`configuration/1` 无副作用示例、`Node.observation()` 的 `configured: false`、发布路径与 runtime 规则均与源码一致。 |
| `apps/beamlet_i18n/README_zh.md` | 运行时示例、语言规范化、词汇边界、五套目录所有权、语言优先级、命令 | 既有已核；**本轮新增** English 导航；改写 Gettext 段落：区分“现有 POT 的重复 `#:` 来源行”与“文档注释改变行号导致 `--check-up-to-date` 过期”，不再声称未验证的上游原因；把该检查移出“可通过命令”列表并说明原因。`iex` 示例已用 `mix run --no-start` 实测（默认 en 回退、`put(nil)`→zh_CN、`put("en-US")`→en）。 |
| `apps/beamlet_cli/README_zh.md` | 依赖/边界、启用与命令语法、Client API、会话与发布、语言、命令 | 既有已核；**本轮新增** English 导航；修正 watch 预算表述（预算从订阅后开始、控制调用与阻塞输出不受硬中断、超时不取消业务）；修正行输入表述（EOF 前不完整行保留、行内空格不裁剪）。语法/`identity_token` 示例已核对。 |
| `apps/beamlet_app_web/README_zh.md` | 职责、本地运行、示例目录、安全/会话/发布、语言、命令 | 既有已核；**本轮新增** English 导航；**修正根任务入口**：根 `mix setup` 与 `mix assets.deploy` 别名不存在，改为 `mix deps.get` + `mix phx.server`（开发 watchers 构建资源）与根可用的 `tailwind beamlet_web --minify`/`esbuild beamlet_web --minify`/`phx.digest` 顺序；Gettext 检查改为说明性段落。链接全部存在。 |
| `apps/beamlet_app_web/HOST_zh.md` | 启停策略、目录 schema、公开/私有投影、创建与不确定结果、导航与部署边界 | 既有已核；逐条对照 `Host.configuration/1`、`Presets.configuration/3`、`Presets.resolve/2`、`Agents.create/1`、`Handles`、`Agent` 五秒预算、`host.exs` 示例。未改。 |
| `apps/beamlet_app_web/WORKBENCH_zh.md` | 工作台流程、发现、创建、观察所有权、只读管理、语言、历史证据边界 | 既有已核；**本轮修正**诊断页链接描述：诊断页只提供页面级“回到工作台观察”链接，工作台活动卡才可深链到诊断；诊断页没有逐活动/逐错误深链接（源码未传 `diagnostic_handle`）。历史浏览器演练数字与 `WORKBENCH.md` 一致。 |

语言顺序：新增中文说明均放在既有英文之前；没有生成新的英文翻译，没有删除既有有效英文（仅去除被重复 `@doc` 覆盖的部分）。没有指向不存在的英文文件；四个 README 现已配对存在并可互链。

## 4. 明确的文档修正（源码依据）

1. **根目录任务入口**：根 `mix.exs` 只注册 `sobelow`/`bench` 别名；`mix help setup`、`mix help assets.deploy` 在仓库根均返回 “task could not be found”。Web README 已改用根可用的 `tailwind`/`esbuild`/`phx.digest` 任务（与应用 `assets.deploy` 别名内容相同），并说明别名只在应用目录注册。
2. **Gettext 检查**：`mix gettext.extract --check-up-to-date` 在仓库根与 `apps/beamlet_i18n` 均失败，报告共享 `default.pot`/`errors.pot` 过期；原因是文档注释改变了 `catalogue.ex` 等文件中 `gettext` 调用的行号，POT 以行号作为来源引用。现有 POT 另有重复 `#:` 行。未重新生成目录（父计划禁止），两处 README 已如实说明该检查不能算通过。
3. **诊断页链接**：`ManagementLive.render/1` 调用 `<.activities display={@display} pending={true} />`，未传 `diagnostic_handle`；`WorkbenchLive` 模板传了 `diagnostic_handle={@handle}`。WORKBENCH_zh 原“页面级/活动级链接可用”对诊断页不成立，已改。
4. **CLI watch 预算**：`do_watch/2` 在订阅成功后计算截止时间；`watch_events/4` 的 `after` 只约束 `receive`，`output/ack/subscribe/unsubscribe` 可超出预算，故“不是严格整调用墙钟上限”成立，但“不包含同步输出”不准确，已改写。
5. **CLI `create/2`**：直接委托 `Agent.start/2`，不存在 Web 的“导航/输入结果”，原说明误用 Web 措辞，已改。

## 5. 内部/隐藏边界与不加注的理由

- `*_application.ex`、`host/bootstrap.ex`、`workbench_commands.ex`：保持 `@moduledoc false`，只加普通注释说明启动时序、所有权与“无重试”。
- `Beamlet.Server.Bootstrap`、`Beamlet.Web.Host.Bootstrap`：`run/1` 是框架回调，行为由模块注释覆盖。
- 私有校验/解析谓词（`Presets.model?/2` 等、`Handles.expire/1`、`Locale.persist_param/2`、`Runner.finish/1`、`Session.dispatch/3` 子句）：函数名与相邻公开说明已表达边界；逐条注释会变成复述。
- LiveView 回调（`mount/3`、`handle_params/3`、`handle_info/2`、`handle_event/3`）、Plug 回调（`init/1`、`call/2`、`on_mount/4`）：由模块说明与模板可见行为覆盖；`@impl` 保留原样。
- CoreComponents 私有 `error/1`、JS 包装私有细节：属于组件内部实现，不扩大公共接口。
- 没有把任何隐藏函数改为公开，没有修改 `@doc false`/`@moduledoc false` 之外的可见性。

## 6. 验证记录（实际执行）

均在本机仓库根目录、`dev` 分支工作区执行；未提交、未切换分支。

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 开发编译 | `mix compile --warnings-as-errors` | 通过（exit 0）；修正后无重复 `@doc`/私有 `@doc` 警告 |
| 测试环境编译 | `MIX_ENV=test mix compile --warnings-as-errors` | 通过（exit 0），四个应用全部重编译 |
| i18n 测试 | `mix test apps/beamlet_i18n/test` | 15 passed |
| CLI 测试 | `mix test apps/beamlet_cli/test` | 25 passed，1 excluded |
| Server 测试 | `mix test apps/beamlet_app_server/test` | 15 passed，4 excluded |
| Web 测试 | `mix test apps/beamlet_app_web/test` | 73 passed，5 excluded |
| 格式（仅本组件文件） | `mix format --check-formatted <本组件 16 个改动 .ex>` | 通过 |
| 空白/冲突标记 | `git diff --check` | 通过（无输出） |
| 行为不变 AST | `/tmp/ast_compare2.exs`：`git show HEAD:<file>` 与工作区对比，忽略位置元数据与 `@doc/@moduledoc/@typedoc` | 40/40 identical，0 differing |
| 链接/锚点 | 自写 Python 检查六份中文文档的相对链接与标题锚点 | 全部存在，无断链 |
| 文档示例 | `mix run --no-start -e ...` 验证 i18n 示例；`Command.parse/1`、`identity_token/1` 由阅读与已知编码核对 | 与文档一致 |
| 任务可用性 | `mix help phx.server/tailwind/esbuild/phx.digest` | 根目录可用；`setup`、`assets.deploy` 不可用（已据此改文档） |
| Gettext 边界检查 | `mix gettext.extract --check-up-to-date`（根与 i18n 目录） | **失败**：POT 行号过期，见 §4.2；未生成/修改目录 |

测试中的 excluded 均为项目既有 tag（分布式/持久化等），非本次跳过。

## 7. 未执行与剩余缺口

- **未执行**：`mix credo --strict --all`、`mix dialyzer`、`mix sobelow`、完整 `mix test --seed 631927`、发布打包、命名节点/物理跨机、付费模型、浏览器/LiveView 端到端、部署验收。按父计划由集成阶段或相应环境执行；本记录不把它们算作通过。
- **POT 基线冲突**：任何文档注释插入都会移动 Gettext 调用行号，`--check-up-to-date` 因此必然报告过期。需要父/集成阶段决定是否批准单独重生成 POT（只改 `#:` 引用）或在验证中记录为已知非文案差异。本组件未改动任何 `.pot`/`.po`。
- **工具限制**：pi-lens 的单文件分析在本环境无法加载依赖/项目模块（`Gettext`、`Beamlet.Web`、`Phoenix.Component` 均报 “module … is not loaded”），并对未修改的 `use` 行给出 “Introduce IO.inspect” 的无效建议；实际编译（dev/test，`--warnings-as-errors`）全部通过，故未按该建议改动代码。属分析器环境问题，记录为未解决提示。
- **英文阶段**：未开始，未新增英文翻译；后续英文任务需以本中文基线逐项补齐。
- **未验证的文档声明**：部署脚本行为、`rpc/eval` 的实际用法、历史浏览器演练细节沿用既有英文专题，未在本次重新演练。

## 8. 与其他车道的边界

- 只改本组件拥有的 40 个 `.ex`、4 个 `README_zh.md`、`HOST_zh.md`、`WORKBENCH_zh.md`，以及本文件。
- 未改 `.heex`、`assets/js`、`priv/gettext`、`config/*.exs`、`mix.exs`、测试、依赖或历史记录。
- 未修改共享 `../10-19-bilingual-documentation/research/coverage.md`；其状态更新与 `verification.md` 归集成车道。
