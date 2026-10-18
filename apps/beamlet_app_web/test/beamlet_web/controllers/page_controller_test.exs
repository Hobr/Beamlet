defmodule Beamlet.Web.PageControllerTest do
  use Beamlet.Web.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "What would you like to do?"
  end

  test "GET / authorizes inline scripts with a CSP nonce", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    [policy] = get_resp_header(conn, "content-security-policy")

    assert policy =~ "default-src 'self'"
    assert policy =~ "object-src 'none'"
    assert policy =~ "frame-ancestors 'self'"
    assert [_, nonce] = Regex.run(~r/script-src 'self' 'nonce-([^']+)'/, policy)
    assert byte_size(Base.decode64!(nonce)) == 16
    assert html =~ ~s(<script nonce="#{nonce}">)
    refute policy =~ "'unsafe-eval'"
    refute policy =~ "127.0.0.1:4007"
    refute policy =~ "script-src 'self' 'unsafe-inline'"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "GET / generates a fresh CSP nonce for each response", %{conn: conn} do
    first = get(conn, ~p"/")
    second = get(conn, ~p"/")

    assert Map.fetch!(first.assigns, :csp_nonce) != Map.fetch!(second.assigns, :csp_nonce)
  end
end
