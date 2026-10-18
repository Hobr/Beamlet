defmodule Beamlet.Web.BootstrapDistributedTest do
  use ExUnit.Case
  @moduletag :distributed

  setup do
    assert Node.alive?()
    previous = Application.get_all_env(:beamlet_app_web)
    :ok = Application.stop(:beamlet_app_web)

    {:ok, peer, remote} =
      :peer.start_link(%{
        name: String.to_atom("daemon_stalled_#{System.unique_integer([:positive])}"),
        connection: :standard_io,
        args: [~c"+S", ~c"2:2", ~c"-setcookie", Atom.to_charlist(Node.get_cookie())],
        wait_boot: 10_000,
        shutdown: 3000
      })

    Process.unlink(peer)
    assert :ok = :peer.call(peer, :sys, :suspend, [:net_kernel])

    on_exit(fn ->
      Application.stop(:beamlet_app_web)

      if Process.alive?(peer) do
        :peer.call(peer, :sys, :resume, [:net_kernel])
        :peer.stop(peer)
      end

      for {key, _} <- Application.get_all_env(:beamlet_app_web),
          do: Application.delete_env(:beamlet_app_web, key)

      Application.put_all_env(beamlet_app_web: previous)
      {:ok, _} = Application.ensure_all_started(:beamlet_app_web)
    end)

    name = Atom.to_string(remote)

    Application.put_env(:beamlet_app_web, :host,
      enabled: true,
      node: [roles: [:interaction, :authority, :executor]],
      allowed_nodes: [name],
      peers: [name]
    )

    started = System.monotonic_time(:millisecond)
    assert {:ok, _} = Application.ensure_all_started(:beamlet_app_web)
    assert System.monotonic_time(:millisecond) - started < 1000
    assert is_pid(Process.whereis(Beamlet.Agent.Registry))
    assert is_pid(Process.whereis(Beamlet.Runtime.ExecutorGateway))
    task = bootstrap_pid()
    # Observe actual linked task/controller/worker ownership while handshake is
    # blocked. Never resume infrastructure before all monitored processes exit.
    helpers = wait_helpers(task, 100)
    monitors = for pid <- helpers, do: {pid, Process.monitor(pid)}
    %{monitors: monitors, peer: peer, remote: remote}
  end

  test "startup deadline retires task and helpers while peer remains suspended", %{
    monitors: monitors,
    remote: remote
  } do
    for {pid, ref} <- monitors do
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 6500
      refute Process.alive?(pid)
    end

    refute remote in Node.list(:connected)
    assert is_pid(Process.whereis(Beamlet.Agent.Registry))
    assert is_pid(Process.whereis(Beamlet.Runtime.ExecutorGateway))
    assert bootstrap_pid() == nil
  end

  test "host loss retires startup task and connection helpers before peer resumes", %{
    monitors: monitors,
    remote: remote
  } do
    host = Process.whereis(Beamlet.Web.Host)
    host_monitor = Process.monitor(host)
    Process.exit(host, :kill)
    assert_receive {:DOWN, ^host_monitor, :process, ^host, :killed}, 1500

    for {pid, ref} <- monitors do
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1500
      refute Process.alive?(pid)
    end

    refute remote in Node.list(:connected)
  end

  defp bootstrap_pid do
    Enum.find_value(Supervisor.which_children(Beamlet.Web.Host), fn
      {Beamlet.Web.Host.Bootstrap, pid, _, _} when is_pid(pid) -> pid
      _ -> nil
    end)
  end

  defp wait_helpers(_task, 0), do: flunk("connection helper ownership was not observed")

  defp wait_helpers(task, n) do
    helpers = linked([task], [Process.whereis(Beamlet.Web.Host)], [])

    if length(helpers) >= 3 do
      helpers
    else
      Process.sleep(10)
      wait_helpers(task, n - 1)
    end
  end

  defp linked([], _excluded, seen), do: seen

  defp linked([pid | rest], excluded, seen) do
    if pid in excluded or pid in seen do
      linked(rest, excluded, seen)
    else
      case Process.info(pid, :links) do
        {:links, links} -> linked(rest ++ Enum.filter(links, &is_pid/1), excluded, [pid | seen])
        nil -> linked(rest, excluded, seen)
      end
    end
  end
end
