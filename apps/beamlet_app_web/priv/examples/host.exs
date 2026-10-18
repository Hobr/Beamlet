# Trusted, explicit startup example. Import in config/dev.exs after reviewing it.
import Config

config :beamlet_app_web, :host,
  enabled: true,
  node: [roles: [:interaction, :authority, :executor]],
  catalogue: %{
    models: %{
      "local" => %{
        title: "Deterministic local model",
        binding: %{
          provider: "deterministic",
          config: %{
            "reply" => %{"kind" => "text", "content" => "Local example response", "calls" => []}
          },
          credentials: %{}
        }
      }
    },
    authorities: %{"local" => %{title: "This VM", target: :local}},
    default_authority: "local",
    presets: %{"basic" => %{title: "Local example", model: "local", tools: []}}
  }
