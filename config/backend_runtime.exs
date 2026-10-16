import Config

# This file is copied into the Node release. The operator file is trusted Elixir
# configuration, owned by the deployment user; never accept it from a model.
config_path = System.fetch_env!("BEAMLET_CONFIG")

unless Path.type(config_path) == :absolute do
  raise "BEAMLET_CONFIG must be an absolute trusted config path"
end

for {app, settings} <- Config.Reader.read!(config_path) do
  config app, settings
end
