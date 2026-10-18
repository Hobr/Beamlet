# Execution Plan: Web/CLI i18n

## Preconditions

- [x] 用户确认本计划（PRD/design/implement）后执行 `task.py start`。
- [x] 阅读 `web-host.md`、`web-workbench.md`、`web-management.md`、`backend-release.md`、`directory-structure.md`、`quality-guidelines.md`、`error-handling.md`。

## Ordered work

- [x] 新建 umbrella 应用 `beamlet_i18n`：`Beamlet.I18n` backend、`Beamlet.I18n.Locale`（normalize/default/options 单一实现）、`priv/gettext` 共享 catalogue；Web/CLI 的 `mix.exs` 增加依赖（CLI 另加 `gettext`），确认 `mix.lock` 未变。
- [x] 按归属规则划分文案：共用状态/原因/动作/表头进共享集，Web 专有进 `Beamlet.Web.Gettext`，CLI 专有进 `Beamlet.CLI.Gettext`；三份 msgid 集合保持互斥。共享 msgid 在 `Beamlet.I18n.Catalogue` 声明一次，调用方用 `Beamlet.I18n.gettext/2` 运行时函数。
- [x] 共享 locale 规范化接入 Web 与 CLI，删除任何重复的 normalize 实现；默认仍为 `zh_CN`。
- [x] 从根目录运行 `mix gettext.extract --merge`（recursive，一次覆盖所有 app）；确认共享 msgid 落在 `beamlet_i18n/priv`、各自 msgid 落在本 app `priv`。
- [x] 加源码扫描测试：`Beamlet.I18n.gettext/dgettext` 中出现的每个字面量必须存在于共享 catalogue；共享 msgid 不得出现在 app catalogue。
- [x] CLI：新增 `Beamlet.CLI.Gettext` 与 `Beamlet.CLI.Locale`（复用 `Beamlet.I18n.Locale`，仅保留配置/环境解析）。
- [x] CLI：`Runner` 启动时 `put_locale`；`Renderer`（help、errors、discovery header/rows、status/nodes 表头、`(none)`、提示语）与 `Session` 提示接入 `gettext`；命令语法/列宽/边界/退出码不变。
- [x] Web：新增 `Beamlet.Web.Locale`（normalize、resolve、plug、LiveView `on_mount`），接入 `:browser` pipeline；默认 `zh_CN`，会话与 `?locale=` 覆盖，非法值回退。
- [x] Web：布局加中英切换（保留当前路径），无客户端持久化；保持 CSP/CSRF 与主题脚本不变。
- [x] Web：`WorkbenchLive`、`management_live.ex`、`observation_components.ex`、`layouts.ex` 全部用户可见文案改为 `gettext`；`core_components` 的 `errors` 域补 zh_CN。
- [x] 生成/整理 `default.pot`、`errors.pot`，写 `en` 与 `zh_CN` 的 `.po`（zh 全覆盖；en 可留空 msgstr）。
- [x] 若 child-dir `mix gettext.extract` 被 umbrella `:only` 不一致阻塞：优先统一 Web/CLI 的 `beamlet_runtime`（CLI 另含 `beamlet_harness`）声明并验证闭包不变；否则加根级提取任务。不得为了跑任务而牺牲依赖语义。
- [x] 测试：现有英文断言显式设 `en` 并在 `on_exit` 复原；新增默认中文、切换/回退、CLI 配置/环境优先级、PO 完整性与关键页面无残留英文的断言。
- [x] 文档：更新 `WORKBENCH.md`/`HOST.md` 与 CLI 帮助的环境变量说明，记录默认语言与切换方式；同步 `quality-guidelines` 的提取/合并命令。

## Validation

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test apps/beamlet_web/test
mix test apps/beamlet_cli/test
mix test --seed 631927
mix credo --strict
mix sobelow
mix dialyzer --no-check   # 复用既有 PLT，不刷新
git diff --check
```

命名分布式测试与本改动无关，除非 manifest/闭包变动；若改动 Web/CLI manifest，需确认 `mix.lock` 未变并复跑受影响 release 闭包检查。


## Closure and drift gates

```bash
mix gettext.extract --check-up-to-date   # 必须在根目录运行
mix test apps/beamlet_web/test apps/beamlet_cli/test
bash scripts/deployment/check-release.sh  # 仅在 manifest/闭包变动时，需先构建 backend release
```

- 若 runner 没有预构建的 backend release，记录为未执行并说明原因，不得声称闭包已验证。
- 共享/自有 msgid 互斥、zh 全覆盖、`--check-up-to-date` 三项必须有自动化断言。

## Rollback

回滚 i18n 提交；业务、协议、安全与存储均未改变。若只回滚 Web 侧，保留 CLI 目录仍可编译（两套 catalogue 独立）。

## Review gates

- 默认语言必须实际为中文（不是仅配置存在）。
- 不得出现未翻译的 `nil`/term 或半中半英的断裂句子。
- 不得改变 CLI 输出结构与边界、Web 事件/状态语义。