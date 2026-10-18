defmodule Beamlet.Web.HostDistributedTest do
  use ExUnit.Case
  @moduletag :distributed
  alias Beamlet.Web.{Agents, Handles, Presets}

  test "interaction-only host bootstraps trusted authority once and reattaches surviving remote Agent" do
    assert Node.alive?()
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    {:ok, peer, remote} =
      :peer.start_link(%{
        name: String.to_atom("web_authority_#{System.unique_integer([:positive])}"),
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())] ++ paths,
        wait_boot: 10_000,
        shutdown: 3000
      })

    Process.unlink(peer)
    previous = Application.get_env(:beamlet_app_web, :host)
    :ok = Application.stop(:beamlet_app_web)

    on_exit(fn ->
      Application.stop(:beamlet_app_web)
      if Process.alive?(peer), do: :peer.stop(peer)

      if previous,
        do: Application.put_env(:beamlet_app_web, :host, previous),
        else: Application.delete_env(:beamlet_app_web, :host)

      {:ok, _} = Application.ensure_all_started(:beamlet_app_web)
    end)

    assert :ok = :peer.call(peer, Beamlet.Web.HostPeer, :boot, [])
    name = Atom.to_string(remote)

    c =
      Config.Reader.read!(Path.expand("../../priv/examples/host.exs", __DIR__))[:beamlet_app_web][
        :host
      ][:catalogue]

    c = %{c | authorities: %{"local" => %{title: "Remote", target: name}}}

    settings = [
      enabled: true,
      node: [roles: [:interaction]],
      allowed_nodes: [name],
      peers: [name],
      catalogue: c
    ]

    Application.put_env(:beamlet_app_web, :host, settings)
    assert {:ok, _} = Application.ensure_all_started(:beamlet_app_web)
    wait_ready(remote, 200)
    assert Process.whereis(Beamlet.Agent.Registry) == nil
    {:ok, d} = Presets.reset("basic")

    assert {:created, %{ref: ref, navigation: {:ok, handle}, input: {:accepted, _}}} =
             Agents.create(%{d | "task" => "hello"})

    assert ref.authority == remote
    assert :ok = Beamlet.Agent.subscribe(ref)
    wait_done(ref)
    assert :ok = Beamlet.Agent.unsubscribe(ref)
    assert {:ok, %{agents: [descriptor], complete: true}} = Agents.discover([remote])
    assert {:ok, ^ref} = Handles.fetch(handle)
    :ok = Application.stop(:beamlet_app_web)
    assert {:ok, %{status: :done}} = Beamlet.Agent.snapshot(ref)
    assert {:ok, _} = Application.ensure_all_started(:beamlet_app_web)
    assert {:error, :stale_handle} = Handles.fetch(handle)
    assert {:ok, fresh} = Agents.attach(descriptor)
    assert fresh != handle
    assert {:ok, ^ref} = Handles.fetch(fresh)
    assert {:ok, [^descriptor]} = Beamlet.Agent.list(remote)
    assert :ok = Beamlet.Agent.close(ref)
  end

  defp wait_ready(_, 0), do: flunk("remote capacity not ready")

  defp wait_ready(remote, n) do
    if ready?(remote) do
      :ok
    else
      Process.sleep(20)
      wait_ready(remote, n - 1)
    end
  end

  defp ready?(remote) do
    with {:ok, %{nodes: nodes}} <- Beamlet.Node.observe([remote]),
         {:ok, %{reports: reports}} <- get_in(nodes, [remote, :runtime]) do
      Enum.any?(reports, &(&1[:execution_ready] == true and &1.node == remote))
    else
      _ -> false
    end
  end

  defp wait_done(ref) do
    receive do
      {:beamlet_agent, ^ref, seq, {:snapshot, snapshot}} ->
        Beamlet.Agent.ack(ref, seq)

        if snapshot.status == :done,
          do: assert(snapshot.final == "Local example response"),
          else: wait_done(ref)
    after
      5000 -> flunk("remote completion absent")
    end
  end
end
