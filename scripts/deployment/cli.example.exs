import Config

# 应用设置示例：在共享配置或打包的 runtime.exs 中改写它。
# Mix 不会发现或自动加载示例文件；`allowed_nodes` 必须是可信部署配置。
# Application settings example for shared config or bundled runtime.exs.
# Mix does not discover or automatically load this example.
config :beamlet_cli, allowed_nodes: ["authority@127.0.0.1"]
