import Config

# Trusted operator-owned Elixir code, never model input. Do not render errors from
# the reader or validators: they can contain file contents, paths or credentials.
result =
  try do
    path = System.get_env("BEAMLET_CONFIG")

    with true <- is_binary(path) and Path.type(path) == :absolute,
         [{:beamlet_daemon, settings}] <- Config.Reader.read!(path),
         {:ok, validated} <- Beamlet.Daemon.configuration(settings) do
      {:ok, Keyword.put(validated, :enabled, true)}
    else
      _ -> :invalid
    end
  rescue
    _ -> :invalid
  catch
    _, _ -> :invalid
  end

case result do
  {:ok, settings} ->
    config :beamlet_daemon, settings

  :invalid ->
    raise "invalid daemon configuration; BEAMLET_CONFIG must be an absolute trusted host config"
end
