defmodule Beamlet.CLI.ReleaseIntegrationTest do
  use ExUnit.Case
  alias Beamlet.CLI.Client, as: CLI
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Harness.Tools.WorkspaceRead
  @moduletag :distributed

  test "three independent role VMs use real HTTP adapter and executor workspace" do
    assert Node.alive?()

    peers =
      for role <- [:interaction, :authority, :executor], into: %{} do
        {:ok, peer, remote} =
          :peer.start_link(%{
            name: String.to_atom("release_#{role}_#{System.unique_integer([:positive])}"),
            connection: :standard_io,
            wait_boot: 10_000,
            shutdown: 3000,
            args:
              [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())] ++
                Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
          })

        Process.unlink(peer)
        on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)
        {role, {peer, remote}}
      end

    for {_, {peer, remote}} <- peers, {_, {_, other}} <- peers, remote != other do
      assert :peer.call(peer, Node, :connect, [other])
    end

    root = Path.join(System.tmp_dir!(), "release_marker_#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.write!(Path.join(root, "marker"), "executor-marker")
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    server = spawn_link(fn -> serve(listener, owner, 2) end)

    on_exit(fn ->
      Process.exit(server, :kill)
      :gen_tcp.close(listener)
    end)

    {cp, executor} = peers.executor
    assert nil == :peer.call(cp, System, :get_env, ["RELEASE_FIXTURE_KEY"])

    profiles = %{
      "tree" => %{
        type: :tool,
        module: Beamlet.Harness.Tools.WorkspaceRead,
        capability: "workspace",
        environment: "fixture-tree",
        settings: %{root: root}
      }
    }

    for {role, {peer, _}} <- peers do
      opts = [roles: [role], limits: [refresh_ms: 20, expiry_ms: 500]]

      opts =
        if role == :executor,
          do:
            opts ++
              [
                profiles: profiles,
                pools: %{"native" => 2}
              ],
          else: opts

      assert :ok = :peer.call(peer, Beamlet.CLI.TestBoot, :boot, [opts])
    end

    {ap, _} = peers.interaction
    {bp, authority} = peers.authority

    assert :ok =
             :peer.call(bp, Beamlet.CLI.TestBoot, :barrier, ["model.provider:openai-compatible"])

    assert nil == :peer.call(cp, Process, :whereis, [Beamlet.Agent.Registry])
    assert nil == :peer.call(bp, Process, :whereis, [Beamlet.Runtime.ExecutorGateway])

    {:ok, catalogue} =
      Catalogue.new([WorkspaceRead.descriptor()])

    options = [
      id: "http-loop",
      model: %{
        provider: "openai-compatible",
        config: %{
          "base_url" => "http://127.0.0.1:#{port}/v1",
          "model" => "fixture",
          "allow_local_http" => true
        },
        credentials: %{"api_key" => "local-fixture-only"},
        placement: %{allowed_nodes: [executor], claims: %{"native" => 1}}
      },
      catalogue: catalogue,
      tools: %{
        "workspace_read" => %{
          id: "tree",
          capability: "workspace",
          environment: "fixture-tree",
          allowed_nodes: [executor]
        }
      }
    ]

    assert {:ok, ref} = :peer.call(ap, CLI, :create, [authority, options])
    assert ref.authority == authority
    assert {:ok, _} = :peer.call(ap, CLI, :input, [ref, "read marker"])
    assert {:ok, %{status: :done, final: "verified"}} = CLI.watch(ref, timeout: 10_000)
    assert_receive {:http_request, 2, first}, 1000
    assert first["model"] == "fixture"
    assert_receive {:http_request, 1, second}, 1000
    [tool] = Enum.filter(second["messages"], &(&1["role"] == "tool"))
    assert tool["tool_call_id"] == "marker-call"
    assert tool["content"] =~ "executor-marker"
    fence = :peer.call(cp, Beamlet.CLI.TestBoot, :capacity_fence, [])
    assert :ok = :peer.call(bp, Beamlet.CLI.TestBoot, :fresh_capacity, [executor, fence])
    later_server = spawn_link(fn -> serve(listener, owner, 1) end)
    on_exit(fn -> Process.exit(later_server, :kill) end)
    {:ok, _} = CLI.input(ref, "later turn")
    assert {:ok, %{status: :done, final: "verified"}} = CLI.watch(ref, timeout: 10_000)
    assert_receive {:http_request, 1, later}, 1000
    assert later["model"] == "fixture"
    fence = :peer.call(cp, Beamlet.CLI.TestBoot, :capacity_fence, [])
    assert :ok = :peer.call(bp, Beamlet.CLI.TestBoot, :fresh_capacity, [executor, fence])
    assert :ok = CLI.close(ref)

    # Same adapter, but no eligible workspace: the model sees an explicit failure,
    # never the marker from a different environment.
    again = spawn_link(fn -> serve(listener, owner, 2) end)
    on_exit(fn -> Process.exit(again, :kill) end)

    wrong_options =
      options
      |> Keyword.put(:id, "wrong-tree")
      |> Keyword.update!(:tools, fn tools ->
        put_in(tools, ["workspace_read", :environment], "absent-tree")
      end)

    {:ok, wrong} = :peer.call(ap, CLI, :create, [authority, wrong_options])
    {:ok, _} = CLI.input(wrong, "wrong tree")
    assert {:ok, %{status: :done}} = CLI.watch(wrong, timeout: 10_000)
    assert_receive {:http_request, 2, _}, 1000
    assert_receive {:http_request, 1, wrong_request}, 1000
    [failure] = Enum.filter(wrong_request["messages"], &(&1["role"] == "tool"))
    assert failure["content"] =~ "no_target"
    refute failure["content"] =~ "executor-marker"

    held =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        _request = headers(socket, "")
        send(owner, :http_held)

        receive do
          :release -> :gen_tcp.close(socket)
        after
          5000 -> :gen_tcp.close(socket)
        end
      end)

    on_exit(fn -> Process.exit(held, :kill) end)
    {:ok, _} = CLI.input(wrong, "stop while HTTP waits")
    assert_receive :http_held, 3000
    assert :ok = CLI.stop(wrong)
    assert {:ok, %{status: :stopped}} = CLI.watch(wrong)
    send(held, :release)
    :peer.stop(cp)
    {:ok, _} = CLI.input(wrong, "executor gone")
    assert {:ok, %{status: :error}} = CLI.watch(wrong, timeout: 10_000)
    assert :ok = CLI.close(wrong)
    refute_receive {:http_request, _, _}, 100
  end

  defp serve(_listener, _owner, 0), do: :ok

  defp serve(listener, owner, count) do
    {:ok, socket} = :gen_tcp.accept(listener, 10_000)
    data = headers(socket, "")
    [head, body] = :binary.split(data, "\r\n\r\n")
    [_, length] = Regex.run(~r/content-length: (\d+)/i, head)
    request = body(socket, body, String.to_integer(length)) |> Jason.decode!()
    true = String.contains?(String.downcase(head), "authorization: bearer local-fixture-only")
    false = String.contains?(inspect(request), "local-fixture-only")
    send(owner, {:http_request, count, request})

    message =
      if count == 2 do
        %{
          "role" => "assistant",
          "content" => nil,
          "tool_calls" => [
            %{
              "id" => "marker-call",
              "type" => "function",
              "function" => %{"name" => "workspace_read", "arguments" => ~s({"path":"marker"})}
            }
          ]
        }
      else
        %{"role" => "assistant", "content" => "verified"}
      end

    reply =
      Jason.encode!(%{
        "choices" => [
          %{
            "finish_reason" => if(count == 2, do: "tool_calls", else: "stop"),
            "message" => message
          }
        ]
      })

    :ok =
      :gen_tcp.send(
        socket,
        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(reply)}\r\nconnection: close\r\n\r\n" <>
          reply
      )

    :gen_tcp.close(socket)
    serve(listener, owner, count - 1)
  end

  defp headers(socket, data) do
    if String.contains?(data, "\r\n\r\n"),
      do: data,
      else:
        (
          {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
          headers(socket, data <> more)
        )
  end

  defp body(_socket, data, size) when byte_size(data) >= size, do: data

  defp body(socket, data, size) do
    {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
    body(socket, data <> more, size)
  end
end
