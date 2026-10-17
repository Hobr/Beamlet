import Config

# Trusted executable operator-owned code. Restrict permissions to the operator.
config :beamlet_cli, allowed_nodes: ["authority@127.0.0.1"]
