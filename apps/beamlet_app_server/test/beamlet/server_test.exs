defmodule Beamlet.ServerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  setup do
    previous = Application.get_all_env(:beamlet_app_server)
    :ok = Application.stop(:beamlet_app_server)

    on_exit(fn ->
      Application.stop(:beamlet_app_server)

      for {key, _} <- Application.get_all_env(:beamlet_app_server),
          do: Application.delete_env(:beamlet_app_server, key)

      Application.put_all_env(beamlet_app_server: previous)
      {:ok, _} = Application.ensure_all_started(:beamlet_app_server)
    end)

    :ok
  end

  test "shared runtime configuration activates only the selected release host" do
    previous = System.get_env("RELEASE_NAME")

    on_exit(fn ->
      if previous,
        do: System.put_env("RELEASE_NAME", previous),
        else: System.delete_env("RELEASE_NAME")
    end)

    runtime = Path.expand("../../../../config/runtime.exs", __DIR__)

    for name <- ["beamlet_server", "beamlet_cli", "beamlet_web"] do
      System.put_env("RELEASE_NAME", name)
      config = Config.Reader.read!(runtime, env: :test)

      assert get_in(config, [:beamlet_app_server, :enabled]) ==
               if(name == "beamlet_server", do: true)

      assert get_in(config, [:beamlet_cli, :enabled]) == if(name == "beamlet_cli", do: true)

      assert get_in(config, [:beamlet_app_web, :host, :enabled]) ==
               if(name == "beamlet_web", do: true)

      assert get_in(config, [:beamlet_app_web, Beamlet.Web.Endpoint, :server]) ==
               if(name == "beamlet_web", do: true)
    end

    System.delete_env("RELEASE_NAME")
    assert Config.Reader.read!(runtime, env: :test) == []
  end

  test "production backend runtime needs no Web secret; Web and source runs still do" do
    previous_name = System.get_env("RELEASE_NAME")
    previous_secret = System.get_env("SECRET_KEY_BASE")

    on_exit(fn ->
      for {key, value} <- [{"RELEASE_NAME", previous_name}, {"SECRET_KEY_BASE", previous_secret}] do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    System.delete_env("SECRET_KEY_BASE")
    runtime = Path.expand("../../../../config/runtime.exs", __DIR__)

    for name <- ["beamlet_server", "beamlet_cli"] do
      System.put_env("RELEASE_NAME", name)
      config = Config.Reader.read!(runtime, env: :prod)
      refute Keyword.has_key?(config, :beamlet_app_web)
    end

    for name <- ["beamlet_web", nil] do
      if name, do: System.put_env("RELEASE_NAME", name), else: System.delete_env("RELEASE_NAME")

      assert_raise RuntimeError, ~r/SECRET_KEY_BASE is missing/, fn ->
        Config.Reader.read!(runtime, env: :prod)
      end
    end
  end

  test "authority-only limits reject at preflight without starting children" do
    for limits <- [
          [refresh_ms: 0],
          [refresh_ms: 3_600_001],
          [operation_bytes: 1023],
          [operation_bytes: 262_145],
          [unknown: 1],
          :bad,
          nil,
          {:refresh_ms, 20},
          %{"refresh_ms" => 20},
          [refresh_ms: "bad"],
          "PRIVATE_LIMIT_SENTINEL",
          [1],
          [{:refresh_ms, 20} | :bad]
        ] do
      options = [roles: [:authority], limits: limits]

      assert {:error, :invalid_server_configuration} =
               Beamlet.Server.configuration(node: options)

      assert Process.whereis(Beamlet.Node.Routes) == nil
      assert Process.whereis(Beamlet.Runtime.Directory) == nil
      assert Process.whereis(Beamlet.Agent.Registry) == nil
    end
  end

  test "ordinary application startup is opt-in and has no role or connection effects" do
    connected = Node.list(:connected)
    assert {:ok, _} = Application.ensure_all_started(:beamlet_app_server)
    assert Supervisor.which_children(Beamlet.Server.Supervisor) == []
    assert Process.whereis(Beamlet.Node) == nil
    assert Process.whereis(Beamlet.Agent.Registry) == nil
    assert Process.whereis(Beamlet.Runtime.ExecutorGateway) == nil
    assert Node.list(:connected) == connected
  end

  test "same code starts default and only trees without workspace or user credentials" do
    for {options, authority, executor} <- [
          {[], true, true},
          {[roles: [:authority]], true, false},
          {[roles: [:executor]], false, true}
        ] do
      Application.put_all_env(beamlet_app_server: [enabled: true, node: options])
      assert {:ok, _} = Application.ensure_all_started(:beamlet_app_server)
      assert is_pid(Process.whereis(Beamlet.Node))
      assert is_pid(Process.whereis(Beamlet.Agent.Registry)) == authority
      assert is_pid(Process.whereis(Beamlet.Node.Provider)) == executor
      assert is_pid(Process.whereis(Beamlet.Runtime.ExecutorGateway)) == executor
      :ok = Application.stop(:beamlet_app_server)
      assert Process.whereis(Beamlet.Node) == nil
    end
  end

  test "invalid host and delegated Node configuration reject before any role starts" do
    invalid = [
      [node: [roles: []]],
      [node: [roles: [:interaction]]],
      [node: [roles: [:authority, :interaction]]],
      [node: [roles: [:authority, :authority]]],
      [node: [roles: [:unknown]]],
      [node: [{:roles, [:authority]} | :bad]],
      [node: [roles: [:authority], roles: [:executor]]],
      [node: [model_providers: %{"bad" => String}]],
      [node: [pools: %{"bad" => -1}]],
      [enabled: :yes],
      [enabled: true, enabled: false],
      [unknown: "secret-sentinel"],
      [allowed_nodes: ["bad name"]],
      [allowed_nodes: ["a@localhost" | :bad]],
      [peers: ["a@localhost"]],
      [allowed_nodes: ["a@localhost"], peers: ["a@localhost", "a@localhost"]],
      [allowed_nodes: ["a@localhost"], peers: ["a@localhost" | :bad]],
      [allowed_nodes: List.duplicate("a@localhost", 33)],
      [node: :bad]
    ]

    for settings <- invalid do
      assert {:error, :invalid_server_configuration} = Beamlet.Server.configuration(settings)

      unless Keyword.keys(settings) != Enum.uniq(Keyword.keys(settings)) do
        Application.put_all_env(beamlet_app_server: Keyword.put_new(settings, :enabled, true))
        assert {:error, _} = Application.ensure_all_started(:beamlet_app_server)
      end

      assert Process.whereis(Beamlet.Node) == nil
      assert Process.whereis(Beamlet.Agent.Registry) == nil

      for {key, _} <- Application.get_all_env(:beamlet_app_server),
          do: Application.delete_env(:beamlet_app_server, key)
    end
  end

  test "bounded trusted peer set is accepted and failed connection keeps local service alive" do
    allowed = for n <- 1..32, do: "server_#{n}@127.0.0.1"
    assert {:ok, _} = Beamlet.Server.configuration(allowed_nodes: allowed, peers: allowed)

    log =
      capture_log(fn ->
        Application.put_all_env(
          beamlet_app_server: [enabled: true, allowed_nodes: [hd(allowed)], peers: [hd(allowed)]]
        )

        assert {:ok, _} = Application.ensure_all_started(:beamlet_app_server)
        wait_bootstrap(100)
        assert is_pid(Process.whereis(Beamlet.Agent.Registry))
        assert is_pid(Process.whereis(Beamlet.Runtime.ExecutorGateway))
      end)

    assert log =~ "server startup peer 1: unavailable"
    refute log =~ hd(allowed)
  end

  defp wait_bootstrap(0), do: flunk("startup peer task did not terminate")

  defp wait_bootstrap(n) do
    if Enum.any?(Supervisor.which_children(Beamlet.Server.Supervisor), fn {id, _, _, _} ->
         id == Beamlet.Server.Bootstrap
       end) do
      Process.sleep(10)
      wait_bootstrap(n - 1)
    end
  end
end
