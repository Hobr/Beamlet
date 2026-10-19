import Config

# 可信可执行 Elixir 代码，绝不是模型输出；把它的绝对路径传给 `create` 命令。
# 这里的确定性夹具不需要付费提供方或凭据；真实模型绑定需运维者自行选择。
# Trusted executable code, never model output. Pass its absolute path to create.
# Deterministic fixture needs no paid provider or credentials.
config :beamlet_cli,
  agent_options: [
    id: "demo",
    model: %{
      provider: "deterministic",
      config: %{"reply" => %{"kind" => "text", "content" => "hello", "calls" => []}}
    }
  ]
