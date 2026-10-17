defmodule Beamlet.Web.ManagementDistributedTest do
  use Beamlet.Web.ConnCase
  import Phoenix.LiveViewTest
  alias Beamlet.Web.ManagementReads
  @moduletag :distributed

  test "real trusted peer facts, disconnected target and source timeout are distinct", %{
    conn: conn
  } do
    assert Node.alive?()
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    {:ok, peer, remote} =
      :peer.start_link(%{
        name: String.to_atom("management_#{System.unique_integer([:positive])}"),
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())] ++ paths,
        wait_boot: 10_000,
        shutdown: 3000
      })

    Process.unlink(peer)
    on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)
    :ok = :peer.call(peer, Beamlet.Web.HostPeer, :boot, [])
    assert Node.connect(remote)
    original = Application.get_env(:beamlet_web, :host, [])
    Application.put_env(:beamlet_web, :host, allowed_nodes: [Atom.to_string(remote)])
    on_exit(fn -> Application.put_env(:beamlet_web, :host, original) end)
    {:ok, view, _} = live(conn, ~p"/admin/nodes")

    eventually(fn ->
      html = render(view)
      assert html =~ "connected at read entry"
      assert html =~ "authority, executor"
      assert html =~ "Configured: true"
      assert html =~ Atom.to_string(remote)
    end)

    :ok = :peer.call(peer, :sys, :suspend, [Beamlet.Node.Routes])
    started = System.monotonic_time(:millisecond)
    assert {:ok, %{reads: reads}} = ManagementReads.nodes()
    assert System.monotonic_time(:millisecond) - started < 6500
    assert Enum.any?(reads, fn {:ok, r} -> r.failures[remote] == :timeout end)
    :ok = :peer.call(peer, :sys, :resume, [Beamlet.Node.Routes])
    assert Node.disconnect(remote)
    view |> element("#refresh") |> render_click()

    eventually(fn ->
      html = render(view)
      assert html =~ "disconnected"
      assert html =~ "partial / unknown"
    end)
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
