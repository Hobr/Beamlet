Code.require_file("../../../beamlet_storage/test/support/contract_fixture.ex", __DIR__)

defmodule Beamlet.Agent.DurableTestModel do
  @moduledoc false
  @behaviour Beamlet.Harness.Model
  def validate_invocation(_), do: :ok

  def complete(request, invocation, _) do
    send(:beamlet_durable_test_sink, {:model_call, request})

    if invocation.config["wait"] do
      send(:beamlet_durable_test_sink, {:model_waiting, self()})

      receive do
        :release -> :ok
      end
    end

    if invocation.config["tools"] and not Enum.any?(request.messages, &(&1["role"] == "tool")) do
      {:ok,
       %{
         kind: :tool_calls,
         content: nil,
         calls: [
           %{id: "one", name: "echo", arguments: %{"text" => "first"}},
           %{id: "two", name: "echo", arguments: %{"text" => "second"}}
         ]
       }}
    else
      {:ok, %{kind: :text, content: "finished", calls: []}}
    end
  end
end

defmodule Beamlet.Agent.DurableWaitingTool do
  @moduledoc false
  alias Beamlet.Harness.Tools.Deterministic
  def descriptor, do: Deterministic.descriptor()

  def invoke(arguments, _, _) do
    send(:beamlet_durable_test_sink, {:tool_waiting, self(), arguments})

    receive do
      :release -> {:ok, arguments}
    end
  end
end

defmodule Beamlet.Agent.DurableAgentTest do
  use ExUnit.Case, async: false
  import Kernel, except: [binding: 0, binding: 1]
  alias Beamlet.Actions.Result
  alias Beamlet.Agent
  alias Beamlet.Agent.{ContextBuilder, Durable, Loader, Reducer}
  alias Beamlet.Agent.Integration.Caller
  alias Beamlet.Harness.{Catalogue, Model}
  alias Beamlet.Harness.Tools.Deterministic
  alias Beamlet.Runtime.{Directory, Persistence}

  alias Beamlet.Storage.{
    AgentRecords,
    Codec,
    ContractFixture,
    Dataset,
    Events,
    ExecutorJournalRepo,
    OperationRecords,
    Transaction
  }

  alias Ecto.Adapters.SQL

  setup do
    dir = Path.join(System.tmp_dir!(), "beamlet-c-#{Ecto.UUID.generate()}")
    File.mkdir_p!(dir)

    backend =
      if System.get_env("BEAMLET_AGENT_TEST_ADAPTER") == "postgres", do: :postgres, else: :sqlite

    fixture = ContractFixture.open(backend)
    repo = fixture.repo
    authority = fixture.authority_id

    {:ok, _} =
      Dataset.initialize(ExecutorJournalRepo,
        database: Path.join(dir, "j.db"),
        peer_database: Path.join(dir, "a.db"),
        dataset_id: Ecto.UUID.generate()
      )

    Process.register(self(), :beamlet_durable_test_sink)
    providers = Map.put(Model.default_providers(), "scripted", Beamlet.Agent.DurableTestModel)
    start_supervised!({Agent.AuthoritySupervisor, model_providers: providers})

    runtime = %{
      authority_repo: repo,
      journal_repo: ExecutorJournalRepo,
      executor_id: Ecto.UUID.generate(),
      executor_boot_id: Ecto.UUID.generate()
    }

    {:ok, durable} =
      Durable.open(repo, %{
        agent_id: Ecto.UUID.generate(),
        authority_id: authority,
        definition: %{"version" => 1},
        command_id: Ecto.UUID.generate()
      })

    {:ok, durable} = Durable.with_runtime(durable, runtime)

    on_exit(fn ->
      stop_repo(ExecutorJournalRepo)
      ContractFixture.close(fixture)
      File.rm_rf!(dir)
    end)

    %{durable: durable, providers: providers}
  end

  defp stop_repo(repo) do
    if pid = Process.whereis(repo) do
      monitor = Process.monitor(pid)

      try do
        Supervisor.stop(pid)
      catch
        :exit, _ -> :ok
      end

      receive do
        {:DOWN, ^monitor, :process, ^pid, _} -> :ok
      after
        5000 -> flunk("Repo did not stop")
      end
    end
  end

  defp binding(tools \\ false), do: %{provider: "scripted", config: %{"tools" => tools}}

  defp input(d) do
    Durable.accept_input(d, %{
      text: "hello",
      turn_id: Ecto.UUID.generate(),
      command_id: Ecto.UUID.generate()
    })
  end

  defp locator(d), do: %{repo: d.repo, agent_id: d.agent_id, model: binding(), runtime: d.runtime}

  defp version(d) do
    {:ok, %{"agent" => a}} = AgentRecords.fetch(d.repo, d.agent_id)
    a["lock_version"]
  end

  defp boot(ctx, tool_module \\ Deterministic, persistent \\ true) do
    {:ok, p} = Durable.persistence(ctx.durable, nil)

    start_supervised!(
      {Beamlet.Runtime,
       execution: true,
       persistence: if(persistent, do: p),
       handlers: %{
         "agent.native" =>
           {Agent.Integration.Handler,
            %{
              model_providers: ctx.providers,
              profiles: %{
                "echo" => %{
                  type: :tool,
                  module: tool_module,
                  settings: %{}
                }
              }
            }}
       },
       capabilities: ["model.provider:scripted", "echo"],
       limits: [refresh_ms: 10, expiry_ms: 300]}
    )

    eventually(fn -> assert map_size(Directory.snapshots()) > 0 end)
  end

  defp eventually(fun, count \\ 400)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, count) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(10)
      eventually(fun, count - 1)
  end

  defp prepare(d) do
    {:ok, built} = Durable.context(d, %{})
    {:ok, op} = Caller.operation(binding(), built.request, 262_144)
    {:ok, next, [member]} = Durable.prepare(d, [%{operation: op}], "model", built.sources)
    {next, op, member}
  end

  defp accept(d, member) do
    OperationRecords.accept_result(d.repo, %{
      operation_id: member["operation_id"],
      expected_version: 0,
      result: %{
        "status" => "ok",
        "value" => %{"kind" => "text", "content" => "saved", "calls" => []},
        "reason" => nil
      }
    })
  end

  test "original input survives before any preparation; replay has zero effects", %{durable: d} do
    {:ok, d} = input(d)
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert loaded.control == d.control
    assert {:ok, %{request: %{"messages" => [%{"content" => "hello"}]}}} = Durable.context(d, %{})
    assert {:ok, restored} = Durable.restore(locator(d), d.version, Ecto.UUID.generate())
    assert restored.control["paused"]
    assert restored.control["continuation"] == "await_model_result"
    refute_receive {:model_call, _}
  end

  test "atomic preparation owns immutable logical requests and consumption only references", %{
    durable: d
  } do
    {:ok, d} = input(d)
    {d, op, member} = prepare(d)

    assert {:ok, %{"operation" => stored}} =
             OperationRecords.fetch(d.repo, member["operation_id"])

    assert stored["description"] == Persistence.description(op)
    assert stored["owner_agent_id"] == d.agent_id
    assert {:ok, _} = accept(d, member)
    assert {:ok, d} = Durable.consume(d, [member["operation_id"]], "completed")
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert loaded.control == d.control
    assert {:ok, built} = Durable.context(d, %{})
    assert List.last(built.request["messages"])["content"] == "saved"
    refute inspect(d.control) =~ "saved"
    assert {:error, _} = Durable.consume(d, [member["operation_id"]], "completed")
  end

  test "unknown version and sequence gaps refuse reduction", %{durable: d} do
    {:ok, %{"events" => [created]}} = AgentRecords.history_page(d.repo, d.agent_id)

    assert {:error, :schema_unsupported} =
             Reducer.reduce(Reducer.new(d.agent_id), %{created | "schema_version" => 2})

    assert {:error, :invalid_history} =
             Reducer.reduce(Reducer.new(d.agent_id), %{created | "seq" => 2})
  end

  test "corrupt accepted bodies block inspect before consumption", %{durable: d} do
    {:ok, d} = input(d)
    {d, _, member} = prepare(d)
    assert {:ok, _} = accept(d, member)

    SQL.query!(d.repo, "UPDATE events SET payload = $1 WHERE scope_id = $2 AND seq = 2", [
      Jason.encode!(%{"accepted_digest" => String.duplicate("0", 64)}),
      member["operation_id"]
    ])

    assert {:error, :invalid_reference} = Durable.inspect(locator(d))

    assert {:error, :invalid_reference} =
             Durable.restore(locator(d), d.version, Ecto.UUID.generate())

    assert version(d) == d.version
    refute_receive {:model_call, _}
  end

  test "unconsumed accepted output cannot enter context or a new request", %{durable: d} do
    {:ok, d} = input(d)
    {d, _, member} = prepare(d)
    assert {:ok, accepted} = accept(d, member)
    assert {:ok, built} = Durable.context(d, %{})
    assert built.request["messages"] == [%{"role" => "user", "content" => "hello"}]
    assert length(built.sources) == 1

    source = %{
      "type" => "accepted_result",
      "reference" => %{
        "operation_id" => member["operation_id"],
        "accepted_digest" => accepted["accepted_digest"],
        "consumption_kind" => "model_result"
      }
    }

    {:ok, op} = Caller.operation(binding(), built.request, 262_144)
    assert {:error, _} = Durable.prepare(d, [%{operation: op}], "model", [source])
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert loaded.control == d.control
  end

  test "inspect without runtime is read only and restore without a cache stays paused", %{
    durable: d
  } do
    {:ok, d} = input(d)
    locator = Map.drop(locator(d), [:model, :runtime])
    assert {:ok, inspected} = Durable.inspect(locator)
    assert inspected.control == d.control
    assert version(d) == d.version
    assert {:ok, restored} = Durable.restore(locator, d.version, Ecto.UUID.generate())
    assert restored.control["generation"] == d.generation + 1
    assert restored.control["paused"]
    assert restored.control["pending"] == []
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id, cache: false)
    assert loaded.control == restored.control
    refute_receive {:model_call, _}
  end

  test "accepted model result resumes once without model execution", ctx do
    {:ok, d} = input(ctx.durable)
    {d, _, member} = prepare(d)
    assert {:ok, _} = accept(d, member)
    assert {:ok, ref} = Agent.restore(locator(d), d.version, Ecto.UUID.generate())
    assert {:ok, %{status: :paused}} = Agent.snapshot(ref)
    assert {:ok, _} = Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())
    assert {:ok, %{status: :done, final: "saved"}} = Agent.snapshot(ref)
    refute_receive {:model_call, _}
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert length(loaded.control["consumed"]) == 1
  end

  test "uncertain accepted model output requires an explicit decision and is never overwritten",
       %{
         durable: d
       } do
    {:ok, d} = input(d)
    {d, _, member} = prepare(d)
    result = %{"status" => "uncertain", "reason" => "lost", "value" => nil}

    assert {:ok, _} =
             OperationRecords.accept_result(d.repo, %{
               operation_id: member["operation_id"],
               expected_version: 0,
               result: result
             })

    assert {:ok, ref} = Agent.restore(locator(d), d.version, Ecto.UUID.generate())

    assert {:error, :unresolved_execution} =
             Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())

    assert {:ok, %{status: :paused}} = Agent.snapshot(ref)
    decision = %{"operation_id" => member["operation_id"], "resolution" => "confirmed_failed"}
    assert {:ok, _} = Agent.continue(ref, version(d), decision, Ecto.UUID.generate())
    assert {:ok, %{status: :done}} = Agent.snapshot(ref)

    assert {:ok, %{"operation" => stored}} =
             OperationRecords.fetch(d.repo, member["operation_id"])

    assert stored["accepted_result"] == result
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert [%{"consumption_kind" => "evidence_resolution"}] = loaded.control["consumed"]
    refute_receive {:model_call, _}
  end

  test "input and ordinary context enforce their exact text and message boundaries", %{durable: d} do
    attrs = %{
      text: String.duplicate("a", 65_536),
      turn_id: Ecto.UUID.generate(),
      command_id: Ecto.UUID.generate()
    }

    assert {:error, _} = Durable.accept_input(d, %{attrs | text: attrs.text <> "a"})
    assert version(d) == d.version
    assert {:ok, d} = Durable.accept_input(d, attrs)
    [source] = d.control["timeline"]
    control = %{d.control | "timeline" => List.duplicate(source, 128)}
    assert {:error, :context_limit} = ContextBuilder.build(d.repo, control, %{})
    assert {:ok, _} = Durable.context(d, %{})

    assert {:ok, small} =
             Durable.open(d.repo, %{
               agent_id: Ecto.UUID.generate(),
               authority_id: d.authority_id,
               definition: %{"version" => 1},
               command_id: Ecto.UUID.generate()
             })

    assert {:ok, small} = input(small)
    [source] = small.control["timeline"]
    control = %{small.control | "timeline" => List.duplicate(source, 128)}
    assert {:ok, _} = ContextBuilder.build(d.repo, control, %{})
    control = %{control | "timeline" => List.duplicate(source, 129)}
    assert {:error, :context_limit} = ContextBuilder.build(d.repo, control, %{})
  end

  test "claimed unresolved attempt stays blocked on explicit continue", %{durable: d} do
    {:ok, d} = input(d)
    {d, _, member} = prepare(d)

    assert {:ok, _} =
             OperationRecords.claim_dispatch(d.repo, %{
               operation_id: member["operation_id"],
               attempt_id: member["attempt_id"],
               expected_version: 0
             })

    assert {:ok, ref} = Agent.restore(locator(d), d.version, Ecto.UUID.generate())

    assert {:error, :unresolved_execution} =
             Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())

    decision = %{"operation_id" => member["operation_id"], "resolution" => "confirmed_failed"}
    before = version(d)
    assert {:error, _} = Agent.continue(ref, before, decision, Ecto.UUID.generate())
    assert version(d) == before
    refute_receive {:model_call, _}
  end

  test "cache and full replay agree across multiple pages; corrupt cache falls back", %{
    durable: d
  } do
    d =
      Enum.reduce(1..120, d, fn _, current ->
        {:ok, response} =
          AgentRecords.advance(current.repo, %{
            command_id: Ecto.UUID.generate(),
            position: Durable.position(current),
            turn_id: nil,
            type: "context.selected",
            payload: %{}
          })

        {:ok, control} = Reducer.replay(current.control, response["events"])
        %{current | version: response["lock_version"], control: control}
      end)

    checkpoint_id = Ecto.UUID.generate()
    prefix = d.control

    assert {:ok, checkpoint} =
             AgentRecords.checkpoint(d.repo, %{
               command_id: Ecto.UUID.generate(),
               position: Durable.position(d),
               id: checkpoint_id,
               through_seq: d.control["through_seq"],
               reducer_version: Reducer.version(),
               projection: d.control,
               continuation: "await_input",
               safe_to_fork: true
             })

    d = %{d | version: checkpoint["lock_version"]}

    assert {:ok, suffix} =
             AgentRecords.advance(d.repo, %{
               command_id: Ecto.UUID.generate(),
               position: Durable.position(d),
               turn_id: nil,
               type: "context.selected",
               payload: %{}
             })

    assert {:ok, control} = Reducer.replay(d.control, suffix["events"])
    d = %{d | version: suffix["lock_version"], control: control}
    assert {:ok, fixed} = Loader.load(d.repo, d.agent_id, through_seq: prefix["through_seq"])
    assert fixed.control == prefix
    assert {:ok, cached} = Loader.load(d.repo, d.agent_id)
    assert {:ok, full} = Loader.load(d.repo, d.agent_id, cache: false)
    assert cached.control == full.control
    assert full.control == d.control

    SQL.query!(d.repo, "UPDATE checkpoints SET digest = $1 WHERE id = $2", [
      String.duplicate("0", 64),
      checkpoint_id
    ])

    assert {:ok, fallback} = Loader.load(d.repo, d.agent_id)
    assert fallback.control == full.control
  end

  test "unclaimed prepared model resumes its original identity once", ctx do
    boot(ctx)
    {:ok, d} = input(ctx.durable)
    {d, _, member} = prepare(d)
    assert {:ok, ref} = Agent.restore(locator(d), d.version, Ecto.UUID.generate())
    assert {:ok, _} = Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())
    eventually(fn -> assert {:ok, %{status: :done}} = Agent.snapshot(ref) end)
    assert_receive {:model_call, _}
    refute_receive {:model_call, _}
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert [%{"operation_id" => id}] = loaded.control["consumed"]
    assert id == member["operation_id"]
  end

  test "input command replay returns the original turn without another request", ctx do
    boot(ctx)
    d = ctx.durable
    {:ok, ref} = Agent.start(node(), id: d.agent_id, durable: d, model: binding())
    command = Ecto.UUID.generate()
    assert {:ok, turn} = Agent.input(ref, "hello", command)
    assert {:ok, ^turn} = Agent.input(ref, "hello", command)
    assert {:error, :conflict} = Agent.input(ref, "changed", command)
    eventually(fn -> assert {:ok, %{status: :done}} = Agent.snapshot(ref) end)
    assert {:ok, ^turn} = Agent.input(ref, "hello", command)
    assert_receive {:model_call, _}
    refute_receive {:model_call, _}
  end

  defp tool_reply do
    %{
      "kind" => "tool_calls",
      "content" => nil,
      "calls" => [
        %{"id" => "one", "name" => "echo", "arguments" => %{"text" => "first"}},
        %{"id" => "two", "name" => "echo", "arguments" => %{"text" => "second"}}
      ]
    }
  end

  defp tool_locator(d) do
    {:ok, catalogue} = Catalogue.new([Deterministic.descriptor()])

    Map.merge(locator(d), %{
      model: binding(true),
      catalogue: catalogue,
      tools: %{"echo" => %{id: "echo", capability: "echo"}}
    })
  end

  defp consumed_tool_reply(d) do
    {:ok, d} = input(d)
    l = tool_locator(d)
    {:ok, built} = Durable.context(d, l.catalogue)
    {:ok, operation} = Caller.operation(l.model, built.request, 262_144)
    {:ok, d, [member]} = Durable.prepare(d, [%{operation: operation}], "model", built.sources)

    assert {:ok, _} =
             OperationRecords.accept_result(d.repo, %{
               operation_id: member["operation_id"],
               expected_version: 0,
               result: %{"status" => "ok", "value" => tool_reply(), "reason" => nil}
             })

    {:ok, d} = Durable.consume(d, [member["operation_id"]], "reply_recorded")
    d
  end

  test "consumed model reply drives the tool batch after restore without repeating that model call",
       ctx do
    boot(ctx)
    d = consumed_tool_reply(ctx.durable)
    assert {:ok, ref} = Agent.restore(tool_locator(d), d.version, Ecto.UUID.generate())
    assert {:ok, _} = Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())
    eventually(fn -> assert {:ok, %{status: :done, final: "finished"}} = Agent.snapshot(ref) end)
    assert_receive {:model_call, request}
    assert Enum.count(request.messages, &(&1["role"] == "tool")) == 2
    refute_receive {:model_call, _}
  end

  test "unconsumed accepted tool results resume in ordinal order without dispatching tools",
       ctx do
    boot(ctx)
    d = consumed_tool_reply(ctx.durable)

    operations =
      Enum.map(tool_reply()["calls"], fn call ->
        {:ok, operation} =
          Caller.operation(%{id: "echo", capability: "echo"}, call["arguments"], 262_144)

        %{id: call["id"], operation: operation}
      end)

    {:ok, d, members} = Durable.prepare(d, operations, "tool", d.control["timeline"])

    for member <- Enum.reverse(members) do
      assert {:ok, _} =
               OperationRecords.accept_result(d.repo, %{
                 operation_id: member["operation_id"],
                 expected_version: 0,
                 result: %{
                   "status" => "ok",
                   "value" => %{"text" => member["operation_id"]},
                   "reason" => nil
                 }
               })
    end

    assert {:ok, ref} = Agent.restore(tool_locator(d), d.version, Ecto.UUID.generate())
    assert {:ok, _} = Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())
    eventually(fn -> assert {:ok, %{status: :done}} = Agent.snapshot(ref) end)
    assert_receive {:model_call, request}

    assert Enum.map(Enum.filter(request.messages, &(&1["role"] == "tool")), & &1["call_id"]) == [
             "one",
             "two"
           ]

    refute_receive {:model_call, _}
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert length(loaded.control["consumed"]) == 4
  end

  test "a malformed but digest-valid cache falls back without traversing invalid references", %{
    durable: d
  } do
    checkpoint_id = Ecto.UUID.generate()

    assert {:ok, _} =
             AgentRecords.checkpoint(d.repo, %{
               command_id: Ecto.UUID.generate(),
               position: Durable.position(d),
               id: checkpoint_id,
               through_seq: d.control["through_seq"],
               reducer_version: Reducer.version(),
               projection: d.control,
               continuation: "await_input",
               safe_to_fork: true
             })

    bad = %{d.control | "pending" => [17]}
    {:ok, digest} = Codec.digest(bad, :checkpoint)

    SQL.query!(d.repo, "UPDATE checkpoints SET data = $1, digest = $2 WHERE id = $3", [
      Jason.encode!(bad),
      digest,
      checkpoint_id
    ])

    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert loaded.control == d.control
  end

  test "invalid consumption order and position refuse before committing", %{durable: d} do
    {:ok, d} = input(d)
    {d, _, member} = prepare(d)
    assert {:ok, _} = accept(d, member)
    assert {:error, _} = Durable.consume(d, [member["operation_id"]], "bogus")
    assert version(d) == d.version
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert loaded.control == d.control
  end

  test "invalid model preparation refuses before committing while input is pending", %{durable: d} do
    {:ok, d} = input(d)
    {d, op, _} = prepare(d)
    assert {:error, _} = Durable.prepare(d, [%{operation: op}], "model", d.control["timeline"])
    assert version(d) == d.version
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert loaded.control == d.control
  end

  test "resolution cannot conceal a successful model reply", %{durable: d} do
    {:ok, d} = input(d)
    {d, _, member} = prepare(d)
    assert {:ok, _} = accept(d, member)
    assert {:ok, ref} = Agent.restore(locator(d), d.version, Ecto.UUID.generate())
    before = version(d)
    decision = %{"operation_id" => member["operation_id"], "resolution" => "confirmed_failed"}
    assert {:error, _} = Agent.continue(ref, before, decision, Ecto.UUID.generate())
    assert version(d) == before
    assert {:ok, _} = Agent.continue(ref, before, %{}, Ecto.UUID.generate())
    assert {:ok, %{status: :done, final: "saved"}} = Agent.snapshot(ref)
    refute_receive {:model_call, _}
  end

  test "repeating the restore command does not activate another generation", %{durable: d} do
    {:ok, d} = input(d)
    command = Ecto.UUID.generate()
    assert {:ok, first} = Durable.restore(locator(d), d.version, command)
    assert {:ok, repeated} = Durable.restore(locator(d), d.version, command)
    assert repeated.control == first.control
    assert {:error, :invalid_data} = Durable.restore(locator(d), nil, command)
    assert version(d) == first.durable.version
    refute_receive {:model_call, _}
  end

  test "partially consumed tool batch resumes remaining identities and preserves original order",
       ctx do
    boot(ctx)
    d = consumed_tool_reply(ctx.durable)

    operations =
      Enum.map(tool_reply()["calls"], fn call ->
        {:ok, operation} =
          Caller.operation(%{id: "echo", capability: "echo"}, call["arguments"], 262_144)

        %{id: call["id"], operation: operation}
      end)

    {:ok, d, [first, second]} = Durable.prepare(d, operations, "tool", d.control["timeline"])

    for member <- [first, second] do
      assert {:ok, _} =
               OperationRecords.accept_result(d.repo, %{
                 operation_id: member["operation_id"],
                 expected_version: 0,
                 result: %{
                   "status" => "ok",
                   "value" => %{"text" => member["operation_id"]},
                   "reason" => nil
                 }
               })
    end

    assert {:error, _} =
             Durable.consume(
               d,
               [second["operation_id"], first["operation_id"]],
               "await_model_result"
             )

    assert {:error, _} =
             Durable.consume(
               d,
               [first["operation_id"], first["operation_id"]],
               "await_model_result"
             )

    assert version(d) == d.version
    assert {:ok, d} = Durable.consume(d, [first["operation_id"]], "await_model_result")
    assert {:ok, ref} = Agent.restore(tool_locator(d), d.version, Ecto.UUID.generate())
    assert {:ok, _} = Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())
    eventually(fn -> assert {:ok, %{status: :done, final: "finished"}} = Agent.snapshot(ref) end)
    assert_receive {:model_call, request}

    assert Enum.map(Enum.filter(request.messages, &(&1["role"] == "tool")), & &1["call_id"]) == [
             "one",
             "two"
           ]

    refute_receive {:model_call, _}
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert length(loaded.control["consumed"]) == 4
  end

  test "definite accepted model errors consume once and do not require a false resolution", ctx do
    boot(ctx)
    {:ok, d} = input(ctx.durable)
    {d, _, member} = prepare(d)

    assert {:ok, _} =
             OperationRecords.accept_result(d.repo, %{
               operation_id: member["operation_id"],
               expected_version: 0,
               result: %{"status" => "error", "reason" => "provider_failure", "value" => nil}
             })

    assert {:ok, ref} = Agent.restore(locator(d), d.version, Ecto.UUID.generate())
    assert {:ok, _} = Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())
    assert {:ok, %{status: :error, final: %{status: :error}}} = Agent.snapshot(ref)
    refute_receive {:model_call, _}
    eventually(fn -> assert {:ok, _} = Agent.input(ref, "next") end)
    eventually(fn -> assert {:ok, %{status: :done}} = Agent.snapshot(ref) end)
    assert_receive {:model_call, request}
    assert Enum.any?(request.messages, &String.contains?(&1["content"] || "", "provider_failure"))
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert length(loaded.control["consumed"]) == 2
  end

  test "all uncertain tools need named truthful resolutions before another model call", ctx do
    boot(ctx)
    d = consumed_tool_reply(ctx.durable)

    operations =
      Enum.map(tool_reply()["calls"], fn call ->
        {:ok, operation} =
          Caller.operation(%{id: "echo", capability: "echo"}, call["arguments"], 262_144)

        %{id: call["id"], operation: operation}
      end)

    {:ok, d, members} = Durable.prepare(d, operations, "tool", d.control["timeline"])

    for member <- members do
      assert {:ok, _} =
               OperationRecords.accept_result(d.repo, %{
                 operation_id: member["operation_id"],
                 expected_version: 0,
                 result: %{"status" => "uncertain", "reason" => "lost", "value" => nil}
               })
    end

    assert {:ok, ref} = Agent.restore(tool_locator(d), d.version, Ecto.UUID.generate())

    decisions =
      Enum.map(
        members,
        &%{"operation_id" => &1["operation_id"], "resolution" => "confirmed_failed"}
      )

    assert {:error, :unresolved_execution} =
             Agent.continue(ref, version(d), hd(decisions), Ecto.UUID.generate())

    refute_receive {:model_call, _}

    assert {:ok, _} =
             Agent.continue(ref, version(d), %{"resolutions" => decisions}, Ecto.UUID.generate())

    eventually(fn -> assert {:ok, %{status: :done}} = Agent.snapshot(ref) end)
    assert_receive {:model_call, request}
    observations = Enum.filter(request.messages, &(&1["role"] == "tool"))
    assert length(observations) == 2
    assert Enum.all?(observations, &String.contains?(&1["content"], "explicit_decision"))
    refute_receive {:model_call, _}
  end

  test "a safe input-only interruption can continue without fabricating execution evidence", %{
    durable: d
  } do
    {:ok, d} = input(d)
    {:ok, d} = Durable.block(d, :dependency_missing)
    assert {:ok, d} = Durable.decide(d, %{decision: %{}, command_id: Ecto.UUID.generate()})
    refute d.control["paused"]
    assert d.control["resolutions"] == %{}
    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert loaded.control == d.control
  end

  test "changed prepared dependencies block without executing or minting replacement work", ctx do
    boot(ctx)
    {:ok, d} = input(ctx.durable)
    {d, _, member} = prepare(d)
    changed = %{locator(d) | model: %{provider: "scripted", config: %{"changed" => true}}}
    assert {:ok, ref} = Agent.restore(changed, d.version, Ecto.UUID.generate())
    assert {:ok, _} = Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())
    assert {:ok, %{status: :paused, final: :dependency_missing}} = Agent.snapshot(ref)

    assert {:ok, %{"attempt" => %{"dispatch_state" => "prepared"}}} =
             OperationRecords.fetch(d.repo, member["operation_id"])

    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert length(loaded.control["pending"]) == 1
    refute_receive {:model_call, _}
  end

  test "continue waits for actual owner retirement rather than reusing its old turn token", ctx do
    boot(ctx)
    d = ctx.durable
    wait_binding = %{provider: "scripted", config: %{"wait" => true}}
    assert {:ok, ref} = Agent.start(node(), id: d.agent_id, durable: d, model: wait_binding)
    assert {:ok, _} = Agent.input(ref, "hello")
    assert_receive {:model_waiting, _}, 3000
    owner = :sys.get_state(ref.pid).owners |> Map.values() |> hd()
    monitor = Process.monitor(owner.pid)
    :erlang.suspend_process(owner.pid)

    try do
      assert :ok = Agent.stop_turn(ref)
      before = version(d)
      assert {:error, :owners_retiring} = Agent.continue(ref, before, %{}, Ecto.UUID.generate())
      assert version(d) == before
    after
      :erlang.resume_process(owner.pid)
    end

    assert_receive {:DOWN, ^monitor, :process, _, _}, 3000
    eventually(fn -> assert :sys.get_state(ref.pid).owners == %{} end)

    assert {:error, :unresolved_execution} =
             Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())

    assert_receive {:model_call, _}
    refute_receive {:model_call, _}
  end

  test "reducer rejects malformed schema and invalid orchestration without raising", %{durable: d} do
    {:ok, %{"events" => [created]}} = AgentRecords.history_page(d.repo, d.agent_id)

    for payload <- [nil, %{}, %{"definition_version" => 1, "extra" => true}] do
      assert {:error, _} =
               Reducer.reduce(Reducer.new(d.agent_id), %{created | "payload" => payload})
    end

    assert {:error, :invalid_history} =
             Reducer.reduce(Reducer.new(d.agent_id), %{
               created
               | "type" => "context.selected",
                 "payload" => %{}
             })

    {:ok, d} = input(d)
    {d, _, member} = prepare(d)
    assert {:ok, _} = accept(d, member)
    assert {:ok, %{"events" => events}} = AgentRecords.history_page(d.repo, d.agent_id)
    prepared = List.last(events)

    for payload <- [
          %{"operation_id" => member["operation_id"]},
          %{prepared["payload"] | "ordinal" => 7}
        ] do
      event = %{prepared | "payload" => payload}

      assert {:error, _} =
               Reducer.reduce(%{d.control | "through_seq" => prepared["seq"] - 1}, event)
    end
  end

  test "memory mode uncertain tool output blocks the next model and new input", ctx do
    boot(ctx, Beamlet.Agent.DurableWaitingTool, false)
    {:ok, catalogue} = Catalogue.new([Deterministic.descriptor()])

    assert {:ok, ref} =
             Agent.start(node(),
               id: "memory-unknown",
               model: binding(true),
               catalogue: catalogue,
               tools: %{"echo" => %{id: "echo", capability: "echo"}}
             )

    assert {:ok, _} = Agent.input(ref, "tools")
    assert_receive {:tool_waiting, first, _}, 3000
    assert_receive {:tool_waiting, second, _}, 3000
    monitors = Enum.map([first, second], &Process.monitor/1)
    eventually(fn -> assert map_size(:sys.get_state(ref.pid).pending) == 2 end)
    state = :sys.get_state(ref.pid)
    pending = Enum.find_value(state.pending, fn {_, p} -> if p.key == "one", do: p end)

    result = %Result{
      operation_id: pending.ref.id,
      source: :coordinator,
      status: :uncertain,
      reason: :lost
    }

    assert Result.valid?(result)
    send(ref.pid, {:beamlet_operation, pending.ref, {:result, result}})

    eventually(fn ->
      assert {:ok, %{status: :error, final: :unresolved_execution}} = Agent.snapshot(ref)
    end)

    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 3000)
    assert {:error, :unresolved_execution} = Agent.input(ref, "try again")
    assert_receive {:model_call, _}
    refute_receive {:model_call, _}
  end

  test "Operation row corruption cannot substitute a different immutable prepared request", %{
    durable: d
  } do
    {:ok, d} = input(d)
    {d, operation, member} = prepare(d)
    description = Persistence.description(operation) |> Map.put("refs", %{"changed" => true})
    {:ok, digest} = Codec.digest(description, :operation)

    SQL.query!(
      d.repo,
      "UPDATE operations SET description = $1, description_digest = $2 WHERE id = $3",
      [
        Jason.encode!(description),
        digest,
        member["operation_id"]
      ]
    )

    assert {:error, :invalid_reference} = Durable.inspect(locator(d))

    assert {:error, :invalid_reference} =
             Durable.restore(locator(d), d.version, Ecto.UUID.generate())

    assert version(d) == d.version
    refute_receive {:model_call, _}
  end

  test "stored reply conversion does not silently discard unknown model or call fields" do
    reply = tool_reply()
    assert {:error, :invalid_reply} = ContextBuilder.reply(Map.put(reply, "ignored", true))
    calls = [Map.put(hd(reply["calls"]), "ignored", true)]
    assert {:error, :invalid_reply} = ContextBuilder.reply(%{reply | "calls" => calls})
  end

  test "activation fences suspended old senders and waits for their inventoried group DOWN",
       ctx do
    boot(ctx)
    d = ctx.durable

    assert {:ok, ref} =
             Agent.start(node(),
               id: d.agent_id,
               durable: d,
               model: %{provider: "scripted", config: %{"wait" => true}}
             )

    assert {:ok, _} = Agent.input(ref, "hello")
    assert_receive {:model_waiting, worker}, 3000
    owner = :sys.get_state(ref.pid).owners |> Map.values() |> hd()

    eventually(fn ->
      resources = :sys.get_state(Agent.Resources)
      assert Enum.any?(resources.identities, fn {_, identity} -> identity == {d.agent_id, 0} end)
      assert owner.pid in Map.values(resources.processes)
      assert length(Map.values(resources.processes)) >= 2
    end)

    :erlang.suspend_process(owner.pid)
    monitor = Process.monitor(ref.pid)
    Process.exit(ref.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 3000
    assert Process.alive?(owner.pid)
    assert Process.alive?(worker)
    inventory = :sys.get_state(Agent.Resources).processes |> Map.values()
    monitors = Enum.map([worker | inventory], &Process.monitor/1)

    try do
      assert {:ok, restored} = Durable.restore(locator(d), version(d), Ecto.UUID.generate())
      assert restored.control["paused"]
      assert Enum.all?(inventory, &(not Process.alive?(&1)))
      for mon <- monitors, do: assert_receive({:DOWN, ^mon, :process, _, _}, 3000)

      assert {:error, :unresolved_execution} =
               Durable.decide(restored.durable, %{
                 command_id: Ecto.UUID.generate(),
                 decision: %{}
               })
    after
      if Process.alive?(owner.pid), do: :erlang.resume_process(owner.pid)
    end

    assert_receive {:model_call, _}
    refute_receive {:model_call, _}
  end

  test "failed restored sibling dependency prevents every later sibling dispatch", ctx do
    boot(ctx, Beamlet.Agent.DurableWaitingTool)
    d = consumed_tool_reply(ctx.durable)

    operations =
      tool_reply()["calls"]
      |> Enum.with_index()
      |> Enum.map(fn {call, index} ->
        profile = %{id: if(index == 0, do: "missing-profile", else: "echo"), capability: "echo"}
        {:ok, operation} = Caller.operation(profile, call["arguments"], 262_144)
        %{id: call["id"], operation: operation}
      end)

    {:ok, d, members} = Durable.prepare(d, operations, "tool", d.control["timeline"])
    assert {:ok, ref} = Agent.restore(tool_locator(d), d.version, Ecto.UUID.generate())
    assert {:ok, _} = Agent.continue(ref, version(d), %{}, Ecto.UUID.generate())
    assert {:ok, %{status: :paused, final: :dependency_missing}} = Agent.snapshot(ref)
    assert :sys.get_state(ref.pid).owners == %{}

    for member <- members do
      assert {:ok, %{"attempt" => %{"dispatch_state" => "prepared"}}} =
               OperationRecords.fetch(d.repo, member["operation_id"])
    end

    refute_receive {:tool_waiting, _, _}
    refute_receive {:model_call, _}
  end

  test "a valid cache cannot conceal a missing committed history event", %{durable: d} do
    {:ok, d} = input(d)

    assert {:ok, checkpoint} =
             AgentRecords.checkpoint(d.repo, %{
               command_id: Ecto.UUID.generate(),
               position: Durable.position(d),
               id: Ecto.UUID.generate(),
               through_seq: d.control["through_seq"],
               reducer_version: Reducer.version(),
               projection: d.control,
               continuation: "await_model_result",
               safe_to_fork: false
             })

    SQL.query!(d.repo, "DELETE FROM events WHERE scope_id = $1 AND seq = 2", [d.agent_id])
    assert {:error, :history_limit_or_gap} = Durable.inspect(locator(d))

    assert {:error, :history_limit_or_gap} =
             Durable.restore(locator(d), checkpoint["lock_version"], Ecto.UUID.generate())

    assert version(d) == checkpoint["lock_version"]
    refute_receive {:model_call, _}
  end

  test "memory mode uncertain model outcome blocks subsequent model calls", ctx do
    boot(ctx, Deterministic, false)

    assert {:ok, ref} =
             Agent.start(node(),
               id: "memory-model-unknown",
               model: %{provider: "scripted", config: %{"wait" => true}}
             )

    assert {:ok, _} = Agent.input(ref, "hello")
    assert_receive {:model_waiting, worker}, 3000
    monitor = Process.monitor(worker)
    eventually(fn -> assert map_size(:sys.get_state(ref.pid).pending) == 1 end)
    [pending] = :sys.get_state(ref.pid).pending |> Map.values()

    result = %Result{
      operation_id: pending.ref.id,
      source: :coordinator,
      status: :uncertain,
      reason: :lost
    }

    assert Result.valid?(result)
    send(ref.pid, {:beamlet_operation, pending.ref, {:result, result}})

    eventually(fn ->
      assert {:ok, %{status: :error, final: %{status: :uncertain}}} = Agent.snapshot(ref)
    end)

    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 3000
    assert {:error, :unresolved_execution} = Agent.input(ref, "try again")
    assert_receive {:model_call, _}
    refute_receive {:model_call, _}
  end

  test "malformed stored JSON blocks read-only reconstruction rather than raising", %{durable: d} do
    {:ok, d} = input(d)

    SQL.query!(d.repo, "UPDATE events SET payload = $1 WHERE scope_id = $2 AND seq = 2", [
      "{bad",
      d.agent_id
    ])

    assert {:error, :invalid_data} = Durable.inspect(locator(d))

    assert_raise ArgumentError, "unrelated", fn ->
      Transaction.read(fn -> raise ArgumentError, "unrelated" end)
    end

    assert {:error, :invalid_data} = Durable.restore(locator(d), d.version, Ecto.UUID.generate())
    assert version(d) == d.version
    refute_receive {:model_call, _}
  end

  test "effective configuration versions distinguish config and schema but exclude inputs and secrets",
       %{durable: d} do
    {:ok, d} = input(d)
    assert {:ok, built} = Durable.context(d, %{})
    assert {:ok, ^built} = Durable.context(d, %{})
    assert built.policy["definition_version"] == 1
    assert {:ok, original} = Caller.operation(binding(), built.request, 262_144)
    version = original.metadata["configuration_version"]
    assert version =~ ~r/\A[0-9a-f]{64}\z/

    changed_input = %{
      built.request
      | "messages" => [%{"role" => "user", "content" => "different"}]
    }

    assert {:ok, other_input} = Caller.operation(binding(), changed_input, 262_144)
    assert other_input.metadata["configuration_version"] == version

    assert {:ok, other_secret} =
             Caller.operation(
               Map.put(binding(), :credentials, %{"api_key" => "not-persisted"}),
               built.request,
               262_144
             )

    assert other_secret.metadata["configuration_version"] == version
    refute inspect(Persistence.description(other_secret)) =~ "not-persisted"
    assert {:ok, other_config} = Caller.operation(binding(true), built.request, 262_144)
    refute other_config.metadata["configuration_version"] == version
    {:ok, catalogue} = Catalogue.new([Deterministic.descriptor()])

    assert {:ok, other_schema} =
             Caller.operation(binding(), %{built.request | "catalogue" => catalogue}, 262_144)

    refute other_schema.metadata["configuration_version"] == version
    profile = %{id: "echo", capability: "echo"}
    assert {:ok, first} = Caller.operation(profile, %{"text" => "one"}, 262_144)
    assert {:ok, second} = Caller.operation(profile, %{"text" => "two"}, 262_144)
    assert first.metadata["configuration_version"] == second.metadata["configuration_version"]

    assert {:ok, changed} =
             Caller.operation(%{profile | id: "echo-v2"}, %{"text" => "one"}, 262_144)

    refute first.metadata["configuration_version"] == changed.metadata["configuration_version"]
  end

  test "policy metadata counts in the executable limit before any Operation is prepared", %{
    durable: d
  } do
    text = String.duplicate("a", 1000)
    request = %{"messages" => [%{"role" => "user", "content" => text}], "catalogue" => %{}}
    {:ok, operation} = Caller.operation(binding(), request, 262_144)
    assert {:ok, ref} = Agent.start(node(), id: d.agent_id, durable: d, model: binding())
    :sys.replace_state(ref.pid, &%{&1 | operation_limit: :erlang.external_size(operation)})
    assert {:ok, _} = Agent.input(ref, text)

    eventually(fn ->
      assert {:ok, %{status: :paused, final: :executable_input_limit}} = Agent.snapshot(ref)
    end)

    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert loaded.control["pending"] == []
    assert loaded.control["step"] == 0
    assert {:ok, %{request: ^request}} = ContextBuilder.build(d.repo, loaded.control, %{})
    refute_receive {:model_call, _}
  end

  test "cache prefix and suffix share the same total history byte budget", %{durable: d} do
    payload = %{"selection_tag" => String.duplicate("a", 900_000)}

    d =
      Enum.reduce(1..40, d, fn index, current ->
        assert {:ok, response} =
                 AgentRecords.advance(current.repo, %{
                   command_id: Ecto.UUID.generate(),
                   position: Durable.position(current),
                   turn_id: nil,
                   type: "context.selected",
                   payload: payload
                 })

        {:ok, control} = Reducer.replay(current.control, response["events"])
        current = %{current | version: response["lock_version"], control: control}

        if index == 35 do
          assert {:ok, checkpoint} =
                   AgentRecords.checkpoint(current.repo, %{
                     command_id: Ecto.UUID.generate(),
                     position: Durable.position(current),
                     id: Ecto.UUID.generate(),
                     through_seq: control["through_seq"],
                     reducer_version: Reducer.version(),
                     projection: control,
                     continuation: "await_input",
                     safe_to_fork: true
                   })

          %{current | version: checkpoint["lock_version"]}
        else
          current
        end
      end)

    assert {:error, :history_limit_or_gap} = Loader.load(d.repo, d.agent_id, cache: false)
    assert {:error, :history_limit_or_gap} = Loader.load(d.repo, d.agent_id)
    assert {:ok, _} = Loader.load(d.repo, d.agent_id, through_seq: 2)

    assert {:error, :history_limit_or_gap} =
             Durable.restore(locator(d), d.version, Ecto.UUID.generate())

    assert version(d) == d.version
    refute_receive {:model_call, _}
  end

  test "real durable model and parallel tool batch consume accepted output in ordinal order",
       ctx do
    boot(ctx)
    {:ok, catalogue} = Catalogue.new([Deterministic.descriptor()])
    d = ctx.durable

    assert {:ok, ref} =
             Agent.start(node(),
               id: d.agent_id,
               durable: d,
               model: binding(true),
               catalogue: catalogue,
               tools: %{"echo" => %{id: "echo", capability: "echo"}}
             )

    assert {:ok, _} = Agent.input(ref, "tools")
    eventually(fn -> assert {:ok, %{status: :done, final: "finished"}} = Agent.snapshot(ref) end)
    assert_receive {:model_call, _}
    assert_receive {:model_call, request}

    assert Enum.map(Enum.filter(request.messages, &(&1["role"] == "tool")), & &1["call_id"]) == [
             "one",
             "two"
           ]

    assert {:ok, loaded} = Loader.load(d.repo, d.agent_id)
    assert length(loaded.control["consumed"]) == 4

    for reference <- loaded.control["consumed"] do
      assert {:ok, %{"operation" => op}} = Loader.operation(d.repo, d.agent_id, reference)
      metadata = op["description"]["safety"]["metadata"]
      assert metadata["configuration_version"] =~ ~r/\A[0-9a-f]{64}\z/
      if op["role"] == "model", do: assert(metadata["definition_version"] == 1)
    end

    assert :ok == Events.control(loaded.control)
  end
end
