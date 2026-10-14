defmodule BeamletWeb.Plugs.CSPNonce do
  @moduledoc """
  Gives trusted server-rendered scripts a fresh nonce for each HTTP response.

  LiveDashboard consumes this assign for its inline configuration script.
  Ordinary application scripts remain external same-origin assets.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    nonce = :crypto.strong_rand_bytes(18) |> Base.encode64()
    [policy] = get_resp_header(conn, "content-security-policy")
    policy = String.replace(policy, "script-src 'self'", "script-src 'self' 'nonce-#{nonce}'")

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy)
  end
end
