defmodule Beamlet.Web.WorkbenchDistributedTest do
  use ExUnit.Case
  use Beamlet.Web, :verified_routes
  @endpoint Beamlet.Web.Endpoint
  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Beamlet.Web.{Handles, WorkbenchCommands}
  @moduletag :distributed

  test "remote external creation is discovered exactly and connection loss clears observation", %{
    conn: conn
  } do
    assert Node.alive?()
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    {:ok, peer, remote} =
      :peer.start_link(%{
        name: String.to_atom("workbench_remote_#{System.unique_integer([:positive])}"),
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())] ++ paths,
        wait_boot: 10_000,
        shutdown: 3000
      })

    Process.unlink(peer)
    on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)
    assert :ok = :peer.call(peer, Beamlet.Web.HostPeer, :boot, [])
    assert Node.connect(remote)
    original_host = Application.get_env(:beamlet_web, :host, [])
    Application.put_env(:beamlet_web, :host, allowed_nodes: [Atom.to_string(remote)])
    on_exit(fn -> Application.put_env(:beamlet_web, :host, original_host) end)
    start_supervised!(Handles)

    {:ok, ref} =
      Beamlet.Agent.start(remote,
        id: "external-remote",
        model: %{
          provider: "deterministic",
          config: %{"reply" => %{"kind" => "text", "content" => "remote reply", "calls" => []}},
          credentials: %{}
        }
      )

    Application.put_env(:beamlet_web, :host, allowed_nodes: [])
    assert remote in Node.list(:connected)
    assert {:ok, %{agents: untrusted}} = WorkbenchCommands.discover()
    refute Enum.any?(untrusted, &(&1.authority == remote))
    Application.put_env(:beamlet_web, :host, allowed_nodes: [Atom.to_string(remote)])

    {:ok, view, _} = live(conn, ~p"/")
    eventually(fn -> assert has_element?(view, "li button", "external-remote") end)
    view |> element("li button", "external-remote") |> render_click()
    eventually(fn -> assert render(view) =~ "Agent workspace" end)
    assert :peer.call(peer, :erlang, :is_process_alive, [ref.pid])
    Node.disconnect(remote)

    eventually(fn ->
      assert render(view) =~ "Observation unavailable"
      assert render(view) =~ "Display absent / omitted"
    end)

    GenServer.stop(view.pid)
    assert {:ok, %{status: :idle}} = :peer.call(peer, Beamlet.Agent, :snapshot, [ref])
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, n) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      receive do
      after
        20 -> eventually(fun, n - 1)
      end
  end
end
