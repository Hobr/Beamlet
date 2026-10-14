defmodule BeamletWeb.PageControllerTest do
  use BeamletWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "A workspace for durable agents."
    assert html =~ ~s(href="/components")
    assert html =~ ~s(/assets/css/app.css)
    assert html =~ ~s(/assets/js/app.js)
    assert html =~ ~s(/assets/js/theme.js)
    assert LazyHTML.from_document(html) |> LazyHTML.query("script:not([src])") |> Enum.empty?()
    assert html =~ ~s(data-phx-theme="system")
    assert html =~ ~s(data-phx-theme="light")
    assert html =~ ~s(data-phx-theme="dark")
    assert html =~ "pc-card"
    assert html =~ "csrf-token"
    refute html =~ "daisyui"
  end

  test "trusted inline script nonces are unpredictable and never reused", %{conn: conn} do
    first = get(conn, ~p"/")
    second = first |> recycle() |> get(~p"/")
    nonce = first.assigns.csp_nonce
    assert byte_size(Base.decode64!(nonce)) == 18
    refute nonce == second.assigns.csp_nonce
    assert [policy] = get_resp_header(first, "content-security-policy")
    assert policy =~ "'nonce-#{nonce}'"
  end

  test "browser responses enforce a restrictive CSP", %{conn: conn} do
    for path <- [~p"/", ~p"/components"] do
      response = conn |> recycle() |> get(path)
      assert html_response(response, 200)
      assert [policy] = get_resp_header(response, "content-security-policy")
      assert policy =~ "default-src 'self'"
      assert policy =~ "script-src 'self'"
      assert policy =~ "script-src-attr 'none'"
      assert policy =~ "object-src 'none'"
      assert policy =~ "frame-ancestors 'none'"
      assert policy =~ "form-action 'self'"
      refute policy =~ "unsafe-eval"
      refute policy =~ "127.0.0.1:4007"
    end
  end
end
