defmodule Beamlet.Harness.HTTPTest do
  use ExUnit.Case, async: false
  alias Beamlet.Harness.{Catalogue, Context}
  alias Beamlet.Harness.Models.OpenAICompatible, as: Model
  alias Beamlet.Harness.Tools.WorkspaceRead

  defp call(id),
    do: %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => "workspace_read", "arguments" => ~s({"path":"a"})}
    }

  defp reply(message, finish),
    do: %{
      "choices" => [
        %{"finish_reason" => finish, "message" => Map.put(message, "role", "assistant")}
      ]
    }

  setup do
    System.put_env("HARNESS_FIXTURE_KEY", "fixture-only-key")
    on_exit(fn -> System.delete_env("HARNESS_FIXTURE_KEY") end)
    {:ok, catalogue} = Catalogue.new([WorkspaceRead.descriptor()])

    %{
      request: %{
        messages: [%{"role" => "user", "content" => "fixture prompt"}],
        catalogue: catalogue
      }
    }
  end

  defp fixture(response, opts \\ []) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    pid = spawn_link(fn -> serve(listener, owner, response, opts) end)

    on_exit(fn ->
      Process.exit(pid, :kill)
      :gen_tcp.close(listener)
    end)

    %{
      base_url: "http://127.0.0.1:#{port}/v1",
      model: "fixture",
      key_env: "HARNESS_FIXTURE_KEY",
      allow_local_http: true,
      timeout_ms: 150
    }
  end

  defp serve(listener, owner, response, opts) do
    {:ok, socket} = :gen_tcp.accept(listener, 2000)
    {:ok, initial} = :gen_tcp.recv(socket, 0, 1000)
    {headers, body} = read_headers(socket, initial)
    [_, length] = Regex.run(~r/content-length: (\d+)/i, headers)
    body = read_body(socket, body, String.to_integer(length))
    send(owner, {:wire, headers, body})

    if opts[:timeout] do
      receive do
        :finish -> :ok
      after
        350 -> :ok
      end
    else
      :gen_tcp.send(socket, response)
    end

    :gen_tcp.close(socket)
    # Any client retry or redirect would open a second connection here.
    case :gen_tcp.accept(listener, 250) do
      {:ok, second} ->
        send(owner, :second_request)
        :gen_tcp.close(second)

      _ ->
        :ok
    end

    send(owner, :fixture_done)
  end

  defp read_headers(socket, data) do
    case :binary.split(data, "\r\n\r\n") do
      [h, b] ->
        {h, b}

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 1000)
        read_headers(socket, data <> more)
    end
  end

  defp read_body(_, body, size) when byte_size(body) >= size, do: body

  defp read_body(socket, body, size) do
    {:ok, more} = :gen_tcp.recv(socket, 0, 1000)
    read_body(socket, body <> more, size)
  end

  defp response(body, status \\ 200, extra \\ ""),
    do:
      "HTTP/1.1 #{status} Fixture\r\nconnection: close\r\ncontent-length: #{byte_size(body)}\r\n#{extra}\r\n#{body}"

  test "actual socket validates base path, auth, request and preserves complete call IDs", %{
    request: request
  } do
    settings =
      fixture(
        response(
          Jason.encode!(
            reply(%{"content" => nil, "tool_calls" => [call("opaque-id")]}, "tool_calls")
          )
        )
      )

    assert {:ok, %{calls: [%{id: "opaque-id", arguments: %{"path" => "a"}}]}} =
             Model.complete(request, settings, %Context{})

    assert_receive {:wire, headers, body}
    assert headers =~ "POST /v1/chat/completions HTTP/1.1"
    assert String.downcase(headers) =~ "authorization: bearer fixture-only-key"
    assert String.downcase(headers) =~ "accept-encoding: identity"

    assert %{
             "stream" => false,
             "n" => 1,
             "model" => "fixture",
             "tools" => [_],
             "messages" => [%{"content" => "fixture prompt"}]
           } = Jason.decode!(body)

    assert_receive :fixture_done, 1000
    refute_received :second_request
  end

  for status <- [302, 307, 429, 500] do
    test "status #{status} does not retry or follow", %{request: request} do
      settings =
        fixture(response("error body secret", unquote(status), "location: /elsewhere\r\n"))

      assert {:error, :http_status} = Model.complete(request, settings)
      assert_receive :fixture_done, 1000
      refute_received :second_request
    end
  end

  test "timeout makes only one attempt", %{request: request} do
    settings = fixture("", timeout: true)
    assert {:error, _} = Model.complete(request, settings)
    assert_receive :fixture_done, 1500
    refute_received :second_request
  end

  test "all-status and chunked overflow, invalid JSON and encoding fail closed", %{
    request: request
  } do
    huge =
      Jason.encode!(reply(%{"content" => "valid prefix must never be accepted"}, "stop")) <>
        String.duplicate(" ", 1_048_577)

    chunked =
      "HTTP/1.1 200 OK\r\nconnection: close\r\ntransfer-encoding: chunked\r\n\r\n#{Integer.to_string(byte_size(huge), 16)}\r\n#{huge}\r\n0\r\n\r\n"

    for {wire, error} <- [
          {response(huge), :response_limit},
          {response(huge, 500), :response_limit},
          {chunked, :response_limit},
          {response("{"), :invalid_json},
          {response(<<255>>), :invalid_json},
          {response("{}", 200, "content-encoding: gzip\r\n"), :unsupported_encoding}
        ] do
      assert {:error, ^error} = Model.complete(request, fixture(wire))
      assert_receive :fixture_done, 1000
      refute_received :second_request
    end
  end

  test "TLS handshake failure never falls back to HTTP", %{request: request} do
    settings = %{base_url: "", model: "fixture", key_env: "HARNESS_FIXTURE_KEY", timeout_ms: 150}
    # Use a dedicated TCP listener that closes during TLS handshake.
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 1000)
        :gen_tcp.recv(socket, 0, 1000)
        :gen_tcp.close(socket)
        result = :gen_tcp.accept(listener, 250)
        :gen_tcp.close(listener)
        result
      end)

    assert {:error, _} =
             Model.complete(request, %{settings | base_url: "https://127.0.0.1:#{port}"})

    assert {:error, :timeout} = Task.await(task, 2000)
  end

  test "history requires complete ordered tool results before another model request", %{
    request: request
  } do
    assistant = %{
      "role" => "assistant",
      "content" => nil,
      "tool_calls" => [call("one"), call("two")]
    }

    result = fn id ->
      %{"role" => "tool", "tool_call_id" => id, "content" => "bounded observation"}
    end

    for tail <- [[assistant], [assistant, result.("two"), result.("one")], [result.("one")]] do
      assert {:error, :invalid_messages} =
               Model.complete(%{request | messages: request.messages ++ tail}, %{
                 base_url: "http://localhost:1",
                 model: "fixture",
                 key_env: "HARNESS_FIXTURE_KEY",
                 allow_local_http: true
               })
    end

    settings = fixture(response(Jason.encode!(reply(%{"content" => "joined"}, "stop"))))

    assert {:ok, %{content: "joined"}} =
             Model.complete(
               %{
                 request
                 | messages: request.messages ++ [assistant, result.("one"), result.("two")]
               },
               settings
             )

    assert_receive :fixture_done, 1000
  end

  test "unsafe profiles fail before transport", %{request: request} do
    for base <- [
          "http://example.com/v1",
          "https://user:pass@example.com",
          "https://example.com?query=secret",
          "https://example.com#fragment"
        ] do
      assert {:error, :invalid_profile} =
               Model.complete(request, %{
                 base_url: base,
                 model: "fixture",
                 key_env: "HARNESS_FIXTURE_KEY"
               })
    end
  end

  test "self-signed TLS certificate is rejected with peer verification", %{request: request} do
    dir = Path.join(System.tmp_dir!(), "harness-tls-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    cert = Path.join(dir, "cert.pem")
    key = Path.join(dir, "key.pem")

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-nodes",
          "-keyout",
          key,
          "-out",
          cert,
          "-days",
          "1",
          "-subj",
          "/CN=localhost",
          "-addext",
          "subjectAltName=DNS:localhost"
        ],
        stderr_to_stdout: true
      )

    {:ok, listener} =
      :ssl.listen(0, [
        :binary,
        active: false,
        certfile: String.to_charlist(cert),
        keyfile: String.to_charlist(key),
        ip: {127, 0, 0, 1}
      ])

    on_exit(fn -> :ssl.close(listener) end)
    {:ok, {_, port}} = :ssl.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listener, 2000)
        handshake = :ssl.handshake(socket, 2000)
        :ssl.close(socket)
        {handshake, :ssl.transport_accept(listener, 250)}
      end)

    settings = %{
      base_url: "https://localhost:#{port}/v1",
      model: "fixture",
      key_env: "HARNESS_FIXTURE_KEY",
      timeout_ms: 1000
    }

    assert {:error, :transport} = Model.complete(request, settings)
    assert {{:error, _}, {:error, :timeout}} = Task.await(server, 3000)
  end

  test "socket rejects invalid semantic replies without returning any executable sibling", %{
    request: request
  } do
    for wire <- [
          reply(%{"content" => "no", "refusal" => "refused"}, "stop"),
          reply(%{"content" => nil, "tool_calls" => [call("a")]}, "length"),
          reply(%{"content" => nil, "tool_calls" => [call("a"), call("a")]}, "tool_calls"),
          reply(%{"content" => nil, "tool_calls" => [call("a"), %{}]}, "tool_calls"),
          %{"choices" => []}
        ] do
      assert {:error, _} = Model.complete(request, fixture(response(Jason.encode!(wire))))
      assert_receive :fixture_done, 1000
      refute_received :second_request
    end
  end

  test "unsupported settings and request actions are rejected before transport", %{
    request: request
  } do
    settings = %{
      base_url: "http://localhost:1",
      model: "fixture",
      key_env: "HARNESS_FIXTURE_KEY",
      allow_local_http: true
    }

    for extra <- [
          %{temperature: 0.5},
          %{max_tokens: 1},
          %{verify: :verify_none},
          %{timeout_ms: 0}
        ] do
      assert {:error, :invalid_profile} = Model.complete(request, Map.merge(settings, extra))
    end

    assert {:error, :invalid_request} = Model.complete(Map.put(request, :actions, []), settings)

    for url <- [
          "https://",
          "https://example.com:0",
          "https://example.com/a b",
          "https://example.com/" <> <<0>>
        ] do
      assert {:error, :invalid_profile} = Model.complete(request, %{settings | base_url: url})
    end
  end

  test "global Req defaults cannot inject plugins, parameters or adapters", %{request: request} do
    previous = Application.fetch_env(:req, :default_options)

    Application.put_env(:req, :default_options,
      plugins: [fn _ -> raise "must not run" end],
      params: [injected: "bad"]
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:req, :default_options, value)
        :error -> Application.delete_env(:req, :default_options)
      end
    end)

    assert {:ok, %{content: "controlled"}} =
             Model.complete(
               request,
               fixture(response(Jason.encode!(reply(%{"content" => "controlled"}, "stop"))))
             )

    assert_receive {:wire, headers, _}
    assert headers =~ "POST /v1/chat/completions HTTP/1.1"
    assert_receive :fixture_done, 1000
    refute_received :second_request
  end
end
