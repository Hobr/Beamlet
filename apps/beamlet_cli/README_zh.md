# Beamlet CLI

> 语言状态：本页是当前维护的中文版本。本应用尚无英文 README，英文对照属于后续语言阶段；此处不链接尚不存在的文件。

终端交互宿主与 IEx 客户端。直接运行依赖为 Node、Agent、I18n、Gettext、Owl 与 Ucwidth；Runtime/Harness/Jason 是测试依赖。它不拥有 authority/executor，普通加载只启动空监督树，不读取 stdin。需要服务端先启动 authority，并为执行模型/工具准备 executor。每个 VM 仅一棵 Node 树，不能同时启用其他宿主。

## 启用与调用

源代码方式在启动前配置 `config :beamlet_cli, enabled: true, allowed_nodes: ["authority@host.internal"]`，再从根目录执行 `iex -S mix`，手动调用 `Beamlet.CLI.Runner.main()` 进入前台循环。远端互通要求受信节点名、命名 VM、匹配 cookie 与网络；只有显式 `connect` 尝试连接。配置文件是受信可执行 Elixir，不接受不可信上传。

```elixir
# 无网络、无业务副作用的语法与语言示例
{:ok, {:input, "a", "你好  世界"}} = Beamlet.CLI.Command.parse("input a 你好  世界")
"id64:dHdvIHdvcmRz" = Beamlet.CLI.Command.identity_token("two words")
"zh_CN" = Beamlet.CLI.Locale.normalize("zh-cn")
```

前台固定命令示例（先替换为部署实际允许的节点与 ID）：

```text
connect authority@host.internal
agents authority@host.internal
agents-page 2
attach authority@host.internal id64:dHdvIHdvcmRz a
input a 你好
status a
watch a 30000 128
stop a
detach a
quit
```

`agents-page` 遍历最近一次查询，每页八条，不重新查询；第二页仅在结果足够时有效。`complete` 描述查询范围而非原子集群清单。`attach` 不输入任务，别名保存精确 Ref，旧别名不会随同名 ID 替换。最多 128 个安全 ASCII 别名。创建命令 `create <authority> <absolute-options-file>` 读取唯一 `config :beamlet_cli, :agent_options, [...]`，其中选项必须含适合别名的 id、实际 model 等 Agent 参数；不是任意 eval 命令。

`Beamlet.CLI.Client` 提供 create/input/snapshot/status/stop/close/watch：已有有效 Ref 时可调用 `Client.input(ref, "你好")` 与 `Client.watch(ref, timeout: 30000, events: 128)`。watch 默认 5000ms/64 条，最大 60000ms/256 条；收到 done/error/stopped 返回快照，耗尽/失联/超时返回错误并退订。预算从订阅成功后开始计时，覆盖事件接收与输出耗时；订阅、确认、退订与阻塞输出本身不受硬中断，因此不是严格的整调用墙钟上限，超时也不取消业务工作。

## 会话与发布边界

行输入最多 65536 原始字节，以 LF 分隔；EOF 前的不完整行保留原文，行内及两侧空格不裁剪（由命令语法再分词）。非法 UTF-8/超限/读取错误退出 1，EOF 与 quit 退出 0。终端读取独占设备并恢复临时编码设置。detach、quit、EOF、watch 超时不关闭 Agent；stop 只停轮次，close 显式关闭且成功后移除同 Ref 别名。操作不自动重试，不承诺撤回外部副作用。

从根目录打包：`BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_cli`。产物位于 `_build/backend/prod/rel/beamlet_cli`；`bin/beamlet_cli start` 的定制入口才启动前台 Runner，rpc/eval 是控制工具。使用 Mix 自带 runtime.exs 与原生 RELEASE_NODE/RELEASE_COOKIE，CLI 闭包不含 Server/Web。运维见 [部署说明](../../scripts/deployment/README.md)。

## 语言

有效 `:locale` → `BEAMLET_LANG` → `:default_locale` → `zh_CN`。Runner 为当前进程安装一次，命令关键字不翻译。终端专用文案归本应用，公共词汇归 [I18n](../beamlet_i18n/README_zh.md)，不得复制 msgid。

## 开发与核验

以下命令均在仓库根目录执行。项目开发环境由 `flake.nix` 提供 Elixir 1.20 / OTP 29；先进入 `nix develop`，已有工具链也须满足根及各应用 Mix 要求。依赖尚未安装时先运行 `mix deps.get`。

```sh
mix compile --warnings-as-errors
mix test apps/beamlet_cli/test
mix format --check-formatted
git diff --check
```

完整质量检查由集成阶段执行；示例启动、发布及远程调用需要对应运行环境，不属于仅检查文档即可证明的部署验收。
