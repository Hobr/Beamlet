# umbrella 与**所有子应用**共享这一份运行时配置；某个应用需要不同
# 配置或依赖时，应把它移出 umbrella，而不是在子应用里另起配置入口。
#
# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :beamlet_app_web,
  namespace: Beamlet.Web,
  generators: [context_app: false]

# 产品文案语言：`zh_CN` 是 Web 与 CLI 的出厂默认，`en` 是另一个受支持目录。
# 词汇与语言规范化归 apps/beamlet_i18n；这里只给各界面默认值。
# Product copy locale. `zh_CN` is the default for Web and CLI; `en` is the other
# supported catalogue. See apps/beamlet_i18n.
config :beamlet_app_web, :default_locale, "zh_CN"
config :beamlet_cli, :default_locale, "zh_CN"

# Configures the endpoint
config :beamlet_app_web, Beamlet.Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: Beamlet.Web.ErrorHTML, json: Beamlet.Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: Beamlet.Web.PubSub,
  live_view: [signing_salt: "ltS2ELK+"]

# 资源构建 profile 名为 `beamlet_web`，与 Web release 名一致；
# 它不是 OTP 应用名 `beamlet_app_web`，调用 install_and_run/2 时要用前者。
# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  beamlet_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/beamlet_app_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  beamlet_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/beamlet_app_web", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Sample configuration:
#
#     config :logger, :default_handler,
#       level: :info
#
#     config :logger, :default_formatter,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#
import Config

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# 环境专用配置必须最后导入：它依赖前面的共享值，并且要能覆盖它们。
import_config "#{config_env()}.exs"
