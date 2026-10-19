# Beamlet Web

> 语言状态：本页是当前维护的中文版本。本应用尚无英文 README，英文对照属于后续语言阶段；此处不链接尚不存在的文件。

Phoenix/LiveView 界面宿主：任务创建、精确活实例观察，以及节点/预设/诊断只读管理。后端直接依赖 Node、Agent、Actions、Harness、I18n；Runtime 是测试依赖。界面依赖 Phoenix/HTML/LiveView、Bandit、Gettext、Jason、telemetry metrics/poller 与构建资源工具；开发工具只在开发环境启用。业务库不反向依赖 Phoenix。

## 本地运行

先从仓库根目录运行 `mix deps.get` 安装依赖，再执行 `mix phx.server`；开发 watchers 会安装并运行 esbuild/tailwind 构建资源，然后浏览本地开发端口 4000。默认 Endpoint 可用但 Host 关闭，目录为空，无法创建实例。需要本地确定性示例时，审阅后在 `config/dev.exs` 显式加入 `import_config "../apps/beamlet_app_web/priv/examples/host.exs"`，重启服务；该示例启用三个角色、basic 预设与无外部网络/工具的确定性模型。保持其他宿主禁用。

```elixir
# 仅在上述示例已启用的 VM 内；这里只读/解析，不提交业务
public = Beamlet.Web.Presets.describe()
{:ok, draft} = Beamlet.Web.Presets.reset("basic")
{:ok, private} = Beamlet.Web.Presets.resolve(draft)
# private 含实际绑定，必须仅留在服务端，不输出到页面、日志或会话
```

实际创建使用工作台或 `Beamlet.Web.Agents.create(Map.put(draft, "task", "你好"))`，分别处理 created/create_unknown/rejected。创建是有副作用的显式动作，不能因导航或反馈失败重试。完整配置与适配 API 见 [宿主说明](HOST_zh.md)，路由、生命周期及管理页见 [工作台说明](WORKBENCH_zh.md)。

## 安全、状态与发布

句柄仅为 VM 临时导航，不提供授权；共享部署需受信网络/运维认证与核心权限边界。会话 cookie 签名但不默认加密，只保存非敏感语言偏好，不保存 Ref、绑定或凭据。当前界面只消费有限实时上下文，不宣称完整持久历史、重放或恢复。已有持久化能力归核心/Node，本界面没有数据库或在线配置修改入口。

生产 Web 由根 release `beamlet_web` 打包；需 SECRET_KEY_BASE，资源 profile 仍名为 beamlet_web（不是 OTP app 名 beamlet_app_web）。根目录按顺序执行 `MIX_ENV=prod mix compile`、`MIX_ENV=prod mix tailwind beamlet_web --minify`、`MIX_ENV=prod mix esbuild beamlet_web --minify`、`MIX_ENV=prod mix phx.digest`，最后 `MIX_ENV=prod mix release beamlet_web`。后三条与应用的 `assets.deploy` 别名内容一致；别名只在应用目录注册，因此从根目录直接调用同名任务。运行参数/端口见 [部署说明](../../scripts/deployment/README.md)，本批未执行部署。保持 CSP nonce、CSRF、origin 检查、转义及开发工具隔离。

语言默认 zh_CN，支持 en；查询/签名会话优先于 default_locale。公共词汇与语言规范化归 [I18n](../beamlet_i18n/README_zh.md)，本应用目录仅拥有 Web 专用文案。

## 开发与核验

以下命令均在仓库根目录执行。项目开发环境由 `flake.nix` 提供 Elixir 1.20 / OTP 29；先进入 `nix develop`，已有工具链也须满足根及各应用 Mix 要求。依赖尚未安装时先运行 `mix deps.get`。

```sh
mix compile --warnings-as-errors
mix test apps/beamlet_app_web/test
mix sobelow
mix format --check-formatted
git diff --check
```

`mix gettext.extract --check-up-to-date` 只检查已有目录；任何文档注释改变 Gettext 调用行号后，它会报告 POT 过期（现有 POT 还带有 Gettext 1.0.2 的重复来源行），属工具与基线状态而非文案差异，不能算作通过。本阶段不生成或修改产品文案目录；确需重生成时须先获批准并单独审阅差异。

完整质量检查由集成阶段执行；示例启动、发布及远程调用需要对应运行环境，不属于仅检查文档即可证明的部署验收。
