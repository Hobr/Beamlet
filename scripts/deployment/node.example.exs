import Config

# Copy and edit on each host. This is trusted local code, not remote input.
# Authority and interaction nodes need no model credentials/workspace root.
config :beamlet_node, :boot,
  roles: [:authority],
  routes: %{
    "model" => %{id: "model", capability: "model-v1", claims: %{"native" => 1}},
    "tree" => %{
      id: "tree",
      capability: "read-v1",
      environment: "tree-v1",
      claims: %{"native" => 1}
    }
  }

# Executor replacement (keep roots/keys here, never in routes):
# config :beamlet_node, :boot,
#   roles: [:executor], pools: %{"native" => 4},
#   profiles: %{
#     "model" => %{type: :model, module: Beamlet.Harness.Models.OpenAICompatible,
#       capability: "model-v1", settings: %{base_url: "https://provider.example/v1",
#         model: "operator-selected-model", key_env: "BEAMLET_MODEL_KEY"}},
#     "tree" => %{type: :tool, module: Beamlet.Harness.Tools.WorkspaceRead,
#       capability: "read-v1", environment: "tree-v1",
#       settings: %{root: "/srv/beamlet/permitted", max_bytes: 65536}}
#   }
