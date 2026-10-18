# Web 与 CLI 文案中英双语（默认中文）

## Goal and Source

为用户可见文案接入 Gettext，提供英文与简体中文两种语言，默认显示中文。范围包括 Web 工作台、只读管理页与 CLI 输出；不改变任何业务语义、安全边界或状态机。

## Requirements

- I1：Web 全部产品文案（工作台、创建表单、工作区、活动/检查器、管理页、导航、状态与提示）走 Gettext，英文为 msgid，提供 `zh_CN` 与 `en` 两套翻译。
- I2：CLI 全部用户可见输出（help、错误、发现/身份表、状态表、节点表、会话提示）走 Gettext，同样两种语言。
- I3：默认语言为简体中文；未做任何选择时 Web 页面与 CLI 输出均为中文。
- I4：可显式切换语言：Web 通过会话/查询参数切换并在后续页面保持；CLI 通过受信配置或环境变量选择。切换只影响文案，不影响 Agent/Node/Runtime 行为。
- I5：翻译缺失不得崩溃或输出 msgid 之外的占位符；缺失时安全回退（英文 msgid），不得出现 `nil`、函数或原始 term。
- I6：不引入新的持久化（无数据库、无浏览器 transcript）；语言选择是会话级 UI 偏好，非业务数据。
- I8：翻译按**共享集 + 各自集**组织：两端共用的通用文案（状态词、错误原因、通用动作/表头、locale 规范化与默认值）只维护一份共享翻译；Web/CLI 各自只保留仅本面使用的文案。同一 msgid 不得在两处重复定义。
- I7：既有安全语义保持不变：CSP/CSRF/转义、错误渲染、私有配置/凭据不进页面；测试与静态检查仍须通过。

## Acceptance Criteria

- [x] IA1/I1,I3：默认（无 locale 会话）打开 `/`、`/agents/new`、工作区与三个管理页，主要标题/按钮/状态均为中文；`en` 时为英文。
- [x] IA2/I2,I3：CLI 默认输出中文；显式选择英文时输出英文；两者语义与退出码一致。
- [x] IA3/I4：Web 切换到英文后同会话后续页面保持英文，切回中文同样生效；非法/未知 locale 安全回退到默认中文。
- [x] IA4/I5：两套 `.po` 覆盖全部已提取 msgid；缺失翻译回退英文且不泄漏内部 term；错误路径同样本地化。
- [x] IA5/I6,I7：无数据库/持久化新增；CSP/CSRF/转义/错误页回归通过；`mix format`、警告即错误编译、Web 与 CLI 测试、Credo、Sobelow 通过。

## Out of Scope

- 第三种语言、按用户/租户的偏好存储、账号体系。
- 数据库文案、日志文案、内部错误原因 atom 的业务重命名。
- Phoenix 自带 HTTP 状态短语（404/500）的替换，除非随 `errors` 域一并提供且不改变响应语义。
- 改变 CLI 命令语法、输出结构（列/顺序/边界）或任何业务行为。

## Translation ownership

| 归属 | 内容 | 位置 |
| --- | --- | --- |
| 共享集 | 状态/原因词、通用动作与表头、locale 规范化、默认语言 | 新 umbrella 应用 `beamlet_i18n`（`Beamlet.I18n` backend + `priv/gettext`） |
| Web 自有 | 工作台/管理页专有标题、说明、表单标签与服务器反馈 | `apps/beamlet_web/priv/gettext`（`Beamlet.Web.Gettext`） |
| CLI 自有 | help 文本、表格专有表头、终端会话提示 | `apps/beamlet_cli/priv/gettext`（`Beamlet.CLI.Gettext`） |

判定规则：一个 msgid 若会被两端同时使用，必须放共享集；只在单端出现的不要放共享集。

## Dependencies

复用已有的 `Beamlet.Web.Gettext`、`priv/gettext/errors.po` 与 Web 内 `gettext` 依赖；CLI 新增 `gettext` 依赖。与已归档的 Web 交付无冲突。