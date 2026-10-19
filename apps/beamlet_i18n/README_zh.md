# Beamlet I18n

> 语言状态：本页是当前维护的中文版本。本应用尚无英文 README，英文对照属于后续语言阶段；此处不链接尚不存在的文件。

仅依赖 Gettext 的叶应用，拥有 Web/CLI 共用文案、封闭状态/原因词汇、语言规范化与默认值；无 Application 回调，不启动 Node、数据库或界面。

## 运行时使用

从仓库根目录 `iex -S mix` 启动后：

```elixir
"zh_CN" = Beamlet.I18n.Locale.normalize("zh-cn")
"en" = Beamlet.I18n.Locale.put("en-US")
"running" = Beamlet.I18n.gettext("running")
"timeout" = Beamlet.I18n.dgettext("errors", "timeout")
"custom" = Beamlet.I18n.Vocabulary.status(:custom)
"zh_CN" = Beamlet.I18n.Locale.put(nil)
```

支持 zh/zh-cn/zh_CN/cn 与 en/en-us/en_US（忽略大小写及两侧空白）；未知 normalize 返回 nil，canonicalize/put 回退 zh_CN。put 修改当前进程的 Gettext 语言，同时影响共享与界面后端，不修改整个 VM。Vocabulary 只查询 Catalogue 声明的词，未知 atom 转字符串、其他值原样返回；它不是任意数据的安全序列化器。

## 目录所有权

共享词仅在 `Beamlet.I18n.Catalogue` 用提取宏声明，界面通过本后端运行时 gettext/dgettext 查询；不要在 Web/CLI 导入第二套共享提取宏。单界面专用文案仍用其自己的 Gettext 后端。共享 default/errors、Web default/errors、CLI default 五套 msgid 集合须互斥；每个 msgid 恰有一个所有者。Catalogue.declare 只供提取，不在运行时调用。

目录在 `priv/gettext`，zh_CN 须覆盖所有提取词且译文非空，en 可保留空 msgstr 并回退英文 msgid。新增翻译工作在根目录运行 `mix gettext.extract --merge` 后审阅归属；本次中文技术文档任务不改产品词条。现有 POT 中可见重复的 `#:` 来源行（Gettext 1.0.2 的提取产物），文档任务不手动整理。

Web 语言优先级为有效 ?locale= → 会话 → default_locale → zh_CN，使用完整页面链接写入签名会话。CLI 为 :locale → BEAMLET_LANG → :default_locale → zh_CN，Runner 读输入前安装一次。语言只影响显示，命令词、协议值、业务 ID 与配置键不翻译。

## 开发与核验

以下命令均在仓库根目录执行。项目开发环境由 `flake.nix` 提供 Elixir 1.20 / OTP 29；先进入 `nix develop`，已有工具链也须满足根及各应用 Mix 要求。依赖尚未安装时先运行 `mix deps.get`。

```sh
mix compile --warnings-as-errors
mix test apps/beamlet_i18n/test
mix format --check-formatted
git diff --check
```

`mix gettext.extract --check-up-to-date` 只检查已有目录；文档注释改变 Gettext 调用行号后，它会报告 POT 过期，属已知基线与工具状态而非文案差异，不能算作通过。重生成 POT/PO 不在本阶段范围。

完整质量检查由集成阶段执行；示例启动、发布及远程调用需要对应运行环境，不属于仅检查文档即可证明的部署验收。
