defmodule Beamlet.Agent.CountingModel do
  @moduledoc false
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.Models.Deterministic

  @impl true
  defdelegate validate_invocation(invocation), to: Deterministic

  @impl true
  def complete(request, invocation, context \\ %Beamlet.Harness.Context{}) do
    send(:beamlet_model_sink, {:model_call, self()})
    Deterministic.complete(request, invocation, context)
  end
end

defmodule Beamlet.Agent.ScriptedModel do
  @moduledoc false
  @behaviour Beamlet.Harness.Model

  @impl true
  def validate_invocation(_invocation), do: :ok

  @impl true
  def complete(request, invocation, _context) do
    send(:beamlet_model_sink, {:model_call, self()})

    if Enum.any?(request.messages, &(&1["role"] == "tool")) do
      {:ok, %{kind: :text, content: "finished", calls: []}}
    else
      calls =
        for id <- invocation.config["calls"] || ["call-1", "call-2"] do
          %{id: id, name: "echo", arguments: %{"text" => id}}
        end

      {:ok, %{kind: :tool_calls, content: nil, calls: calls}}
    end
  end
end

defmodule Beamlet.Agent.MalformedModel do
  @moduledoc false
  @behaviour Beamlet.Harness.Model

  @impl true
  def validate_invocation(_invocation), do: :ok

  @impl true
  def complete(_request, _invocation, _context), do: {:ok, %{kind: "text", content: "x"}}
end

defmodule Beamlet.Agent.HeldTool do
  @moduledoc false
  @behaviour Beamlet.Harness.Tool

  @impl true
  def descriptor, do: Beamlet.Harness.Tools.Deterministic.descriptor()

  @impl true
  def invoke(arguments, settings, _context) do
    send(settings.observer, {:tool_started, self()})

    receive do
      :release -> {:ok, %{text: arguments["text"]}}
    end
  end
end

defmodule Beamlet.Agent.DurableAgentTest do
  use ExUnit.Case, async: false

  alias Beamlet.Actions.Result
  alias Beamlet.Agent
  alias Beamlet.Agent.Durable
  alias Beamlet.Harness.{Catalogue, Context}

  alias Beamlet.Storage.{
    AgentRecords,
    Dataset,
    ExecutorJournalRepo,
    OperationRecords,
    SQLiteAuthorityRepo
  }

  setup do
    dir =
      Path.join(System.tmp_dir!(), "beamlet-agent-durable-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    authority = Path.join(dir, "authority.db")
    journal = Path.join(dir, "journal.db")

    authority_opts = [
      database: authority,
      peer_database: journal,
      dataset_id: Ecto.UUID.generate()
    ]

    journal_opts = [
      database: journal,
      peer_database: authority,
      dataset_id: Ecto.UUID.generate()
    ]

    {:ok, _} = Dataset.initialize(SQLiteAuthorityRepo, authority_opts)
    {:ok, _} = Dataset.initialize(ExecutorJournalRepo, journal_opts)
    Process.register(self(), :beamlet_model_sink)
    start_supervised!({Beamlet.Agent.AuthoritySupervisor, model_providers: providers()})

    on_exit(fn ->
      stop_repo(SQLiteAuthorityRepo)
      stop_repo(ExecutorJournalRepo)
      File.rm_rf!(dir)
    end)

    %{
      authority_id: Ecto.UUID.generate(),
      executor_id: Ecto.UUID.generate(),
      executor_boot_id: Ecto.UUID.generate(),
      name: "durable#{System.unique_integer([:positive])}"
    }
  end

  defp providers do
    Map.merge(Beamlet.Harness.Model.default_providers(), %{
      "counting" => Beamlet.Agent.CountingModel,
      "scripted" => Beamlet.Agent.ScriptedModel,
      "malformed" => Beamlet.Agent.MalformedModel
    })
  end

  defp stop_repo(repo) do
    if pid = Process.whereis(repo), do: Supervisor.stop(pid)
    :ok
  catch
    _, _ -> :ok
  end

  defp uuid, do: Ecto.UUID.generate()

  defp model_binding(opts \\ []) do
    %{
      provider: Keyword.get(opts, :provider, "counting"),
      config:
        Keyword.get(
          opts,
          :config,
          %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
        )
    }
  end

  defp definition(overrides \\ %{}) do
    base = %{
      "schema_version" => 1,
      "model" => %{"provider" => "counting", "config" => %{"model" => "m1"}},
      "tools" => %{"echo" => %{"profile" => "echo-profile"}}
    }

    Map.merge(base, overrides)
  end

  defp tool_definition(overrides \\ %{}) do
    definition(
      Map.merge(
        %{
          "model" => %{"provider" => "scripted", "config" => %{}},
          "tools" => %{"echo" => %{"profile" => "echo-profile"}}
        },
        overrides
      )
    )
  end

  defp catalogue do
    {:ok, catalogue} = Catalogue.new([Beamlet.Harness.Tools.Deterministic.descriptor()])
    catalogue
  end

  defp tools, do: %{"echo" => %{id: "echo-profile", capability: "echo"}}

  # The durable Agent's own view of the Runtime it dispatches Tools through.
  defp runtime_config(ctx) do
    %{
      authority_repo: SQLiteAuthorityRepo,
      journal_repo: ExecutorJournalRepo,
      executor_id: ctx.executor_id,
      executor_boot_id: ctx.executor_boot_id
    }
  end

  defp boot_runtime(ctx, opts \\ []) do
    tool = Keyword.get(opts, :tool, Beamlet.Harness.Tools.Deterministic)

    persistence =
      Beamlet.Runtime.Persistence.new(
        authority_repo: SQLiteAuthorityRepo,
        journal_repo: ExecutorJournalRepo,
        authority_id: ctx.authority_id,
        executor_id: ctx.executor_id,
        executor_boot_id: ctx.executor_boot_id
      )

    settings = %{
      model_providers: providers(),
      profiles: %{
        "echo-profile" => %{
          type: :tool,
          module: tool,
          settings: Keyword.get(opts, :tool_settings, %{})
        }
      }
    }

    runtime_opts =
      if Keyword.get(opts, :persistence, true) do
        [persistence: persistence]
      else
        []
      end

    runtime_opts =
      Keyword.merge(
        [
          execution: true,
          handlers: %{"agent.native" => {Beamlet.Agent.Integration.Handler, settings}},
          capabilities: [
            "model.provider:counting",
            "model.provider:scripted",
            "model.provider:malformed",
            "echo"
          ],
          limits: Keyword.merge([refresh_ms: 10, expiry_ms: 300], Keyword.get(opts, :limits, []))
        ],
        runtime_opts
      )

    pid = start_supervised!({Beamlet.Runtime, runtime_opts})

    eventually(fn ->
      assert Enum.any?(Beamlet.Runtime.Directory.snapshots(), fn {_, report} ->
               "echo" in report.capabilities
             end)
    end)

    pid
  end

  defp open(ctx, definition, alias_name) do
    Durable.open(SQLiteAuthorityRepo, %{
      agent_id: uuid(),
      authority_id: ctx.authority_id,
      alias: alias_name || ctx.name,
      definition: definition,
      command_id: uuid()
    })
  end

  defp start_durable(ctx, opts \\ []) do
    definition = Keyword.get(opts, :definition, definition())
    alias_name = Keyword.get(opts, :alias, ctx.name)
    {:ok, durable} = open(ctx, definition, alias_name)

    durable =
      case Keyword.get(opts, :runtime, runtime_config(ctx)) do
        nil -> durable
        runtime -> elem(Durable.with_runtime(durable, runtime), 1)
      end

    if Keyword.get(opts, :start, true) do
      {:ok, ref} =
        Agent.start(node(),
          id: alias_name,
          model: Keyword.get(opts, :model, model_binding()),
          tools: tools(),
          catalogue: catalogue(),
          durable: durable
        )

      {durable, ref}
    else
      {durable, nil}
    end
  end

  defp locator(ctx, durable, extra \\ []) do
    Map.merge(
      %{
        repo: SQLiteAuthorityRepo,
        agent_id: durable.agent_id,
        model: model_binding(),
        tools: tools(),
        catalogue: catalogue(),
        runtime: runtime_config(ctx)
      },
      Map.new(extra)
    )
  end

  defp model_calls do
    receive do
      {:model_call, _} -> 1 + model_calls()
    after
      0 -> 0
    end
  end

  defp drain_model_calls(acc \\ 0) do
    receive do
      {:model_call, _} -> drain_model_calls(acc + 1)
    after
      0 -> acc
    end
  end

  defp messages(durable) do
    {:ok, %{"head_checkpoint" => head}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    head["data"]["messages"]
  end

  defp head(durable) do
    {:ok, %{"head_checkpoint" => head, "agent" => agent}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    {head, agent}
  end

  defp events(durable) do
    {:ok, %{"events" => events}} =
      AgentRecords.history_page(SQLiteAuthorityRepo, durable.agent_id, limit: 500)

    events
  end

  defp accept_input(durable, text) do
    {:ok, messages} = Context.append(messages(durable), [%{"role" => "user", "content" => text}])

    Durable.accept_input(durable, %{
      command_id: uuid(),
      turn_id: uuid(),
      messages: messages,
      checkpoint_id: uuid()
    })
  end

  defp current_version(durable) do
    {:ok, %{"agent" => agent}} = AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)
    agent["lock_version"]
  end

  defp accept_result(durable, operation, value) do
    {:ok, %{"operation" => stored}} =
      OperationRecords.fetch(SQLiteAuthorityRepo, operation["operation_id"])

    {:ok, %{"agent" => agent}} = AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    OperationRecords.accept_result(SQLiteAuthorityRepo, %{
      operation_id: operation["operation_id"],
      expected_version: stored["lock_version"],
      agent: %{
        expected_generation: agent["generation"],
        accept_seq: operation["accept_seq"]
      },
      result: %{"status" => "ok", "value" => value, "reason" => nil},
      event: %{
        id: uuid(),
        type: "operation.result_accepted",
        payload: %{"operation_id" => operation["operation_id"]}
      }
    })
  end

  defp batch(durable, calls, step \\ 1) do
    assistant = %{
      "role" => "assistant",
      "content" => nil,
      "calls" =>
        Enum.map(calls, fn call ->
          %{"id" => call.id, "name" => call.name, "arguments" => call.arguments}
        end)
    }

    {:ok, messages} = Context.append(messages(durable), [assistant])

    operations =
      Enum.map(calls, fn call ->
        {:ok, operation} =
          Beamlet.Agent.Integration.Caller.operation(
            tools()[call.name],
            call.arguments,
            262_144
          )

        %{id: call.id, operation: operation}
      end)

    Durable.prepare_batch(durable, %{
      calls: operations,
      messages: messages,
      step: step,
      checkpoint_id: uuid()
    })
  end

  defp calls,
    do: [
      %{id: "call-1", name: "echo", arguments: %{"text" => "first"}},
      %{id: "call-2", name: "echo", arguments: %{"text" => "second"}}
    ]

  defp eventually(fun, attempts \\ 400)

  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    fun.()
  rescue
    _ -> retry(fun, attempts)
  catch
    _, _ -> retry(fun, attempts)
  end

  defp retry(fun, attempts) do
    Process.sleep(10)
    eventually(fun, attempts - 1)
  end

  defp injected_result(operation_id) do
    %Result{
      operation_id: operation_id,
      execution_id: nil,
      status: :uncertain,
      reason: :uncertain_external_effect,
      source: :coordinator,
      metadata: %{}
    }
  end

  test "input acceptance commits the turn and checkpoint, and a repeated command replays", ctx do
    {durable, _ref} = start_durable(ctx)
    command = uuid()
    turn_id = uuid()
    user = [%{"role" => "user", "content" => "hello"}]
    attrs = %{command_id: command, turn_id: turn_id, messages: user, checkpoint_id: uuid()}

    assert {:ok, first} = Durable.accept_input(durable, attrs)
    refute first.replayed?

    # The committed head checkpoint already carries the new turn and continuation,
    # so a crash here can never reach the model without the stored turn.
    {:ok, %{"head_checkpoint" => head}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    assert head["data"]["continuation"] == "await_model_result"
    assert head["turn_id"] == turn_id
    assert head["data"]["messages"] == user

    assert %{"type" => "input.accepted"} =
             Enum.find(events(durable), &(&1["type"] == "input.accepted"))

    assert {:ok, replay} = Durable.accept_input(durable, %{attrs | checkpoint_id: uuid()})
    assert replay.replayed?
    assert replay.turn_id == turn_id
    assert Enum.count(events(durable), &(&1["type"] == "input.accepted")) == 1

    other = [%{"role" => "user", "content" => "different"}]

    assert {:error, :conflict} =
             Durable.accept_input(durable, %{attrs | messages: other, checkpoint_id: uuid()})
  end

  test "the complete reply is committed before validation and is re-validated without a model request",
       ctx do
    {durable, _ref} = start_durable(ctx)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    reply = %{"kind" => "text", "content" => "stored", "calls" => []}

    assert {:ok, %{version: version}} =
             Durable.record_reply(durable, %{
               request: %{"messages" => messages(durable), "catalogue" => %{}},
               messages: messages(durable),
               reply: reply,
               checkpoint_id: uuid(),
               step: 1
             })

    durable = %{durable | version: version}
    assert Enum.any?(events(durable), &(&1["type"] == "model.reply_recorded"))

    assert {:ok, restored} = Durable.restore(locator(ctx, durable), version, uuid())
    assert restored.checkpoint["continuation"] == "reply_recorded"
    assert restored.checkpoint["assistant"] == reply
    assert model_calls() == 0
  end

  test "an illegal batch commits zero Operations", ctx do
    {durable, _ref} = start_durable(ctx)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    duplicate = [
      %{id: "call-1", name: "echo", arguments: %{"text" => "a"}},
      %{id: "call-1", name: "echo", arguments: %{"text" => "b"}}
    ]

    assert {:error, :invalid_data} = batch(durable, duplicate)

    {:ok, %{"events" => events}} =
      AgentRecords.history_page(SQLiteAuthorityRepo, durable.agent_id, limit: 500)

    refute Enum.any?(events, &(&1["type"] == "operation.prepared"))
  end

  test "out-of-order results join in ordinal order and consume exactly once", ctx do
    {durable, _ref} = start_durable(ctx)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    assert {:ok, batch_response} = batch(durable, calls(), 1)
    durable = %{durable | version: batch_response.version}
    [first, second] = batch_response.operations
    assert second["ordinal"] == 2

    # The batch checkpoint carries the real model step, never nil.
    {head, _agent} = head(durable)
    assert head["data"]["step"] == 1
    assert head["turn_id"] == durable.turn_id

    assert {:ok, _} = accept_result(durable, second, %{"text" => "second"})
    assert {:ok, _} = accept_result(durable, first, %{"text" => "first"})

    observations =
      [first, second]
      |> Enum.sort_by(& &1["ordinal"])
      |> Enum.map(fn operation ->
        %{
          "role" => "tool",
          "call_id" => operation["tool_call_id"],
          "content" => Jason.encode!(%{"status" => "ok", "value" => %{"text" => nil}})
        }
      end)

    {:ok, tool_messages} = Context.append(messages(durable), observations)

    attrs = %{
      operations: Enum.map([second, first], &%{operation_id: &1["operation_id"]}),
      messages: tool_messages,
      order: ["call-1", "call-2"],
      checkpoint_id: uuid()
    }

    assert {:ok, consumed} = Durable.consume_results(durable, attrs)

    assert Enum.map(consumed.consumed, & &1["operation_id"]) ==
             [first["operation_id"], second["operation_id"]]

    assert [%{"call_id" => "call-1"}, %{"call_id" => "call-2"}] =
             Enum.filter(messages(durable), &(&1["role"] == "tool"))

    assert {:ok, replay} = Durable.consume_results(durable, attrs)
    assert replay.consumed == consumed.consumed

    assert Enum.count(events(durable), &(&1["type"] == "result.consumed")) == 2
  end

  test "a source Agent Operation is not consumable", ctx do
    {durable, _ref} = start_durable(ctx)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}
    {:ok, batch_response} = batch(durable, [%{id: "call-1", name: "echo", arguments: %{}}])
    [operation] = batch_response.operations
    assert {:ok, _} = accept_result(durable, operation, %{"text" => "x"})

    {:ok, other} = open(ctx, definition(), ctx.name <> "-other")
    {:ok, other_input} = accept_input(other, "other")
    other = %{other | turn_id: other_input.turn_id, version: current_version(other)}

    assert {:error, :conflict} =
             Durable.consume_results(other, %{
               operations: [%{operation_id: operation["operation_id"]}],
               messages: [],
               order: ["call-1"],
               checkpoint_id: uuid()
             })
  end

  test "durable Tool dispatch binds the prepared attempt and consumes real Results", ctx do
    boot_runtime(ctx)

    {durable, ref} =
      start_durable(ctx,
        definition: tool_definition(),
        model: model_binding(provider: "scripted", config: %{})
      )

    assert {:ok, turn} = Agent.input(ref, "run the batch", uuid())

    eventually(fn ->
      assert {:ok, %{status: :done, final: "finished"}} = Agent.snapshot(ref)
    end)

    # Two model steps: the tool batch and the final reply. No third dispatch.
    assert drain_model_calls() == 2

    {head, _agent} = head(durable)
    assert head["turn_id"] == turn
    assert head["data"]["continuation"] == "reply_recorded"
    refute Enum.any?(head["data"]["messages"], &(&1["role"] == "tool" and is_nil(&1["content"])))

    consumed = Enum.filter(events(durable), &(&1["type"] == "result.consumed"))
    assert Enum.map(consumed, & &1["payload"]["ordinal"]) == [1, 2]

    prepared = Enum.filter(events(durable), &(&1["type"] == "operation.prepared"))
    assert length(prepared) == 2
    assert Enum.all?(prepared, &(&1["turn_id"] == turn))

    for event <- prepared do
      operation_id = event["payload"]["operation_id"]

      assert {:ok, %{"operation" => stored}} =
               OperationRecords.fetch(SQLiteAuthorityRepo, operation_id)

      # The dispatched Runtime operation wrote the accepted Result onto this row.
      assert stored["accepted_result"]["status"] == "ok"
      assert stored["accepted_result"]["source"] == "execution"
    end

    # A restore of the finished turn reports confirmed Results, never
    # `unconfirmed_tool_result`.
    assert {:ok, restored} =
             Durable.restore(
               locator(ctx, durable, model: model_binding(provider: "scripted", config: %{})),
               current_version(durable),
               uuid()
             )

    assert restored.checkpoint["continuation"] == "reply_recorded"
    assert restored.checkpoint["pending"] == []
  end

  test "an uncertain Tool Result blocks the turn with no further model or Tool work", ctx do
    boot_runtime(ctx, tool: Beamlet.Agent.HeldTool, tool_settings: %{observer: self()})

    {durable, ref} =
      start_durable(ctx,
        definition: tool_definition(),
        model: model_binding(provider: "scripted", config: %{"calls" => ["call-1"]})
      )

    assert {:ok, _turn} = Agent.input(ref, "run one tool", uuid())
    assert_receive {:tool_started, _worker}, 5000

    eventually(fn ->
      assert map_size(:sys.get_state(ref.pid).pending) == 1
    end)

    [entry] = Map.values(:sys.get_state(ref.pid).pending)
    operation_id = entry.ref.id
    # The single model step that requested the batch.
    assert drain_model_calls() == 1

    send(ref.pid, {:beamlet_operation, entry.ref, {:result, injected_result(operation_id)}})

    eventually(fn ->
      assert {:ok, %{status: :paused, final: :uncertain_external_effect}} = Agent.snapshot(ref)
    end)

    # No tool message was appended, no further model or Tool work was requested.
    {head, _agent} = head(durable)
    assert head["data"]["continuation"] == "blocked"
    assert head["data"]["blocked"] == %{"reason" => "uncertain_external_effect"}
    refute Enum.any?(head["data"]["messages"], &(&1["role"] == "tool"))
    assert drain_model_calls() == 0
    refute_receive {:tool_started, _worker}, 200

    # The block is reachable: a decision returns the instance to `await_input`
    # and is recorded exactly once.
    version = current_version(durable)
    assert {:error, {:blocked, :unresolved_effect}} = Agent.continue(ref, version, %{}, uuid())

    command = uuid()

    assert {:ok, %{status: :idle}} =
             Agent.continue(ref, version, %{"resolution" => "confirmed_failed"}, command)

    assert {:error, :not_paused} =
             Agent.continue(ref, version, %{"resolution" => "confirmed_failed"}, command)

    decisions = Enum.filter(events(durable), &(&1["type"] == "agent.decision"))
    assert length(decisions) == 1
    assert hd(decisions)["payload"]["decision"] == "confirmed_failed"
    assert drain_model_calls() == 0
  end

  test "a durable Agent without the Runtime section blocks before any Tool dispatch", ctx do
    boot_runtime(ctx, persistence: false)

    {durable, ref} =
      start_durable(ctx,
        definition: tool_definition(),
        model: model_binding(provider: "scripted", config: %{}),
        runtime: nil
      )

    assert {:ok, _turn} = Agent.input(ref, "run the batch", uuid())

    eventually(fn ->
      assert {:ok, %{status: :paused, final: :missing_durable_runtime}} = Agent.snapshot(ref)
    end)

    # Nothing was prepared and nothing was dispatched ephemerally.
    refute Enum.any?(events(durable), &(&1["type"] == "operation.prepared"))
    {head, _agent} = head(durable)
    assert head["data"]["blocked"] == %{"reason" => "missing_durable_runtime"}
    assert drain_model_calls() == 1
  end

  test "duplicate restores leave a survivor that can still commit", ctx do
    boot_runtime(ctx)
    {durable, _ref} = start_durable(ctx, start: false)
    {:ok, accepted} = accept_input(durable, "restore me")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}
    version = current_version(durable)

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.async(fn -> Agent.restore(locator(ctx, durable), version, uuid()) end)
      end)
      |> Enum.map(&Task.await(&1, 5000))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    assert [{_id, _pid}] = Registry.lookup(Beamlet.Agent.Registry, ctx.name) |> Enum.take(1)

    # Exactly one generation was committed by the two attempts.
    assert Enum.count(events(durable), &(&1["type"] == "agent.restored")) == 1

    # The survivor still commits: the decision is recorded and the turn advances.
    {:ok, survivor} = Enum.find(results, &match?({:ok, _}, &1))

    assert {:ok, %{status: _}} =
             Agent.continue(survivor, current_version(durable), %{}, uuid())

    eventually(fn ->
      assert {:ok, %{status: :done}} = Agent.snapshot(survivor)
    end)

    assert Enum.count(events(durable), &(&1["type"] == "agent.decision")) == 1
    assert drain_model_calls() == 1
  end

  test "an already active instance rejects a fresh restore before the generation bump", ctx do
    boot_runtime(ctx)
    {durable, ref} = start_durable(ctx)
    version = current_version(durable)

    assert {:error, :already_active} = Agent.restore(locator(ctx, durable), version, uuid())
    assert {:ok, %{status: :idle}} = Agent.snapshot(ref)

    {_head, agent} = head(durable)
    assert agent["generation"] == 0
    refute Enum.any?(events(durable), &(&1["type"] == "agent.restored"))

    assert {:ok, turn} = Agent.input(ref, "after the rejection", uuid())

    eventually(fn ->
      {head, _agent} = head(durable)
      assert head["turn_id"] == turn
      assert {:ok, %{status: :done}} = Agent.snapshot(ref)
    end)
  end

  test "a mid-turn checkpoint restores mid-turn and still advances", ctx do
    boot_runtime(ctx)
    {durable, _ref} = start_durable(ctx, definition: tool_definition(), start: false)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    assert {:ok, batch_response} =
             batch(durable, [%{id: "call-1", name: "echo", arguments: %{"text" => "one"}}], 1)

    durable = %{durable | version: batch_response.version, step: 1}
    [operation] = batch_response.operations
    assert {:ok, _} = accept_result(durable, operation, %{"text" => "one"})

    {:ok, tool_messages} =
      Context.append(messages(durable), [
        %{"role" => "tool", "call_id" => "call-1", "content" => ~s({"status":"ok"})}
      ])

    assert {:ok, consumed} =
             Durable.consume_results(durable, %{
               operations: [%{operation_id: operation["operation_id"]}],
               messages: tool_messages,
               order: ["call-1"],
               step: 2,
               checkpoint_id: uuid()
             })

    durable = %{durable | version: consumed.version}
    locator = locator(ctx, durable, model: model_binding(provider: "scripted", config: %{}))

    assert {:ok, restored} = Durable.restore(locator, current_version(durable), uuid())
    assert restored.checkpoint["continuation"] == "await_model_result"
    assert restored.checkpoint["step"] == 2

    assert {:ok, paused} = Agent.restore(locator, current_version(durable), uuid())
    assert {:ok, %{status: :paused, steps: 2}} = Agent.snapshot(paused)

    # Advancing resumes at step 2, well below the 16-step ceiling.
    assert {:ok, %{status: :running}} =
             Agent.continue(paused, current_version(durable), %{}, uuid())

    eventually(fn ->
      assert {:ok, %{status: :done, final: "finished"}} = Agent.snapshot(paused)
    end)

    assert drain_model_calls() == 1
  end

  test "a malformed provider reply blocks with a safe reason instead of crashing", ctx do
    boot_runtime(ctx)

    {durable, ref} =
      start_durable(ctx, model: model_binding(provider: "malformed", config: %{}))

    assert {:ok, _turn} = Agent.input(ref, "reply badly", uuid())

    eventually(fn ->
      assert {:ok, %{status: :paused, final: :invalid_reply}} = Agent.snapshot(ref)
    end)

    assert Process.alive?(ref.pid)
    {head, _agent} = head(durable)
    assert head["data"]["blocked"] == %{"reason" => "invalid_reply"}
  end

  test "stopping an idle durable instance writes no blocked checkpoint", ctx do
    {durable, ref} = start_durable(ctx)
    _ = durable

    assert :ok = Agent.stop_turn(ref)
    assert {:ok, %{status: :stopped}} = Agent.snapshot(ref)

    refute Enum.any?(events(durable), &(&1["type"] == "agent.blocked"))
    {head, _agent} = head(durable)
    assert head["data"]["continuation"] == "await_input"
  end

  test "every implemented continuation restores a paused instance with no calls", ctx do
    {durable, _ref} = start_durable(ctx, start: false)

    assert {:ok, restored} =
             Durable.restore(locator(ctx, durable), current_version(durable), uuid())

    assert restored.checkpoint["continuation"] == "await_input"
    assert {:ok, paused} = Agent.restore(locator(ctx, durable), current_version(durable), uuid())
    assert {:ok, %{status: :paused}} = Agent.snapshot(paused)
    assert model_calls() == 0

    # await_model_result
    {durable, _ref} = start_durable(%{ctx | name: ctx.name <> "-model"}, start: false)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    assert {:ok, restored} =
             Durable.restore(locator(ctx, durable), current_version(durable), uuid())

    assert restored.checkpoint["continuation"] == "await_model_result"
    assert {:ok, paused} = Agent.restore(locator(ctx, durable), current_version(durable), uuid())
    assert {:ok, %{status: :paused, turn: turn}} = Agent.snapshot(paused)
    assert turn == accepted.turn_id
    assert model_calls() == 0

    # reply_recorded
    {durable, _ref} = start_durable(%{ctx | name: ctx.name <> "-reply"}, start: false)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    assert {:ok, reply_response} =
             Durable.record_reply(durable, %{
               request: %{"messages" => messages(durable)},
               messages: messages(durable),
               reply: %{"kind" => "text", "content" => "stored", "calls" => []},
               checkpoint_id: uuid(),
               step: 1
             })

    durable = %{durable | version: reply_response.version}

    assert {:ok, restored} =
             Durable.restore(locator(ctx, durable), current_version(durable), uuid())

    assert restored.checkpoint["continuation"] == "reply_recorded"
    assert {:ok, paused} = Agent.restore(locator(ctx, durable), current_version(durable), uuid())
    assert {:ok, %{status: :paused}} = Agent.snapshot(paused)

    assert {:ok, %{status: :done}} =
             Agent.continue(paused, current_version(durable), %{}, uuid())

    assert model_calls() == 0

    # await_tool_results with every accepted Result present
    {durable, _ref} = start_durable(%{ctx | name: ctx.name <> "-tools"}, start: false)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    assert {:ok, batch_response} =
             batch(durable, [%{id: "call-1", name: "echo", arguments: %{"text" => "a"}}])

    durable = %{durable | version: batch_response.version}
    [operation] = batch_response.operations
    assert {:ok, _} = accept_result(durable, operation, %{"text" => "a"})

    assert {:ok, restored} =
             Durable.restore(locator(ctx, durable), current_version(durable), uuid())

    assert restored.checkpoint["continuation"] == "await_tool_results"
    assert {:ok, paused} = Agent.restore(locator(ctx, durable), current_version(durable), uuid())
    assert {:ok, %{status: :paused}} = Agent.snapshot(paused)
    assert model_calls() == 0

    # An unsupported position is refused before anything is written.
    assert {:error, {:unsupported_continuation, "await_tool_results"}} =
             Agent.continue(paused, current_version(durable), %{}, uuid())

    refute Enum.any?(events(durable), &(&1["type"] == "agent.decision"))
  end

  test "a missing dependency or artifact blocks the restore with zero dispatch", ctx do
    secret_definition =
      definition(%{"model" => %{"provider" => "counting", "secret_ref" => "vault-1"}})

    {:ok, secret_durable} = open(ctx, secret_definition, ctx.name <> "-secret")

    assert {:error, {:blocked, :missing_secret}} =
             Agent.restore(
               locator(ctx, secret_durable,
                 model: %{provider: "counting", config: %{}, credentials: %{}}
               ),
               secret_durable.version,
               uuid()
             )

    artifact_definition =
      definition(%{
        "tools" => %{"echo" => %{"profile" => "echo-profile", "artifact_refs" => [uuid()]}}
      })

    {:ok, artifact_durable} = open(ctx, artifact_definition, ctx.name <> "-artifact")

    assert {:error, {:blocked, :artifact_missing}} =
             Agent.restore(
               locator(ctx, artifact_durable),
               current_version(artifact_durable),
               uuid()
             )

    assert model_calls() == 0
    assert Registry.lookup(Beamlet.Agent.Registry, ctx.name <> "-secret") == []
    assert Registry.lookup(Beamlet.Agent.Registry, ctx.name <> "-artifact") == []
  end

  test "an uncertain external effect blocks progression until an explicit decision", ctx do
    {durable, _ref} = start_durable(ctx, start: false)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    assert {:ok, blocked} = Durable.block(durable, :uncertain_external_effect)
    durable = %{durable | version: blocked.version}

    assert {:ok, paused} = Agent.restore(locator(ctx, durable), current_version(durable), uuid())
    assert {:ok, %{status: :paused}} = Agent.snapshot(paused)

    assert {:error, {:blocked, :unresolved_effect}} =
             Agent.continue(paused, current_version(durable), %{}, uuid())

    assert model_calls() == 0

    assert {:ok, _snapshot} =
             Agent.continue(
               paused,
               current_version(durable),
               %{"resolution" => "confirmed_failed"},
               uuid()
             )

    assert {:ok, %{status: :idle}} = Agent.snapshot(paused)
    assert model_calls() == 0
  end

  test "restore rebuilds display annotations for restored messages", ctx do
    {durable, _ref} = start_durable(ctx, start: false)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    assert {:ok, paused} = Agent.restore(locator(ctx, durable), current_version(durable), uuid())
    stored = messages(durable)
    assert length(stored) == 1

    assert {:ok, %{display: display}} = Agent.snapshot(paused, view: :display)
    assert [%{role: "user", content: "hello"}] = display.entries
  end

  test "display data is absent from persisted rows", ctx do
    {durable, ref} = start_durable(ctx)
    {:ok, accepted} = accept_input(durable, "hello")
    durable = %{durable | turn_id: accepted.turn_id, version: accepted.version}

    assert {:ok, reply_response} =
             Durable.record_reply(durable, %{
               request: %{"messages" => messages(durable)},
               messages: messages(durable),
               reply: %{"kind" => "text", "content" => "stored", "calls" => []},
               checkpoint_id: uuid(),
               step: 1
             })

    _durable = %{durable | version: reply_response.version}

    {:ok, %{"agent" => agent, "head_checkpoint" => head}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    checkpoint = head["data"]
    refute Map.has_key?(checkpoint, "display")
    refute Map.has_key?(checkpoint, "display_entries")
    refute Map.has_key?(checkpoint, "subscribers")
    refute Map.has_key?(checkpoint, "annotation")
    refute Map.has_key?(agent, "pid")
    refute inspect(head) =~ "#PID"
    refute inspect(head) =~ "#Reference"

    # Display is rebuilt by the live Server, never read back from storage.
    assert {:ok, %{status: _} = view} = Agent.snapshot(ref)
    assert is_map(view)
  end
end
