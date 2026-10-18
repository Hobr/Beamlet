defmodule Beamlet.Web.ManagementLiveTest do
  use Beamlet.Web.ConnCase
  import Phoenix.LiveViewTest
  alias Beamlet.Web.{Handles, ManagementLive, ManagementReads, OwnedCall, Presets}

  setup do
    original = Application.get_env(:beamlet_app_web, :host, [])
    Application.put_env(:beamlet_app_web, :host, allowed_nodes: ["missing@localhost"])
    on_exit(fn -> Application.put_env(:beamlet_app_web, :host, original) end)
    :ok
  end

  test "unconfigured local and disconnected configured targets remain explicit", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/nodes")

    eventually(fn ->
      html = render(view)
      assert html =~ "Configured: false"
      assert html =~ "missing@localhost"
      assert html =~ "disconnected"
      assert html =~ "partial / unknown"
      assert html =~ "capacity unknown"
      refute html =~ "PRIVATE"
    end)

    for event <- ["connect", "restart", "stop", "close", "input", "write-config"] do
      render_hook(view, event, %{"node" => "arbitrary@localhost"})
    end

    assert Node.list() == [] or Node.alive?()
  end

  for roles <- [[:authority], [:executor], [:authority, :executor]] do
    @roles roles
    test "public role composition #{inspect(roles)}", %{conn: conn} do
      start_supervised!({Beamlet.Node, roles: @roles, limits: [refresh_ms: 20]})
      {:ok, view, _} = live(conn, ~p"/admin/nodes")

      eventually(fn ->
        html = render(view)
        assert html =~ "Configured: true"
        for role <- @roles, do: assert(html =~ Atom.to_string(role))
        assert html =~ "routes: ready"
        assert html =~ "totals and utilization unknown"
      end)
    end
  end

  test "registered service loss stays unavailable rather than healthy empty", %{conn: conn} do
    start_supervised!({Beamlet.Node, roles: [:interaction]})
    :ok = Supervisor.terminate_child(Beamlet.Node, Beamlet.Runtime.SharedSupervisor)
    {:ok, view, _} = live(conn, ~p"/admin/nodes")

    eventually(fn ->
      html = render(view)
      assert html =~ "runtime: unavailable"
      assert html =~ "Runtime reports unavailable"
      assert html =~ "partial / unknown"
    end)
  end

  test "safe catalogue parity, defaults, references, compatibility and no private values", %{
    conn: conn
  } do
    config = %{
      models: %{
        "m" => %{
          title: "Safe model",
          binding: %{
            provider: "deterministic",
            config: %{
              "reply" => %{"kind" => "text", "content" => "PRIVATE_CONFIG", "calls" => []}
            },
            credentials: %{}
          }
        }
      },
      tools: %{},
      environments: %{},
      presets: %{"p" => %{title: "Safe preset", model: "m", tools: []}},
      authorities: %{"a" => %{title: "Safe authority", target: :local}},
      default_authority: "a"
    }

    assert {:ok, config} = Presets.configuration(config, [])
    start_supervised!({Presets, config})
    public = Presets.describe()
    {:ok, view, _} = live(conn, ~p"/admin/presets")

    eventually(fn ->
      html = render(view)
      assert html =~ public.presets["p"].title
      assert html =~ public.models["m"].title
      assert html =~ "Default authority reference: a"
      assert html =~ "Default model reference: m"
      assert html =~ "Tools: none"
      assert html =~ "Environment: not required"
      refute html =~ "PRIVATE_CONFIG"
      refute html =~ "binding"
      refute html =~ "<form"
    end)

    render_hook(view, "write-config", %{"model" => "forged"})
    assert Presets.describe() == public
    stop_supervised(Presets)
    view |> element("#refresh") |> render_click()
    eventually(fn -> assert render(view) =~ "Catalogue read unavailable: unavailable" end)
    assert render(view) =~ "Safe preset"
  end

  test "exact diagnostics handle, observe-only forged events and stale replacement", %{conn: conn} do
    start_supervised!({Beamlet.Agent.AuthoritySupervisor, []})
    start_supervised!(Handles)

    {:ok, ref} =
      Beamlet.Agent.start(node(),
        id: "diagnostic-agent",
        model: %{
          provider: "deterministic",
          config: %{"reply" => %{"kind" => "text", "content" => "safe", "calls" => []}},
          credentials: %{}
        }
      )

    {:ok, handle} = Handles.remember(%{authority: ref.authority, id: ref.id, pid: ref.pid})
    {:ok, view, _} = live(conn, ~p"/admin/diagnostics?handle=#{handle}&activity=forged")

    eventually(fn ->
      assert render(view) =~ "Observing current live context"
      assert render(view) =~ "diagnostic-agent"
      assert render(view) =~ "Activity identity stale / unknown"
    end)

    for event <- ["input", "stop", "close", "inspect-child"] do
      render_hook(view, event, %{"text" => "do business", "key" => "forged"})
    end

    assert {:ok, %{status: :idle}} = Beamlet.Agent.snapshot(ref)
    assert :ok = Beamlet.Agent.close(ref)

    {:ok, replacement} =
      Beamlet.Agent.start(node(),
        id: ref.id,
        model: %{
          provider: "deterministic",
          config: %{"reply" => %{"kind" => "text", "content" => "safe", "calls" => []}},
          credentials: %{}
        }
      )

    view |> element("#refresh") |> render_click()
    eventually(fn -> assert render(view) =~ "Unavailable / stale identity" end)
    assert {:ok, %{status: :idle}} = Beamlet.Agent.snapshot(replacement)
    refute render(view) =~ "#PID"
    {:ok, invalid, _} = live(conn, ~p"/admin/diagnostics?handle=invalid")
    eventually(fn -> assert render(invalid) =~ "No exact live handle resolved" end)
  end

  test "public-shape rendering fixtures show missing/stale/fresh source ages and available only" do
    for status <- [:not_reported, :stale, :fresh] do
      report = %{
        node: node(),
        status: status,
        age_ms: if(status == :not_reported, do: :unknown, else: 234)
      }

      report =
        if status == :not_reported,
          do: report,
          else:
            Map.merge(report, %{
              ready: true,
              execution_ready: true,
              capabilities: ["safe-capability"],
              environments: ["safe-environment"],
              available: %{"pool" => 7}
            })

      html =
        render_component(&ManagementLive.runtime_reports/1,
          runtime: {:ok, %{source: node(), complete: false, reports: [report]}}
        )

      assert html =~ Atom.to_string(status)

      if status == :not_reported do
        assert html =~ "Available capacity unknown"
        assert html =~ "Source receipt age: Unknown"
      else
        assert html =~ "Available pool: 7"
        assert html =~ "234 ms"
        assert html =~ "safe-capability"
        assert html =~ "safe-environment"
      end

      assert html =~ "coverage: partial"
      refute html =~ "total:"
      refute html =~ "%"
    end

    html =
      render_component(&ManagementLive.runtime_reports/1,
        runtime: {:ok, %{source: node(), complete: true, reports: []}}
      )

    assert html =~ "No reports; capacity unknown"
  end

  test "source text is escaped and empty collections stay explicit rather than unknown" do
    report = %{
      node: node(),
      status: :fresh,
      age_ms: 5,
      ready: false,
      execution_ready: false,
      capabilities: ["<script>alert(1)</script>"],
      environments: [],
      available: %{"<b>pool</b>" => 0}
    }

    html =
      render_component(&ManagementLive.runtime_reports/1,
        runtime: {:ok, %{source: node(), complete: true, reports: [report]}}
      )

    refute html =~ "<script>alert(1)</script>"
    refute html =~ "<b>pool</b>"
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert html =~ "Available &lt;b&gt;pool&lt;/b&gt;: 0"
    assert html =~ "Environments: none"
  end

  test "duplicate and local-inclusive allowlists resolve without duplication or a second read" do
    Application.put_env(:beamlet_app_web, :host,
      allowed_nodes: ["missing@localhost", "missing@localhost"]
    )

    assert {:ok, data} = ManagementReads.nodes()
    assert [_, :missing@localhost] = data.targets
    assert length(Enum.uniq(data.targets)) == length(data.targets)
    assert data.excluded == []
    [{:ok, aggregate}] = data.reads
    assert map_size(aggregate.nodes) + map_size(aggregate.failures) == 2

    local = Atom.to_string(node())
    Application.put_env(:beamlet_app_web, :host, allowed_nodes: [local])
    assert {:ok, local_data} = ManagementReads.nodes()
    assert local_data.targets == [node()]
    assert local_data.excluded == []
  end

  test "invalid configured scope is an explicit failure that retains the last observation", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/admin/nodes")
    eventually(fn -> assert render(view) =~ "Last observation received" end)
    Application.put_env(:beamlet_app_web, :host, allowed_nodes: ["not a node"])
    assert {:error, :invalid_authority} = ManagementReads.nodes()
    view |> element("#refresh") |> render_click()
    eventually(fn -> assert render(view) =~ "Node scope read unavailable: invalid_authority" end)
    assert render(view) =~ "missing@localhost"
    refute render(view) =~ "#PID"
  end

  test "one slow refresh, stale generation fencing, owner cleanup before resume", %{conn: conn} do
    start_supervised!({Beamlet.Node, roles: [:interaction]})
    routes = Process.whereis(Beamlet.Node.Routes)
    :ok = :sys.suspend(routes)
    on_exit(fn -> if Process.alive?(routes), do: :sys.resume(routes) end)
    {:ok, view, _} = live(conn, ~p"/admin/nodes")
    for _ <- 1..5, do: render_hook(view, "refresh", %{})
    assert render(view) =~ "Reading; previous observation retained"
    send(view.pid, {:owned, {:management, -1}, {:ok, %{}}})
    assert render(view) =~ "Reading; previous observation retained"
    # Public ownership primitive, not private product state inspection.
    owner =
      spawn(fn ->
        receive do
          :exit -> :ok
        end
      end)

    caller = OwnedCall.start(owner, :read, fn -> Beamlet.Node.observe([node()]) end)
    monitor = Process.monitor(caller)
    send(owner, :exit)
    assert_receive {:DOWN, ^monitor, :process, ^caller, _}, 1000
    GenServer.stop(view.pid)
    # Routes is still suspended at the actual DOWN assertion.
    :ok = :sys.resume(routes)
  end

  test "actual page guardian exits on unmount with source still suspended", %{conn: conn} do
    start_supervised!({Beamlet.Node, roles: [:interaction]})
    {:ok, view, _} = live(conn, ~p"/admin/nodes")
    eventually(fn -> assert render(view) =~ "Last observation received" end)
    routes = Process.whereis(Beamlet.Node.Routes)
    :ok = :sys.suspend(routes)
    on_exit(fn -> if Process.alive?(routes), do: :sys.resume(routes) end)
    :erlang.trace_pattern({OwnedCall, :start, 4}, [{:_, [], [{:return_trace}]}], [])
    :erlang.trace(view.pid, true, [:call])
    on_exit(fn -> :erlang.trace_pattern({OwnedCall, :start, 4}, false, []) end)
    view |> element("#refresh") |> render_click()
    assert_receive {:trace, _, :return_from, {OwnedCall, :start, 4}, guardian}, 1000
    monitor = Process.monitor(guardian)
    GenServer.stop(view.pid)
    assert_receive {:DOWN, ^monitor, :process, ^guardian, _}, 1000
    :ok = :sys.resume(routes)
  end

  test "page reads and forged controls dispatch zero business or connection calls", %{conn: conn} do
    patterns = [
      {Beamlet.Agent, :start, 2},
      {Beamlet.Agent, :input, 2},
      {Beamlet.Agent, :stop, 1},
      {Beamlet.Agent, :close, 1},
      {Beamlet.Runtime, :submit, 2},
      {Node, :connect, 1}
    ]

    for mfa <- patterns, do: :erlang.trace_pattern(mfa, true, [])
    :erlang.trace(:all, true, [:call])

    try do
      {:ok, view, _} = live(conn, ~p"/admin/nodes")
      eventually(fn -> assert render(view) =~ "Last observation received" end)

      for event <- ["input", "stop", "close", "connect", "restart"] do
        render_hook(view, event, %{})
      end

      fence = :erlang.trace_delivered(:all)
      assert_receive {:trace_delivered, :all, ^fence}, 1000
      refute_receive {:trace, _, :call, _}, 20
    after
      :erlang.trace(:all, false, [:call])
      for mfa <- patterns, do: :erlang.trace_pattern(mfa, false, [])
    end
  end

  test "full configured allowlist keeps excess local-inclusive scope explicit and bounded" do
    names = for n <- 1..32, do: "bounded#{n}@localhost"
    Application.put_env(:beamlet_app_web, :host, allowed_nodes: names)
    assert {:ok, data} = ManagementReads.nodes()
    assert length(data.targets) == 33
    assert length(data.reads) == 1
    assert length(data.excluded) == 1
    [{:ok, aggregate}] = data.reads
    assert map_size(aggregate.nodes) + map_size(aggregate.failures) == 32
    html = render_component(&ManagementLive.node_results/1, data: data)
    assert html =~ "32-target limit including explicit local"
    assert html =~ "bounded32@localhost"
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
