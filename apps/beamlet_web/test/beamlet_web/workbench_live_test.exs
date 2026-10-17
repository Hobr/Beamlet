defmodule Beamlet.Web.WorkbenchLiveTest do
  use Beamlet.Web.ConnCase
  import Phoenix.LiveViewTest
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Runtime.Directory
  alias Beamlet.Web.{Handles, OwnedCall, Presets, WorkbenchCommands, WorkbenchLive}

  defmodule Model do
    @behaviour Beamlet.Harness.Model
    def validate_invocation(_), do: :ok

    def complete(request, _, _) do
      send(Process.whereis(:workbench_test), {:model, self(), request})
      receive do: (:release -> :ok)

      if List.last(request.messages)["role"] == "tool" do
        {:ok, %{kind: :text, content: "<script>hostile finished</script>", calls: []}}
      else
        {:ok,
         %{
           kind: :tool_calls,
           content: "working",
           calls:
             for(
               id <- ["one", "two"],
               do: %{id: id, name: "echo", arguments: %{"text" => String.duplicate("x", 9000)}}
             )
         }}
      end
    end
  end

  defmodule Tool do
    @behaviour Beamlet.Harness.Tool
    def descriptor,
      do: %{
        "name" => "echo",
        "description" => "Echo",
        "parameters" => %{
          "type" => "object",
          "properties" => %{"text" => %{"type" => "string"}},
          "required" => ["text"]
        }
      }

    def invoke(args, settings, _) do
      send(settings.observer, {:tool, self()})
      receive do: (:release -> :ok)
      {:ok, args}
    end
  end

  setup do
    Process.register(self(), :workbench_test)
    start_supervised!({Beamlet.Agent.AuthoritySupervisor, model_providers: %{"webtest" => Model}})

    start_supervised!(
      {Beamlet.Runtime,
       execution: true,
       handlers: %{
         "agent.native" =>
           {Beamlet.Agent.Integration.Handler,
            %{
              model_providers: %{"webtest" => Model},
              profiles: %{
                "echo" => %{
                  type: :tool,
                  module: Tool,
                  settings: %{observer: self(), root: "PRIVATE_ROOT"}
                }
              }
            }}
       },
       capabilities: ["model.provider:webtest", "echo"],
       limits: [refresh_ms: 20]}
    )

    eventually(fn ->
      assert Enum.any?(Directory.snapshots(), fn {_, report} ->
               "echo" in report.capabilities
             end)
    end)

    start_supervised!(Handles)

    config = %{
      models: %{
        "model" => %{
          title: "Test",
          binding: %{
            provider: "webtest",
            config: %{"sentinel" => "PRIVATE_CONFIG"},
            credentials: %{"token" => "PRIVATE_CREDENTIAL"}
          }
        }
      },
      tools: %{
        "echo" => %{
          title: "Echo",
          route: %{id: "echo", capability: "echo"},
          descriptor: Tool.descriptor(),
          environments: []
        }
      },
      presets: %{
        "basic" => %{title: "Task", model: "model", tools: ["echo"]},
        "z-chat" => %{title: "Chat", model: "model", tools: []}
      },
      authorities: %{"local" => %{title: "Local", target: :local}},
      default_authority: "local"
    }

    assert {:ok, config} = Presets.configuration(config, [], %{"webtest" => Model})
    start_supervised!({Presets, config})
    {:ok, catalogue} = Catalogue.new([Tool.descriptor()])

    opts = [
      model: config.models["model"].binding,
      catalogue: catalogue,
      tools: %{"echo" => %{id: "echo", capability: "echo"}}
    ]

    %{options: opts, config: config}
  end

  test "external discovery, real concurrent tool turns, escaping, stop, leave and close", %{
    conn: conn,
    options: options
  } do
    {:ok, ref} = Beamlet.Agent.start(node(), Keyword.put(options, :id, "external-cli"))
    {:ok, view, _} = live(conn, ~p"/")
    eventually(fn -> assert render(view) =~ "external-cli" end)
    view |> element("button", "external-cli") |> render_click()
    eventually(fn -> assert render(view) =~ "Agent workspace" end)

    for n <- 1..2 do
      view |> form("#follow-up", text: "turn #{n}") |> render_change()
      view |> form("#follow-up") |> render_submit()
      assert_receive {:model, model, request}, 3000
      assert List.last(request.messages)["content"] == "turn #{n}"
      send(model, :release)

      tools =
        for _ <- 1..2 do
          assert_receive {:tool, tool}, 3000
          tool
        end

      eventually(fn ->
        html = render(view)
        assert html =~ "Source field truncated" or html =~ "truncated"
        assert html =~ "pending"
        refute html =~ "PRIVATE_"
      end)

      Enum.each(tools, &send(&1, :release))
      assert_receive {:model, final, _}, 3000
      send(final, :release)
      eventually(fn -> assert render(view) =~ "&lt;script&gt;hostile finished&lt;/script&gt;" end)
    end

    view |> element("button", "Stop current turn") |> render_click()

    eventually(fn ->
      assert {:ok, _} =
               Beamlet.Agent.lookup(%{authority: ref.authority, id: ref.id, pid: ref.pid})
    end)

    GenServer.stop(view.pid)
    assert {:ok, _} = Beamlet.Agent.snapshot(ref)
    {:ok, handle} = Handles.remember(%{authority: ref.authority, id: ref.id, pid: ref.pid})
    {:ok, second, _} = live(conn, ~p"/agents/#{handle}")
    eventually(fn -> assert render(second) =~ "Agent workspace" end)
    second |> element("button", "Close instance…") |> render_click()
    assert Process.alive?(ref.pid)
    second |> element("button", "Confirm close instance") |> render_click()
    eventually(fn -> refute Process.alive?(ref.pid) end)
  end

  test "owned caller expires while blocked, dies with owner and never retries" do
    owner = self()

    guardian =
      OwnedCall.start(
        owner,
        :probe,
        fn ->
          send(owner, {:worker, self()})
          receive do: (:never -> :ok)
        end,
        30
      )

    assert_receive {:worker, worker}
    monitor = Process.monitor(worker)
    assert_receive {:owned, :probe, :deadline}, 1000
    assert_receive {:DOWN, ^monitor, _, _, _}, 1000
    refute Process.alive?(guardian)
    temporary = spawn(fn -> receive do: (:never -> :ok) end)

    OwnedCall.start(temporary, :probe, fn ->
      send(owner, {:worker, self()})
      receive do: (:never -> :ok)
    end)

    assert_receive {:worker, other}
    monitor = Process.monitor(other)
    Process.exit(temporary, :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}, 1000
  end

  test "preset form creates once and retains real selected instance", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/agents/new")
    eventually(fn -> assert has_element?(view, "#creation") end)
    view |> form("#creation", draft: %{task: "first task"}) |> render_change()
    :ok = :sys.suspend(Beamlet.Agent.Agents)

    try do
      view |> form("#creation") |> render_submit()
      view |> form("#creation") |> render_submit()
    after
      :sys.resume(Beamlet.Agent.Agents)
    end

    assert_receive {:model, model, _}, 3000
    assert {:ok, [_]} = Beamlet.Agent.list(node())
    eventually(fn -> assert render(view) =~ "Agent workspace" end)
    send(model, :release)
  end

  test "local admission timeout preserves uncertainty and late creation has no input" do
    {:ok, draft} = Presets.reset("basic")
    owner = self()
    :ok = :sys.suspend(Beamlet.Agent.Agents)

    try do
      guardian =
        OwnedCall.start(
          owner,
          :late,
          fn -> WorkbenchCommands.create(owner, :late, draft) end,
          60
        )

      assert_receive {:creation, :late, {:identity, authority, id}}, 1000
      {:links, [worker]} = Process.info(guardian, :links)
      monitor = Process.monitor(worker)
      assert_receive {:owned, :late, :deadline}, 1000
      assert_receive {:DOWN, ^monitor, _, _, _}, 1000
      :ok = :sys.resume(Beamlet.Agent.Agents)
      eventually(fn -> assert {:ok, [%{id: ^id}]} = Beamlet.Agent.list(authority) end)
      {:ok, ref} = Beamlet.Agent.lookup(authority, id)
      assert {:ok, %{status: :idle}} = Beamlet.Agent.snapshot(ref)
      refute_receive {:model, _, _}, 50
      refute_receive {:creation, :late, {:confirmed, _}}, 50
    after
      :sys.resume(Beamlet.Agent.Agents)
    end
  end

  test "exact handle rejects replacement and live observer reports loss", %{
    conn: conn,
    options: options
  } do
    {:ok, first} = Beamlet.Agent.start(node(), Keyword.put(options, :id, "replace"))
    {:ok, discovery, _} = live(conn, ~p"/")
    eventually(fn -> assert has_element?(discovery, "li button", "replace") end)
    {:ok, handle} = Handles.remember(%{authority: first.authority, id: first.id, pid: first.pid})
    {:ok, view, _} = live(conn, ~p"/agents/#{handle}")
    eventually(fn -> assert render(view) =~ "Agent workspace" end)
    :ok = Beamlet.Agent.close(first)
    eventually(fn -> assert render(view) =~ "Observation unavailable" end)
    {:ok, replacement} = Beamlet.Agent.start(node(), Keyword.put(options, :id, "replace"))
    discovery |> element("li button", "replace") |> render_click()
    eventually(fn -> assert render(discovery) =~ "Exact discovered identity: stale_agent" end)
    refute has_element?(discovery, "#follow-up")
    {:ok, stale, _} = live(conn, ~p"/agents/#{handle}")
    eventually(fn -> assert render(stale) =~ "exact identity unavailable / stale" end)
    assert Process.alive?(replacement.pid)
  end

  test "missing navigation retains confirmed creation and input feedback", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    eventually(fn -> assert has_element?(view, "#creation") end)
    stop_supervised!(Handles)
    view |> form("#creation", draft: %{task: "retained"}) |> render_change()
    view |> form("#creation") |> render_submit()
    assert_receive {:model, _, _}, 3000

    eventually(fn ->
      html = render(view)
      assert html =~ "Confirmed instance retained here"
      assert html =~ "Input accepted"
      refute html =~ "PRIVATE_"
    end)

    assert {:ok, [_]} = Beamlet.Agent.list(node())
  end

  test "replacement snapshot absence clears display and old generations cannot repaint", %{
    options: options
  } do
    {:ok, ref} = Beamlet.Agent.start(node(), Keyword.put(options, :id, "projection"))
    assert {:ok, snapshot} = Beamlet.Agent.snapshot(ref, view: :display)
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, generation: 2, ref: ref}}

    {:noreply, current} =
      WorkbenchLive.handle_info(
        {:observation, {2, ref}, {:snapshot, snapshot}},
        socket
      )

    assert current.assigns.display == snapshot.display

    {:noreply, cleared} =
      WorkbenchLive.handle_info(
        {:observation, {2, ref}, {:snapshot, Map.delete(snapshot, :display)}},
        current
      )

    assert cleared.assigns.display == nil

    {:noreply, unchanged} =
      WorkbenchLive.handle_info(
        {:observation, {1, ref}, {:snapshot, snapshot}},
        cleared
      )

    assert unchanged.assigns.display == nil
  end

  test "busy external observer is rejected, stop preserves instance and drafts never queue", %{
    conn: conn,
    options: options
  } do
    {:ok, ref} = Beamlet.Agent.start(node(), Keyword.put(options, :id, "busy"))
    {:ok, handle} = Handles.remember(%{authority: ref.authority, id: ref.id, pid: ref.pid})
    {:ok, view, _} = live(conn, ~p"/agents/#{handle}")
    eventually(fn -> assert has_element?(view, "#follow-up") end)
    {:ok, _} = Beamlet.Agent.input(ref, "external observer")
    assert_receive {:model, _, _}, 3000
    view |> form("#follow-up", text: "not queued") |> render_change()
    view |> form("#follow-up") |> render_submit()
    eventually(fn -> assert render(view) =~ "Rejected: busy" end)
    view |> element("button", "Stop current turn") |> render_click()
    eventually(fn -> assert {:ok, %{status: :stopped}} = Beamlet.Agent.snapshot(ref) end)
    assert Process.alive?(ref.pid)
    refute_receive {:model, _, _}, 50
  end

  test "real delegation inspector opens the actual child with commands hidden", %{
    conn: conn,
    options: options
  } do
    {:ok, parent} = Beamlet.Agent.start(node(), Keyword.put(options, :id, "parent"))

    {:ok, _} =
      Beamlet.Agent.delegate(parent, [
        %{authority: node(), options: Keyword.put(options, :id, "child"), input: "child task"}
      ])

    assert_receive {:model, _, _}, 3000

    {:ok, handle} =
      Handles.remember(%{authority: parent.authority, id: parent.id, pid: parent.pid})

    {:ok, view, _} = live(conn, ~p"/agents/#{handle}")
    eventually(fn -> assert has_element?(view, "button", "Inspect child (observe only)") end)
    view |> element("button", "Inspect child (observe only)") |> render_click()

    eventually(fn ->
      assert render(view) =~ "child task"
      refute has_element?(view, "#follow-up")
      refute has_element?(view, "button", "Stop current turn")
    end)

    assert {:ok, _} = Beamlet.Agent.lookup(node(), "child")
  end

  test "missing presets exits before dispatch with explicit feedback", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    eventually(fn -> assert has_element?(view, "#creation") end)
    stop_supervised!(Presets)
    view |> form("#creation", draft: %{task: "never sent"}) |> render_change()
    view |> form("#creation") |> render_submit()

    eventually(fn ->
      assert render(view) =~ "Configuration unavailable before creation dispatch"
    end)

    assert {:ok, []} = Beamlet.Agent.list(node())
  end

  @tag timeout: 30_000
  test "actual UI deadline bounds suspended local creation and late success is discoverable", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/")
    eventually(fn -> assert has_element?(view, "#creation") end)
    :ok = :sys.suspend(Beamlet.Agent.Agents)

    try do
      view |> form("#creation", draft: %{task: "uncertain"}) |> render_change()
      view |> form("#creation") |> render_submit()
      eventually(fn -> assert render(view) =~ "Creation identity:" end)
      assert has_element?(view, "#creation button[disabled]", "Create and send task")
      eventually(fn -> assert render(view) =~ "Outcome unknown / unavailable" end, 900)
      assert {:ok, []} = Beamlet.Agent.list(node())
      :ok = :sys.resume(Beamlet.Agent.Agents)
      eventually(fn -> assert {:ok, [_]} = Beamlet.Agent.list(node()) end)
      view |> element("button", "Discover now") |> render_click()
      eventually(fn -> assert has_element?(view, "li button", "web-") end)
      refute_receive {:model, _, _}, 50
    after
      :sys.resume(Beamlet.Agent.Agents)
    end
  end

  test "selecting a preset applies defaults and reset discards only disposable edits", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/agents/new")
    eventually(fn -> assert has_element?(view, "#creation") end)
    view |> form("#creation", draft: %{preset: "z-chat", task: "keep task"}) |> render_change()
    assert render(view) =~ "keep task"
    refute has_element?(view, "input[name='draft[tools][]'][checked]")
    view |> form("#creation", draft: %{title: "Adjusted"}) |> render_change()
    assert render(view) =~ "Modified from preset defaults"
    view |> element("button", "Reset to preset defaults") |> render_click()
    refute render(view) =~ "Modified from preset defaults"
    assert has_element?(view, "input[name='draft[title]'][value='Chat']")
    {:ok, original} = Presets.reset("z-chat")
    assert original["title"] == "Chat"
    assert original["tools"] == []
    assert {:ok, []} = Beamlet.Agent.list(node())
  end

  test "sink waits for consumer before ack and observer teardown leaves running Agent alive", %{
    options: options
  } do
    {:ok, ref} = Beamlet.Agent.start(node(), Keyword.put(options, :id, "credit"))
    guardian = OwnedCall.observe(self(), :credit, ref)
    assert_receive {:observation, :credit, {:snapshot, initial, sink, sequence}}, 1000
    assert initial.display.entries == []
    {:ok, _} = Beamlet.Agent.input(ref, "held")
    assert_receive {:model, _, _}, 3000
    refute_receive {:observation, :credit, _}, 50
    send(sink, {:displayed, sequence})
    assert_receive {:observation, :credit, {:snapshot, _, ^sink, _}}, 1000
    monitor = Process.monitor(sink)
    send(guardian, :leave)
    assert_receive {:DOWN, ^monitor, _, _, _}, 1000
    assert {:ok, %{status: :running}} = Beamlet.Agent.snapshot(ref)
  end

  test "terminal delivery follows milestones and actual worker exit" do
    owner = self()

    guardian =
      OwnedCall.start(owner, :ordered, fn ->
        send(owner, {:ordered_worker, self()})

        for event <- [:identity, :confirmed, :input] do
          OwnedCall.deliver(owner, {:milestone_test, event})
        end

        :complete
      end)

    assert_receive {:ordered_worker, worker}
    assert_receive {:milestone_test, :identity}
    assert_receive {:milestone_test, :confirmed}
    assert_receive {:milestone_test, :input}
    assert_receive {:owned, :ordered, :complete}
    refute Process.alive?(worker)
    eventually(fn -> refute Process.alive?(guardian) end)
  end

  test "owner loss during prior observer retirement kills new sink before source resumes", %{
    options: options
  } do
    {:ok, ref} = Beamlet.Agent.start(node(), Keyword.put(options, :id, "retiring"))
    previous = OwnedCall.observe(self(), :prior, ref)
    assert_receive {:observation, :prior, {:snapshot, _, old_sink, _}}, 1000
    :ok = :sys.suspend(ref.pid)
    owner = spawn(fn -> receive do: (:never -> :ok) end)
    replacement = OwnedCall.observe(owner, :replacement, ref, previous)
    eventually(fn -> assert match?({:links, [_]}, Process.info(replacement, :links)) end)
    {:links, [new_sink]} = Process.info(replacement, :links)
    replacement_monitor = Process.monitor(replacement)
    new_monitor = Process.monitor(new_sink)
    old_monitor = Process.monitor(old_sink)

    try do
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^new_monitor, _, _, _}, 1000
      assert_receive {:DOWN, ^replacement_monitor, _, _, _}, 1000
      assert_receive {:DOWN, ^old_monitor, _, _, _}, 7000
      refute Process.alive?(old_sink)
    after
      :sys.resume(ref.pid)
    end

    assert {:ok, %{status: :idle}} = Beamlet.Agent.snapshot(ref)
  end

  test "local non-authority is complete empty discovery" do
    stop_supervised!(Beamlet.Agent.AuthoritySupervisor)
    assert {:ok, %{complete: true, agents: [], failures: %{}}} = WorkbenchCommands.discover()
  end

  test "duplicate discovery is locked and stale observer failure cannot clear selected source", %{
    options: options
  } do
    {:ok, ref} = Beamlet.Agent.start(node(), Keyword.put(options, :id, "selected"))

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, generation: 2, ref: ref, discovering: true, display: :retained}
    }

    assert {:noreply, ^socket} = WorkbenchLive.handle_info(:discover, socket)
    stale = %{ref | incarnation: make_ref()}

    assert {:noreply, ^socket} =
             WorkbenchLive.handle_info({:observation, {2, stale}, :unavailable}, socket)
  end

  test "environment is conditional and hidden selection clears before chat creation", %{
    conn: conn,
    config: config
  } do
    stop_supervised!(Presets)

    config =
      config
      |> put_in([:tools, "echo", :environments], ["workspace"])
      |> Map.put(:environments, %{"workspace" => %{title: "Workspace", value: "workspace"}})
      |> put_in([:presets, "basic", :environment], "workspace")

    start_supervised!({Presets, config})
    {:ok, view, _} = live(conn, ~p"/")
    eventually(fn -> assert has_element?(view, "select[name='draft[environment]']") end)
    view |> form("#creation", draft: %{tools: []}) |> render_change()
    refute has_element?(view, "select[name='draft[environment]']")
    view |> form("#creation", draft: %{task: "chat without environment"}) |> render_change()
    view |> form("#creation") |> render_submit()
    assert_receive {:model, _, _}, 3000
    eventually(fn -> assert has_element?(view, "#follow-up") end)
    assert {:ok, [descriptor]} = Beamlet.Agent.list(node())
    assert {:ok, ref} = Beamlet.Agent.lookup(descriptor)

    assert {:ok, %{display: %{metadata: %{option_ids: ids}}}} =
             Beamlet.Agent.snapshot(ref, view: :display)

    refute Map.has_key?(ids, :environment)
    assert ids.tools == []
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
