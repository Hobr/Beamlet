defmodule Beamlet.Node.ClusterDistributedTest do
  use ExUnit.Case
  alias Beamlet.Node.Cluster
  @moduletag :distributed

  setup do
    assert Node.alive?()

    {:ok, peer, remote} =
      :peer.start_link(%{
        name: String.to_atom("cluster_#{System.unique_integer([:positive])}"),
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())],
        wait_boot: 10_000,
        shutdown: 3000
      })

    Process.unlink(peer)

    on_exit(fn ->
      if Process.alive?(peer) do
        :peer.call(peer, :sys, :resume, [:net_kernel])
        :peer.stop(peer)
      end
    end)

    %{peer: peer, remote: remote, name: Atom.to_string(remote)}
  end

  test "connect once and filter already connected trusted nodes without implicit discovery", %{
    remote: remote,
    name: name
  } do
    local = Atom.to_string(node())
    refute remote in Node.list(:connected)
    assert {:ok, [self_node]} = Cluster.connected([local, name])
    assert self_node == node()
    assert :ok = Cluster.connect(name, [name])
    assert {:ok, [^remote]} = Cluster.connected([name])
    assert {:ok, []} = Cluster.connected([])
    assert Node.disconnect(remote)
    assert {:ok, []} = Cluster.connected([name])
    refute remote in Node.list(:connected)
  end

  test "a stalled handshake has a bounded wait and no automatic retry", %{
    peer: peer,
    remote: remote,
    name: name
  } do
    assert :ok = :peer.call(peer, :sys, :suspend, [:net_kernel])
    started = System.monotonic_time(:millisecond)
    assert {:error, :unavailable} = Cluster.connect(name, [name])
    assert System.monotonic_time(:millisecond) - started < 7000
    refute remote in Node.list(:connected)
    assert :ok = :peer.call(peer, :sys, :resume, [:net_kernel])
  end
end
