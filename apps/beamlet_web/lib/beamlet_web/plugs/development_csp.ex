defmodule BeamletWeb.Plugs.DevelopmentCSP do
  @moduledoc """
  Adds explicitly configured development-tool origins to the browser CSP.

  Production and test leave this list empty. Origins must be HTTP(S) origins,
  not paths, wildcards, or arbitrary CSP expressions.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts) do
    Enum.map(Keyword.fetch!(opts, :origins), fn origin ->
      case URI.new(origin) do
        {:ok,
         %URI{scheme: scheme, host: host, path: path, userinfo: nil, query: nil, fragment: nil} =
             uri}
        when scheme in ["http", "https"] and is_binary(host) and host != "" and path in [nil, ""] ->
          if String.contains?(host, ["*", ";", "'", " "]) do
            raise ArgumentError, "development CSP sources must be explicit HTTP(S) origins"
          end

          websocket = %{uri | scheme: if(scheme == "https", do: "wss", else: "ws")}
          {URI.to_string(uri), URI.to_string(websocket)}

        _ ->
          raise ArgumentError, "development CSP sources must be explicit HTTP(S) origins"
      end
    end)
  end

  @impl true
  def call(conn, []), do: conn

  def call(conn, origins) do
    [policy] = get_resp_header(conn, "content-security-policy")
    scripts = Enum.map_join(origins, " ", &elem(&1, 0))

    connections =
      Enum.map_join(origins, " ", fn {http, websocket} -> http <> " " <> websocket end)

    policy =
      policy
      |> String.replace("script-src 'self';", "script-src 'self' " <> scripts <> ";")
      |> String.replace(
        "style-src 'self' 'unsafe-inline';",
        "style-src 'self' 'unsafe-inline' " <> scripts <> ";"
      )
      |> String.replace("connect-src 'self';", "connect-src 'self' " <> connections <> ";")

    put_resp_header(conn, "content-security-policy", policy)
  end
end
