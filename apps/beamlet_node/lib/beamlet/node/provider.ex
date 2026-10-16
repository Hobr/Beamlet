defmodule Beamlet.Node.Provider do
  alias Beamlet.Harness.Tools.WorkspaceRead

  @moduledoc "Executor-local profile ownership. Provider loss couples Runtime teardown before fresh readiness."
  use GenServer
  def start_link(profiles), do: GenServer.start_link(__MODULE__, profiles, name: __MODULE__)
  @impl true
  def init(profiles) do
    if Enum.all?(profiles, fn {_, p} -> ready?(p) end),
      do: {:ok, profiles},
      else: {:stop, :provider_unavailable}
  end

  defp ready?(%{module: WorkspaceRead, settings: settings}) do
    match?({:ok, _}, WorkspaceRead.validate_root(settings[:root])) and
      Map.keys(settings) -- [:root, :max_bytes] == [] and
      valid_read_limit?(Map.get(settings, :max_bytes, 65_536))
  end

  defp ready?(%{module: Beamlet.Harness.Models.OpenAICompatible, settings: settings}) do
    with %{base_url: base, model: model, key_env: env} <- settings,
         true <- is_binary(base) and is_binary(model) and is_binary(env),
         true <-
           Map.keys(settings) -- [:base_url, :model, :key_env, :timeout_ms, :allow_local_http] ==
             [],
         true <- valid_url?(base, Map.get(settings, :allow_local_http, false)),
         true <- byte_size(model) in 1..256 and String.valid?(model),
         true <- is_boolean(Map.get(settings, :allow_local_http, false)),
         true <- valid_timeout?(Map.get(settings, :timeout_ms, 5000)) do
      valid_key?(System.get_env(env))
    else
      _ -> false
    end
  end

  defp ready?(_), do: true

  defp valid_read_limit?(limit), do: is_integer(limit) and limit in 1..65_536
  defp valid_timeout?(timeout), do: is_integer(timeout) and timeout in 1..60_000

  defp valid_key?(key),
    do: is_binary(key) and byte_size(key) in 1..4096 and not String.contains?(key, ["\r", "\n"])

  defp valid_url?(base, local) do
    uri = URI.parse(base)

    valid_url_text?(base) and valid_address?(uri, local) and
      uri.userinfo == nil and uri.query == nil and uri.fragment == nil
  end

  defp valid_url_text?(base),
    do: String.valid?(base) and not String.contains?(base, ["\\", <<0>>, "\r", "\n", " "])

  defp valid_address?(uri, local) do
    scheme =
      uri.scheme == "https" or
        (local == true and uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost", "::1"])

    scheme and is_binary(uri.host) and uri.host != "" and uri.port in 1..65_535
  end
end
