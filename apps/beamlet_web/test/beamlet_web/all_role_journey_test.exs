defmodule Beamlet.Web.AllRoleJourneyTest do
  @moduledoc """
  Parent-level integration: one enabled three-role Web Host, driven through the
  LiveView workbench, exercising preset selection/reset, creation plus first
  input, a real Tool activity/result, a second turn, and stop/leave/close.

  The Host owns the Node tree (interaction + authority + executor), so these are
  not separately started fixtures. The deterministic provider and Tool below are
  test doubles for external systems only; every Web/Agent/Runtime/Node edge is
  the real public API.
  """
  use Beamlet.Web.ConnCase
  import Phoenix.LiveViewTest
  alias Beamlet.Web.Handles

  defmodule Model do
    @behaviour Beamlet.Harness.Model
    def validate_invocation(_), do: :ok

    def complete(request, _, _) do
      send(Process.whereis(:all_role_journey), {:model, self(), request})

      receive do
        :release -> :ok
      end

      if List.last(request.messages)["role"] == "tool" do
        {:ok, %{kind: :text, content: "hostile </script> finished", calls: []}}
      else
        {:ok,
         %{
           kind: :tool_calls,
           content: "working",
           calls: [%{id: "one", name: "echo", arguments: %{"text" => "real tool input"}}]
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

    def invoke(arguments, settings, _) do
      send(settings.observer, {:tool, self()})
      receive do: (:release -> :ok)
      {:ok, arguments}
    end
  end

  setup do
    previous = Application.get_env(:beamlet_web, :host)
    :ok = Application.stop(:beamlet_web)
    Process.register(self(), :all_role_journey)

    on_exit(fn ->
      Application.stop(:beamlet_web)

      if previous,
        do: Application.put_env(:beamlet_web, :host, previous),
        else: Application.delete_env(:beamlet_web, :host)

      {:ok, _} = Application.ensure_all_started(:beamlet_web)
    end)

    :ok
  end

  test "one three-role Host serves preset, create, tool, second turn and stop/close", %{
    conn: conn
  } do
    enable()

    assert {:ok, %{roles: [:interaction, :authority, :executor]}} = Beamlet.Node.observation()
    assert is_pid(Process.whereis(Beamlet.Agent.Registry))
    assert is_pid(Process.whereis(Beamlet.Runtime.ExecutorGateway))

    {:ok, view, _} = live(conn, ~p"/agents/new")
    eventually(fn -> assert has_element?(view, "#creation") end)

    # Preset selection edits a disposable draft only.
    view |> form("#creation", draft: %{preset: "chat", task: "keep task"}) |> render_change()
    assert render(view) =~ "keep task"
    refute has_element?(view, "input[name='draft[tools][]'][checked]")
    view |> form("#creation", draft: %{title: "Edited"}) |> render_change()
    assert render(view) =~ "Modified from preset defaults"
    view |> element("button", "Reset to preset defaults") |> render_click()
    refute render(view) =~ "Modified from preset defaults"

    view |> form("#creation", draft: %{preset: "basic", task: "use the tool"}) |> render_change()
    assert has_element?(view, "input[name='draft[tools][]'][checked]")

    view |> form("#creation") |> render_submit()
    eventually(fn -> assert render(view) =~ "Creation identity:" end)

    assert_receive {:model, model, request}, 5000
    assert List.last(request.messages)["content"] == "use the tool"
    send(model, :release)

    assert_receive {:tool, tool}, 5000

    eventually(fn ->
      html = render(view)
      assert html =~ "echo"
      assert html =~ "real tool input"
      refute html =~ "PRIVATE_"
    end)

    send(tool, :release)
    assert_receive {:model, final, %{messages: messages}}, 5000
    assert List.last(messages)["role"] == "tool"
    send(final, :release)

    eventually(fn ->
      html = render(view)
      assert html =~ "hostile &lt;/script&gt; finished"
      assert html =~ "Initial input: Input accepted"
    end)

    # Second turn on the same Agent.
    view |> form("#follow-up", text: "second task") |> render_change()
    view |> form("#follow-up") |> render_submit()
    assert_receive {:model, second, second_request}, 5000
    assert List.last(second_request.messages)["content"] == "second task"
    send(second, :release)
    assert_receive {:tool, second_tool}, 5000
    send(second_tool, :release)
    assert_receive {:model, second_final, _}, 5000
    send(second_final, :release)

    assert {:ok, [descriptor]} = Beamlet.Agent.list(node())
    assert {:ok, ref} = Beamlet.Agent.lookup(descriptor)

    eventually(fn ->
      assert render(view) =~ "second task"
      assert {:ok, %{status: :done}} = Beamlet.Agent.snapshot(ref)
    end)

    # Stop is a request on the turn; the instance survives.
    view |> form("#follow-up", text: "third task") |> render_change()
    view |> form("#follow-up") |> render_submit()
    assert_receive {:model, third, _}, 5000
    view |> element("button", "Stop current turn") |> render_click()
    eventually(fn -> assert render(view) =~ "Request acknowledged" end)
    assert {:ok, %{status: stopped}} = Beamlet.Agent.snapshot(ref)
    refute stopped == :running
    send(third, :release)
    # Leaving the page only removes observation.
    GenServer.stop(view.pid)
    assert {:ok, _} = Beamlet.Agent.snapshot(ref)

    # The surviving instance is rediscoverable and can be closed explicitly.
    {:ok, handle} = Handles.remember(descriptor)
    {:ok, second_view, _} = live(conn, ~p"/agents/#{handle}")
    eventually(fn -> assert render(second_view) =~ "Agent workspace" end)
    second_view |> element("button", "Close instance…") |> render_click()
    assert Process.alive?(ref.pid)
    second_view |> element("button", "Confirm close instance") |> render_click()
    eventually(fn -> refute Process.alive?(ref.pid) end)
    assert {:error, :stale_handle} = Handles.fetch(handle)
  end

  defp enable do
    catalogue = %{
      models: %{
        "model" => %{
          title: "Test",
          binding: %{
            provider: "webtest",
            config: %{"reply" => %{"kind" => "text", "content" => "unused", "calls" => []}},
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
        "chat" => %{title: "Chat", model: "model", tools: []}
      },
      authorities: %{"local" => %{title: "Local", target: :local}},
      default_authority: "local"
    }

    Application.put_env(:beamlet_web, :host,
      enabled: true,
      node: [
        roles: [:interaction, :authority, :executor],
        model_providers: %{"webtest" => Model},
        profiles: %{
          "echo" => %{
            type: :tool,
            module: Tool,
            capability: "echo",
            settings: %{observer: self(), root: "PRIVATE_ROOT"}
          }
        },
        allowlist: %{tool: [Tool]},
        limits: [refresh_ms: 20]
      ],
      catalogue: catalogue
    )

    assert {:ok, _} = Application.ensure_all_started(:beamlet_web)
    wait_ready(200)
  end

  defp wait_ready(0), do: flunk("executor report absent")

  defp wait_ready(n) do
    {:ok, view} = Beamlet.Runtime.observation()

    if Enum.any?(view.reports, &(&1[:execution_ready] == true)) do
      :ok
    else
      Process.sleep(20)
      wait_ready(n - 1)
    end
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
