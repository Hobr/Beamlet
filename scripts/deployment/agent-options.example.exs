import Config

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
