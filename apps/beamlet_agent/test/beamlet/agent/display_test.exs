defmodule Beamlet.Agent.DisplayTest do
  use ExUnit.Case
  alias Beamlet.Actions.{OperationRef, Result}
  alias Beamlet.Agent
  alias Beamlet.Agent.Display
  alias Beamlet.Harness.Catalogue
  alias Beamlet.Harness.Model, as: NeutralModel
  alias Beamlet.Runtime.Directory

  defmodule Model do
    @behaviour Beamlet.Harness.Model
    def validate_invocation(_), do: :ok

    def complete(request, invocation, _context) do
      send(Process.whereis(:agent_display_observer), {:model, self(), request, invocation})
      receive do: (:release -> :ok)

      if invocation.config["text_only"] == true or List.last(request.messages)["role"] == "tool" do
        {:ok, %{kind: :text, content: "finished", calls: []}}
      else
        calls =
          for id <- ["first", "second"],
              do: %{
                id: id,
                name: "echo",
                arguments: %{"text" => id <> ":" <> String.duplicate("界", 3000)}
              }

        {:ok, %{kind: :tool_calls, content: "working", calls: calls}}
      end
    end
  end

  defmodule Tool do
    @behaviour Beamlet.Harness.Tool
    def descriptor do
      %{
        "name" => "echo",
        "description" => "Test echo",
        "parameters" => %{
          "type" => "object",
          "properties" => %{"text" => %{"type" => "string", "maxLength" => 16_384}},
          "required" => ["text"]
        }
      }
    end

    def invoke(arguments, settings, context) do
      context.progress.(%{"phase" => "held"})
      send(settings.observer, {:tool, self(), arguments})
      receive do: (:release -> :ok)
      {:ok, %{"nested" => %{"text" => arguments["text"]}}}
    end
  end

  setup do
    Process.register(self(), :agent_display_observer)
    registry = %{"display" => Model}
    start_supervised!({Agent.AuthoritySupervisor, model_providers: registry})

    settings = %{
      model_providers: registry,
      profiles: %{
        "echo-profile" => %{
          type: :tool,
          module: Tool,
          settings: %{observer: self(), root: "PRIVATE_ROOT"}
        }
      }
    }

    start_supervised!(
      {Beamlet.Runtime,
       execution: true,
       handlers: %{"agent.native" => {Agent.Integration.Handler, settings}},
       capabilities: ["model.provider:display", "echo"],
       limits: [refresh_ms: 20]}
    )

    eventually(fn ->
      assert Enum.any?(Directory.snapshots(), fn {_, report} ->
               "model.provider:display" in report.capabilities
             end)
    end)

    :ok
  end

  defp options(id, metadata \\ %{}) do
    {:ok, catalogue} = Catalogue.new([Tool.descriptor()])

    [
      id: id,
      model: %{
        provider: "display",
        config: %{"marker" => "PRIVATE_CONFIG"},
        credentials: %{"token" => "PRIVATE_CREDENTIAL"}
      },
      catalogue: catalogue,
      tools: %{"echo" => %{id: "echo-profile", capability: "echo"}},
      display_metadata: metadata
    ]
  end

  test "real multi-turn tool flow projects source identities without changing neutral requests" do
    metadata = %{
      title: "A task",
      preset_id: "general",
      option_ids: %{
        model: "small",
        tools: ["echo"],
        environment: "readonly",
        constraints: "short"
      }
    }

    {:ok, ref} = Agent.start(node(), options("conversation", metadata))
    assert {:ok, base} = Agent.snapshot(ref)

    assert Enum.sort(Map.keys(base)) == [
             :final,
             :progress,
             :ref,
             :status,
             :steps,
             :terminal_turn,
             :turn
           ]

    assert {:ok, initial} = Agent.snapshot(ref, view: :display)
    assert initial.display.metadata == metadata
    assert initial.display.coverage == :live_context
    assert initial.display.entries == []
    assert_clean(initial)
    assert :ok = Agent.subscribe(ref, self(), view: :display)
    assert_receive {:beamlet_agent, ^ref, seq, {:snapshot, ^initial}}
    assert :ok = Agent.ack(ref, seq)

    for n <- 1..2 do
      {:ok, previous} = Agent.snapshot(ref, view: :display)
      text = "turn #{n}"
      {:ok, turn} = Agent.input(ref, text)
      assert {:error, :busy} = Agent.input(ref, "do not overlap")
      assert_receive {:model, model, request, invocation}, 3000
      assert invocation.config == %{"marker" => "PRIVATE_CONFIG"}
      assert invocation.credentials == %{"token" => "PRIVATE_CREDENTIAL"}
      assert List.last(request.messages) == %{"role" => "user", "content" => text}
      assert :ok = NeutralModel.validate_request(request)

      {:ok, running} = Agent.snapshot(ref, view: :display)

      assert Enum.take(running.display.entries, length(previous.display.entries)) ==
               previous.display.entries

      entry = List.last(running.display.entries)
      assert entry.turn == turn
      assert entry.content == text
      assert is_reference(entry.id)
      assert Enum.any?(running.display.activities, &(&1.kind == :model and &1.turn == turn))
      send(model, :release)

      tools =
        for _ <- 1..2 do
          assert_receive {:tool, pid, args}, 3000
          assert byte_size(args["text"]) > 9000
          {args["text"] |> String.split(":", parts: 2) |> hd(), pid}
        end

      eventually(fn ->
        {:ok, snapshot} = Agent.snapshot(ref, view: :display)
        activities = snapshot.display.activities
        assert length(activities) == 2
        assert Enum.all?(activities, &(&1.kind == :tool and &1.truncated))
        assert Enum.all?(activities, &(&1.turn == turn and &1.placement == :unknown))
        assert Enum.all?(activities, &is_struct(&1.operation, OperationRef))

        assert Enum.all?(
                 activities,
                 &(byte_size(&1.arguments) <= 8192 and String.valid?(&1.arguments))
               )
      end)

      # Reverse completion must not reorder the canonical source observations.
      workers = Map.new(tools)
      first = Map.fetch!(workers, "first")
      second = Map.fetch!(workers, "second")
      send(second, :release)

      eventually(fn ->
        {:ok, snapshot} = Agent.snapshot(ref, view: :display)

        assert Enum.any?(
                 snapshot.display.activities,
                 &(&1.id == "second" and &1.status == :completed and &1.truncated)
               )
      end)

      send(first, :release)
      assert_receive {:model, final_model, final_request, ^invocation}, 3000
      assert :ok = NeutralModel.validate_request(final_request)
      observations = Enum.filter(final_request.messages, &(&1["role"] == "tool"))
      assert Enum.map(Enum.take(observations, -2), & &1["call_id"]) == ["first", "second"]
      assert Enum.all?(observations, &(byte_size(&1["content"]) > 8192))
      send(final_model, :release)

      eventually(fn ->
        {:ok, snapshot} = Agent.snapshot(ref, view: :display)
        assert snapshot.status == :done
        assert snapshot.final == "finished"
        assert snapshot.display.truncated
        assert :field_limit in snapshot.display.reasons

        assert Enum.map(Enum.take(snapshot.display.entries, -5), & &1.turn) ==
                 List.duplicate(turn, 5)

        assert length(snapshot.display.entries) == n * 5
        assert Enum.find(snapshot.display.entries, &(&1.id == entry.id)) == entry
        assert snapshot.display.activities == []
        assert_clean(snapshot)
        # Full source context and immutable model binding stay private and intact.
        state = :sys.get_state(ref.pid)
        assert length(state.display_entries) == length(state.messages)
        assert Enum.all?(state.display_entries, &(Enum.sort(Map.keys(&1)) == [:id, :turn]))
        assert Enum.take(state.messages, length(final_request.messages)) == final_request.messages
        assert state.model == Keyword.fetch!(options("unused"), :model)
        assert map_size(state.owners) == 0
      end)
    end

    assert {:ok, before_read} = Agent.snapshot(ref, view: :display)
    assert {:ok, ^before_read} = Agent.snapshot(ref, view: :display)
    refute_receive {:model, _, _, _}, 50
    refute_receive {:tool, _, _}, 50
  end

  test "metadata and view options reject malformed, private and oversized data safely" do
    bad = [
      nil,
      [],
      :bad,
      %{"title" => "bad"},
      %{title: ""},
      %{title: <<255>>},
      %{title: String.duplicate("a", 129)},
      %{preset_id: String.duplicate("p", 129)},
      %{config: %{}},
      %{credentials: %{}},
      %{root: "path"},
      %{module: Model},
      %{option_ids: %{root: "path"}},
      %{option_ids: %{model: Model}},
      %{option_ids: %{tools: ["same", "same"]}},
      %{option_ids: %{tools: ["id" | :bad]}},
      %{option_ids: %{tools: Enum.map(1..65, &to_string/1)}},
      %{option_ids: %{model: %{"api_key" => "no"}}}
    ]

    for metadata <- bad do
      assert {:error, :invalid_agent_options} = Agent.start(node(), options("bad", metadata))
    end

    assert {:ok, ref} = Agent.start(node(), Keyword.delete(options("legacy"), :display_metadata))
    assert {:ok, %{display: %{metadata: %{}}}} = Agent.snapshot(ref, view: :display)

    for opts <- [
          [view: :private],
          [view: :display, extra: true],
          [view: :display, view: :display],
          %{},
          nil
        ] do
      assert {:error, :invalid_command} = Agent.snapshot(ref, opts)
      assert {:error, :invalid_command} = Agent.subscribe(ref, self(), opts)
    end

    assert {:error, :invalid_command} = Agent.subscribe(ref, :not_a_pid, view: :display)
    assert Process.alive?(ref.pid)
  end

  test "metadata enforces the exact complete serialized budget and UTF-8 label boundaries" do
    # Solve for a metadata map exactly at the 4096-byte boundary, using only IDs.
    ids = Enum.map(1..30, &String.pad_leading(to_string(&1), 122, "x"))
    seed = %{option_ids: %{tools: ids}, title: "a", preset_id: String.duplicate("界", 42) <> "ab"}
    padding = 4096 - :erlang.external_size(seed)
    assert padding in 1..127
    metadata = %{seed | title: String.duplicate("a", padding + 1)}
    assert :erlang.external_size(metadata) == 4096
    assert Display.metadata?(metadata)
    assert {:ok, _} = Agent.start(node(), options("exact-metadata", metadata))
    oversize = %{metadata | title: metadata.title <> "a"}
    assert :erlang.external_size(oversize) == 4097
    refute Display.metadata?(oversize)
    assert {:error, :invalid_agent_options} = Agent.start(node(), options("too-big", oversize))
    refute Display.metadata?(%{title: String.duplicate("界", 43)})
  end

  test "mixed subscriptions share credits, coalesce current replacements and survive sink exit" do
    {:ok, ref} = Agent.start(node(), options("credits"))
    parent = self()
    sink = spawn(fn -> sink_loop(parent, ref) end)
    on_exit(fn -> Process.exit(sink, :kill) end)
    assert :ok = Agent.subscribe(ref)
    assert :ok = Agent.subscribe(ref, sink, view: :display)
    assert_receive {:beamlet_agent, ^ref, _, {:snapshot, base}}
    refute Map.has_key?(base, :display)
    assert_receive {:sink, _, %{display: %{entries: []}}}
    assert {:error, :already_subscribed} = Agent.subscribe(ref, self(), view: :display)

    for _ <- 1..30, do: assert(:ok = Agent.stop_turn(ref))
    defaults = drain_default(ref, [])
    displays = drain_sink([])
    # Initial snapshot consumes one of the same 16 credits for either view.
    assert length(defaults) == 15
    assert length(displays) == 15
    {:ok, latest_turn} = Agent.input(ref, "coalesced latest")
    assert_receive {:model, _, _, _}, 3000
    assert Enum.all?(defaults, fn {_, snapshot} -> not Map.has_key?(snapshot, :display) end)
    assert Enum.all?(displays, fn {_, snapshot} -> Map.has_key?(snapshot, :display) end)
    assert :ok = Agent.ack(ref, elem(hd(displays), 0))
    # Ack from a different subscriber cannot release the sink's outstanding set.
    refute_receive {:sink, _, _}, 30
    send(sink, {:ack, elem(hd(displays), 0)})
    assert_receive {:sink_ack, :ok}

    assert_receive {:sink, _,
                    %{
                      status: :running,
                      turn: ^latest_turn,
                      display: %{entries: [%{content: "coalesced latest"}]}
                    }}

    assert :ok = Agent.unsubscribe(ref)
    assert {:error, :not_subscribed} = Agent.ack(ref, 1)
    monitor = Process.monitor(sink)
    Process.exit(sink, :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}
    eventually(fn -> assert :sys.get_state(ref.pid).subscribers == %{} end)
    assert :ok = Agent.stop_turn(ref)
    assert {:ok, %{status: :stopped}} = Agent.snapshot(ref)
    assert Process.alive?(ref.pid)
  end

  test "stop and owner loss freeze generation; stale work cannot alter display or revive execution" do
    {:ok, ref} = Agent.start(node(), options("generations"))
    {:ok, turn} = Agent.input(ref, "old")
    assert_receive {:model, model, _, _}, 3000
    [pending] = :sys.get_state(ref.pid).pending |> Map.values()

    stale_result = %Result{
      operation_id: pending.ref.id,
      source: :coordinator,
      status: :ok,
      value: %{kind: :text, content: "stale completion", calls: []}
    }

    assert Result.valid?(stale_result)
    assert :ok = Agent.stop_turn(ref)
    {:ok, stopped} = Agent.snapshot(ref, view: :display)
    assert stopped.terminal_turn == turn
    assert stopped.display.activities == []
    assert stopped.display.entries |> hd() |> Map.fetch!(:turn) == turn
    send(ref.pid, {:advance, turn})
    send(ref.pid, {:beamlet_operation, pending.ref, {:result, stale_result}})
    send(model, :release)
    eventually(fn -> assert :sys.get_state(ref.pid).owners == %{} end)
    assert {:ok, ^stopped} = Agent.snapshot(ref, view: :display)

    {:ok, next_turn} = Agent.input(ref, "new")
    assert next_turn != turn
    send(ref.pid, {:beamlet_operation, pending.ref, {:result, stale_result}})
    assert_receive {:model, _, _, _}, 3000
    owner = ref.pid |> :sys.get_state() |> Map.fetch!(:owners) |> Map.values() |> hd()
    Process.exit(owner.pid, :kill)

    eventually(fn ->
      assert {:ok, %{status: :error, terminal_turn: ^next_turn, display: display}} =
               Agent.snapshot(ref, view: :display)

      assert display.activities == []
    end)

    assert {:error, :stale_ref} = Agent.snapshot(%{ref | incarnation: make_ref()}, view: :display)

    assert {:error, :stale_ref} =
             Agent.subscribe(%{ref | incarnation: make_ref()}, self(), view: :display)

    assert :ok = Agent.close(ref)
    assert {:error, :unavailable} = Agent.snapshot(ref, view: :display)
    refute_receive {:model, _, _, _}, 50
  end

  test "child activity exposes an actually observed Ref and turn, not helper placement" do
    {:ok, ref} = Agent.start(node(), options("parent"))

    {:ok, group} =
      Agent.delegate(ref, [%{authority: node(), options: options("child"), input: "task"}])

    assert_receive {:model, _, _, _}, 3000

    eventually(fn ->
      {:ok, snapshot} = Agent.snapshot(ref, view: :display)

      assert [
               %{
                 kind: :child,
                 child: %Agent.Ref{} = child,
                 child_turn: turn,
                 turn: ^group,
                 placement: :unknown
               }
             ] = snapshot.display.activities

      assert {:ok, ^child} = Agent.lookup(node(), "child")
      assert is_reference(turn)
    end)

    assert :ok = Agent.stop_turn(ref)
    eventually(fn -> assert Agent.lookup(node(), "child") == {:error, :not_found} end)
    {:ok, snapshot} = Agent.snapshot(ref, view: :display)
    assert snapshot.display.activities == []
    assert snapshot.display.entries == []
    assert snapshot.terminal_turn == group
  end

  test "joined child context uses the source delegation turn and keeps actual interim identities" do
    text_options = fn id ->
      opts = options(id)
      model = Keyword.fetch!(opts, :model)
      Keyword.put(opts, :model, %{model | config: Map.put(model.config, "text_only", true)})
    end

    {:ok, ref} = Agent.start(node(), text_options.("joining"))

    specs =
      for id <- ["one", "two"], do: %{authority: node(), options: text_options.(id), input: id}

    {:ok, group} = Agent.delegate(ref, specs, continue: true)
    assert_receive {:model, first, _, _}, 3000
    assert_receive {:model, second, _, _}, 3000
    send(first, :release)

    eventually(fn ->
      {:ok, snapshot} = Agent.snapshot(ref, view: :display)
      assert length(snapshot.display.activities) == 2
      completed = Enum.find(snapshot.display.activities, &(&1.status == :completed))
      assert completed
      assert %Agent.Ref{} = completed.child
      assert is_reference(completed.child_turn)
      assert completed.turn == group
      assert completed.result == Jason.encode!("finished")
      assert_clean(snapshot)
    end)

    send(second, :release)
    assert_receive {:model, parent, request, _}, 3000
    assert [%{"role" => "user", "content" => child_content}] = request.messages

    assert [
             %{"status" => "ok", "value" => "finished"},
             %{"status" => "ok", "value" => "finished"}
           ] = Jason.decode!(child_content)

    {:ok, snapshot} = Agent.snapshot(ref, view: :display)
    assert [%{turn: ^group, content: ^child_content}] = snapshot.display.entries
    send(parent, :release)

    eventually(fn ->
      assert {:ok, %{status: :done, display: display}} = Agent.snapshot(ref, view: :display)
      assert Enum.map(display.entries, & &1.turn) == [group, group]
    end)
  end

  @tag timeout: 8000
  test "suspended display read is finite and never couples identity discovery to rendering" do
    {:ok, ref} = Agent.start(node(), options("suspended-display"))
    :ok = :sys.suspend(ref.pid)
    on_exit(fn -> if Process.alive?(ref.pid), do: :sys.resume(ref.pid) end)
    assert {:ok, [%{pid: pid}]} = Agent.list(node())
    assert pid == ref.pid
    assert {:error, :unavailable} = Agent.snapshot(ref, view: :display)
    assert Process.alive?(ref.pid)
    :ok = :sys.resume(ref.pid)
    assert {:ok, %{status: :idle, display: %{entries: []}}} = Agent.snapshot(ref, view: :display)
    refute_receive {_, {:ok, _}}, 30
  end

  test "identity-island loss invalidates display refs without recovery or replacement attachment" do
    {:ok, ref} = Agent.start(node(), options("identity-loss"))
    monitor = Process.monitor(ref.pid)
    registry = Process.whereis(Agent.Registry)
    Process.exit(registry, :kill)
    assert_receive {:DOWN, ^monitor, _, _, _}, 3000
    assert {:error, :unavailable} = Agent.snapshot(ref, view: :display)

    eventually(fn ->
      assert is_pid(Process.whereis(Agent.Registry))
      assert Process.whereis(Agent.Registry) != registry
      assert {:ok, []} = Agent.list(node())
    end)

    {:ok, replacement} = Agent.start(node(), options("identity-loss"))
    refute replacement.incarnation == ref.incarnation
    assert {:error, :unavailable} = Agent.snapshot(ref, view: :display)
    assert {:ok, %{display: %{entries: []}}} = Agent.snapshot(replacement, view: :display)
  end

  defp assert_clean(value) do
    text = inspect(value, limit: :infinity, printable_limit: :infinity)

    for marker <- ["PRIVATE_CONFIG", "PRIVATE_CREDENTIAL", "PRIVATE_ROOT"],
        do: refute(text =~ marker)

    refute text =~ "Beamlet.Agent.DisplayTest.Model"
    refute text =~ "echo-profile"
  end

  defp sink_loop(parent, ref) do
    receive do
      {:beamlet_agent, ^ref, sequence, {:snapshot, snapshot}} ->
        send(parent, {:sink, sequence, snapshot})
        sink_loop(parent, ref)

      {:ack, sequence} ->
        send(parent, {:sink_ack, Agent.ack(ref, sequence)})
        sink_loop(parent, ref)
    end
  end

  defp drain_default(ref, acc) do
    receive do
      {:beamlet_agent, ^ref, seq, {:snapshot, snapshot}} ->
        drain_default(ref, [{seq, snapshot} | acc])
    after
      30 -> Enum.reverse(acc)
    end
  end

  defp drain_sink(acc) do
    receive do
      {:sink, seq, snapshot} -> drain_sink([{seq, snapshot} | acc])
    after
      30 -> Enum.reverse(acc)
    end
  end

  defp eventually(fun, attempts \\ 200) do
    fun.()
  rescue
    error in ExUnit.AssertionError ->
      if attempts == 0, do: reraise(error, __STACKTRACE__)
      Process.sleep(10)
      eventually(fun, attempts - 1)
  end
end
