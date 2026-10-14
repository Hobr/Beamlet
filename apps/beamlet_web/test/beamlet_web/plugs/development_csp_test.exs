defmodule BeamletWeb.Plugs.DevelopmentCSPTest do
  use ExUnit.Case, async: true

  alias BeamletWeb.Plugs.DevelopmentCSP

  import Plug.Conn
  import Plug.Test

  test "an empty development allowlist leaves the policy unchanged" do
    connection = conn(:get, "/")
    assert DevelopmentCSP.call(connection, DevelopmentCSP.init(origins: [])) == connection
  end

  test "only configured HTTP(S) origins and their WebSocket equivalents are added" do
    connection =
      conn(:get, "/")
      |> put_resp_header(
        "content-security-policy",
        "script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; object-src 'none';"
      )

    options =
      DevelopmentCSP.init(origins: ["http://127.0.0.1:4007", "https://debug.example"])

    response = DevelopmentCSP.call(connection, options)
    assert [policy] = get_resp_header(response, "content-security-policy")
    assert policy =~ "script-src 'self' http://127.0.0.1:4007 https://debug.example;"

    assert policy =~
             "connect-src 'self' http://127.0.0.1:4007 ws://127.0.0.1:4007 https://debug.example wss://debug.example;"

    assert policy =~ "object-src 'none';"

    assert policy =~
             "style-src 'self' 'unsafe-inline' http://127.0.0.1:4007 https://debug.example;"

    refute policy =~ "script-src 'self' 'unsafe-inline'"
    refute policy =~ "unsafe-eval"
  end

  test "wildcards, paths, credentials, and injected directives are rejected" do
    for source <- [
          "*",
          "http://*.example",
          "http://debug.example/path",
          "http://user:password@debug.example",
          "http://debug.example?query=1",
          "http://debug.example#fragment",
          "http://debug.example;script-src",
          "http://debug.example 'unsafe-inline'",
          "data:text/javascript,alert(1)"
        ] do
      assert_raise ArgumentError, fn -> DevelopmentCSP.init(origins: [source]) end
    end
  end
end
