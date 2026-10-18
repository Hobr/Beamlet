import Config

# Application settings example: adapt in shared config or bundled runtime.exs.
# Mix does not discover or automatically load this example.
# Boot needs no model credentials. Agent creation supplies one immutable binding.
config :beamlet_daemon,
  allowed_nodes: [],
  peers: [],
  node: [
    # Omit roles for [:authority, :executor]; either only selection is also supported.
    roles: [:authority],
    model_providers: %{"openai-compatible" => Beamlet.Harness.Models.OpenAICompatible},
    routes: %{
      "tree" => %{
        id: "tree",
        capability: "read-v1",
        environment: "tree-v1",
        claims: %{"native" => 1}
      }
    }
  ]

# Executor replacement: register trusted adapters; keep Tool roots/settings local.
# User credentials arrive only with dedicated model invocations, never via key_env.
# config :beamlet_daemon, node: [
#   roles: [:executor], pools: %{"native" => 4},
#   model_providers: %{"openai-compatible" => Beamlet.Harness.Models.OpenAICompatible},
#   profiles: %{
#     "tree" => %{type: :tool, module: Beamlet.Harness.Tools.WorkspaceRead,
#       capability: "read-v1", environment: "tree-v1",
#       settings: %{root: "/srv/beamlet/permitted", max_bytes: 65536}}
#   }
#   ]
