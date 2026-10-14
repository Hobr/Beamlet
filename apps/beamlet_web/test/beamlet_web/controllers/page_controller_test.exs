defmodule BeamletWeb.PageControllerTest do
  use BeamletWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "A workspace for durable agents."
    assert html =~ ~s(href="/components")
    assert html =~ ~s(/assets/css/app.css)
    assert html =~ ~s(/assets/js/app.js)
    assert html =~ ~s(data-phx-theme="system")
    assert html =~ ~s(data-phx-theme="light")
    assert html =~ ~s(data-phx-theme="dark")
    assert html =~ "pc-card"
    assert html =~ "csrf-token"
    refute html =~ "daisyui"
  end
end
