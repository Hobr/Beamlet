defmodule Beamlet.Agent.ForkTest do
  use ExUnit.Case, async: false
  import Ecto.Query

  alias Beamlet.Agent
  alias Beamlet.Agent.Durable
  alias Beamlet.Harness.Context
  alias Beamlet.Storage.Codec

  alias Beamlet.Storage.{
    AgentRecords,
    Dataset,
    ExecutorJournalRepo,
    OperationRecords,
    Records,
    SQLiteAuthorityRepo
  }

  alias Beamlet.Storage.Schema.{Checkpoint, Command, Event, Operation}
  alias Beamlet.Storage.Schema.Agent, as: AgentRow

  setup do
    dir = Path.join(System.tmp_dir!(), "beamlet-fork-#{System.unique_integer([:positive])}")
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

    start_supervised!(Beamlet.Agent.AuthoritySupervisor)
    {:ok, _} = Dataset.initialize(SQLiteAuthorityRepo, authority_opts)
    {:ok, _} = Dataset.initialize(ExecutorJournalRepo, journal_opts)

    on_exit(fn ->
      stop_repo(SQLiteAuthorityRepo)
      stop_repo(ExecutorJournalRepo)
      File.rm_rf!(dir)
    end)

    %{authority_id: Ecto.UUID.generate(), dir: dir}
  end

  defp stop_repo(repo) do
    if pid = Process.whereis(repo), do: Supervisor.stop(pid)
    :ok
  catch
    _, _ -> :ok
  end

  defp uuid, do: Ecto.UUID.generate()

  defp definition(overrides \\ %{}) do
    Map.merge(
      %{
        "schema_version" => 1,
        "model" => %{"provider" => "counting", "config" => %{"model" => "m1"}},
        "tools" => %{"echo" => %{"profile" => "echo-profile"}}
      },
      overrides
    )
  end

  # The Runtime wiring only supplies the identities a prepared attempt records;
  # these tests accept Results through the facades instead of dispatching them.
  defp open(ctx, opts \\ []) do
    {:ok, durable} =
      Durable.open(SQLiteAuthorityRepo, %{
        agent_id: uuid(),
        authority_id: ctx.authority_id,
        alias:
          Keyword.get_lazy(opts, :alias, fn -> "fork-#{System.unique_integer([:positive])}" end),
        definition: Keyword.get(opts, :definition, definition()),
        command_id: uuid()
      })

    Durable.with_runtime(durable, %{
      authority_repo: SQLiteAuthorityRepo,
      journal_repo: ExecutorJournalRepo,
      executor_id: uuid(),
      executor_boot_id: uuid()
    })
  end

  defp accept_input(durable, text) do
    {:ok, messages} = Context.append(messages(durable), [%{"role" => "user", "content" => text}])

    {:ok, accepted} =
      Durable.accept_input(durable, %{
        command_id: uuid(),
        turn_id: uuid(),
        messages: messages,
        checkpoint_id: uuid()
      })

    {accepted, %{durable | turn_id: accepted.turn_id, version: accepted.version}}
  end

  # One complete Tool turn: prepared batch, two accepted Results, consumed
  # context. The returned durable points at the consumed checkpoint.
  defp complete_turn(durable) do
    {_accepted, durable} = accept_input(durable, "hello")

    calls = [
      %{id: "call-1", name: "echo", arguments: %{"text" => "first"}},
      %{id: "call-2", name: "echo", arguments: %{"text" => "second"}}
    ]

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
            %{id: "echo-profile", capability: "echo"},
            call.arguments,
            262_144
          )

        %{id: call.id, operation: operation}
      end)

    {:ok, batch} =
      Durable.prepare_batch(durable, %{
        calls: operations,
        messages: messages,
        step: 1,
        checkpoint_id: uuid()
      })

    durable = %{durable | version: batch.version}
    [first, second] = batch.operations

    assert {:ok, _} = accept_result(durable, first, %{"text" => "first"})
    assert {:ok, _} = accept_result(durable, second, %{"text" => "second"})

    observations = [
      %{"role" => "tool", "call_id" => "call-1", "content" => ~s({"status":"ok"})},
      %{"role" => "tool", "call_id" => "call-2", "content" => ~s({"status":"ok"})}
    ]

    {:ok, tool_messages} = Context.append(messages(durable), observations)

    {:ok, consumed} =
      Durable.consume_results(durable, %{
        operations: [
          %{operation_id: first["operation_id"]},
          %{operation_id: second["operation_id"]}
        ],
        messages: tool_messages,
        order: ["call-1", "call-2"],
        checkpoint_id: uuid()
      })

    %{durable | version: consumed.version}
  end

  defp accept_result(durable, operation, value) do
    {:ok, %{"operation" => stored}} =
      OperationRecords.fetch(SQLiteAuthorityRepo, operation["operation_id"])

    {:ok, %{"agent" => agent}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    OperationRecords.accept_result(SQLiteAuthorityRepo, %{
      operation_id: operation["operation_id"],
      expected_version: stored["lock_version"],
      agent: %{expected_generation: agent["generation"], accept_seq: operation["accept_seq"]},
      result: %{"status" => "ok", "value" => value, "reason" => nil},
      event: %{
        id: uuid(),
        type: "operation.result_accepted",
        payload: %{"operation_id" => operation["operation_id"]}
      }
    })
  end

  defp head(durable) do
    {:ok, %{"head_checkpoint" => head, "agent" => agent}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    {head, agent}
  end

  defp messages(durable), do: elem(head(durable), 0)["data"]["messages"]

  defp locator(durable, extra \\ []) do
    Map.merge(
      %{
        repo: SQLiteAuthorityRepo,
        agent_id: durable.agent_id,
        model: %{provider: "counting", config: %{}},
        tools: %{"echo" => %{id: "echo-profile", capability: "echo"}},
        catalogue: %{}
      },
      Map.new(extra)
    )
  end

  defp counts do
    %{
      agents: SQLiteAuthorityRepo.aggregate(AgentRow, :count),
      checkpoints: SQLiteAuthorityRepo.aggregate(Checkpoint, :count),
      events: SQLiteAuthorityRepo.aggregate(Event, :count),
      commands: SQLiteAuthorityRepo.aggregate(Command, :count),
      operations: SQLiteAuthorityRepo.aggregate(Operation, :count)
    }
  end

  defp source_rows(agent_id) do
    agent = SQLiteAuthorityRepo.all(from(a in AgentRow, where: a.id == ^agent_id))

    checkpoints =
      SQLiteAuthorityRepo.all(
        from(c in Checkpoint, where: c.agent_id == ^agent_id, order_by: [asc: c.id])
      )

    {:ok, %{"events" => events}} =
      AgentRecords.history_page(SQLiteAuthorityRepo, agent_id, limit: 500)

    %{
      agent: Records.plain(agent),
      checkpoints: Records.plain(checkpoints),
      events: events
    }
  end

  defp child_count(parent) do
    SQLiteAuthorityRepo.aggregate(
      from(a in AgentRow, where: a.forked_from_agent_id == ^parent),
      :count
    )
  end

  test "a safe checkpoint forks into an independent Agent with copied context", ctx do
    {:ok, source} = open(ctx)
    source = complete_turn(source)
    {source_head, source_agent} = head(source)
    before = source_rows(source.agent_id)

    assert {:ok, fork} =
             Agent.fork(
               locator(source, source: %{freeze: :frozen, environment: :confirmed_stopped}),
               source_head["id"],
               source_agent["lock_version"],
               uuid()
             )

    refute fork.agent_id == source.agent_id
    assert fork.source == %{agent_id: source.agent_id, checkpoint_id: source_head["id"]}

    # The new Agent starts at await_input with the copied effective context.
    {:ok, %{"agent" => forked, "head_checkpoint" => forked_head}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, fork.agent_id)

    assert forked["forked_from_agent_id"] == source.agent_id
    assert forked["forked_from_checkpoint_id"] == source_head["id"]
    assert forked_head["continuation"] == "await_input"
    assert forked_head["data"]["messages"] == source_head["data"]["messages"]
    assert forked_head["data"]["pending"] == []
    assert forked_head["data"]["turn_id"] == nil
    assert forked_head["data"]["fork"]["source_agent_id"] == source.agent_id
    assert forked_head["data"]["fork"]["inherited_messages"] == 4

    # Inherited context records carry fresh ids plus the source markers.
    {:ok, %{"events" => events}} =
      AgentRecords.history_page(SQLiteAuthorityRepo, fork.agent_id, limit: 500)

    inherited = Enum.filter(events, &(&1["type"] == "context.inherited"))
    assert length(inherited) == 4
    assert Enum.all?(inherited, &(&1["source_agent_id"] == source.agent_id))
    assert Enum.all?(inherited, fn event -> is_nil(event["turn_id"]) end)
    assert Enum.uniq(Enum.map(inherited, & &1["id"])) == Enum.map(inherited, & &1["id"])

    forked_events = Enum.reject(events, &(&1["type"] == "context.inherited"))
    assert [fork_event] = forked_events
    assert fork_event["type"] == "agent.forked"
    assert fork_event["payload"]["source_checkpoint_id"] == source_head["id"]

    # The source history is unchanged by the fork.
    assert source_rows(source.agent_id) == before

    # Loading the new Agent reads only its own rows: the parent keeps moving and
    # the copied context stays identical.
    {_next_accepted, moved} = accept_input(source, "later")
    assert moved.version > source_agent["lock_version"]
    {moved_head, _moved_agent} = head(source)
    assert moved_head["id"] != source_head["id"]
    assert head(source) |> elem(0) |> get_in(["data", "messages"]) |> length() == 5

    assert {:ok, restored} =
             Durable.restore(fork.locator, fork.version, uuid())

    assert restored.checkpoint["messages"] == source_head["data"]["messages"]
    assert restored.checkpoint["continuation"] == "await_input"
    assert restored.checkpoint["fork"]["source_checkpoint_id"] == source_head["id"]
    assert restored.durable.agent_id == fork.agent_id
  end

  test "an unsafe checkpoint is refused and writes no rows", ctx do
    {:ok, source} = open(ctx)
    {_accepted, source} = accept_input(source, "hello")

    assistant = %{
      "role" => "assistant",
      "content" => nil,
      "calls" => [%{"id" => "call-1", "name" => "echo", "arguments" => %{"text" => "a"}}]
    }

    {:ok, messages} = Context.append(messages(source), [assistant])

    {:ok, operation} =
      Beamlet.Agent.Integration.Caller.operation(
        %{id: "echo-profile", capability: "echo"},
        %{"text" => "a"},
        262_144
      )

    {:ok, batch} =
      Durable.prepare_batch(source, %{
        calls: [%{id: "call-1", operation: operation}],
        messages: messages,
        step: 1,
        checkpoint_id: uuid()
      })

    {batch_head, agent} = head(%{source | version: batch.version})
    assert batch_head["safe_to_fork"] == false
    before = counts()

    assert {:error, :unsafe_checkpoint} =
             Agent.fork(
               locator(source, source: %{freeze: :frozen, environment: :confirmed_stopped}),
               batch_head["id"],
               agent["lock_version"],
               uuid()
             )

    # A checkpoint flagged safe but carrying in-flight state is refused too.
    data = Durable.state(%{"pending" => [%{"operation_id" => uuid()}]})
    {:ok, digest} = Codec.digest(data, :checkpoint)
    checkpoint_id = uuid()

    assert {:ok, _} =
             AgentRecords.insert_checkpoint(
               SQLiteAuthorityRepo,
               %{
                 id: checkpoint_id,
                 data: data,
                 continuation: "await_input",
                 digest: digest,
                 safe_to_fork: true
               },
               source.agent_id,
               nil
             )

    marked = counts()

    assert {:error, :unsafe_checkpoint} =
             Agent.fork(
               locator(source, source: %{freeze: :frozen, environment: :confirmed_stopped}),
               checkpoint_id,
               agent["lock_version"],
               uuid()
             )

    assert counts() == marked
    assert counts().agents == before.agents
    assert child_count(source.agent_id) == 0
  end

  test "an oversize copy is refused instead of truncated", ctx do
    huge =
      definition(%{
        "model" => %{
          "provider" => "counting",
          "config" => %{"padding" => String.duplicate("x", 1_040_000)}
        }
      })

    {:ok, source} = open(ctx, definition: huge)
    {_accepted, source} = accept_input(source, String.duplicate("y", 10_000))
    {head, agent} = head(source)
    before = counts()

    assert {:error, :limit} =
             Agent.fork(
               locator(source, source: %{freeze: :frozen, environment: :confirmed_stopped}),
               head["id"],
               agent["lock_version"],
               uuid()
             )

    assert counts() == before
    assert child_count(source.agent_id) == 0
  end

  test "a repeated fork command returns the same locator and a different payload conflicts",
       ctx do
    {:ok, source} = open(ctx)
    source = complete_turn(source)
    {head, agent} = head(source)
    command = uuid()

    fork = fn attrs ->
      Agent.fork(
        Map.put(locator(source), :source, attrs),
        head["id"],
        agent["lock_version"],
        command
      )
    end

    source_input = %{freeze: :frozen, environment: :confirmed_stopped}
    assert {:ok, first} = fork.(source_input)
    assert {:ok, second} = fork.(source_input)
    assert second.agent_id == first.agent_id
    assert second.checkpoint_id == first.checkpoint_id
    assert child_count(source.agent_id) == 1

    assert {:error, :conflict} =
             fork.(%{freeze: :idle, environment: :confirmed_stopped})
  end

  test "the new Agent inherits no pending, consumption or command state", ctx do
    {:ok, source} = open(ctx)
    source = complete_turn(source)
    {head, agent} = head(source)

    assert {:ok, fork} =
             Agent.fork(
               locator(source, source: %{freeze: :frozen, environment: :confirmed_stopped}),
               head["id"],
               agent["lock_version"],
               uuid()
             )

    assert SQLiteAuthorityRepo.aggregate(
             from(o in Operation, where: o.owner_agent_id == ^fork.agent_id),
             :count
           ) == 0

    assert SQLiteAuthorityRepo.aggregate(
             from(c in Command, where: c.scope_id == ^fork.agent_id),
             :count
           ) == 0

    {:ok, %{"events" => events}} =
      AgentRecords.history_page(SQLiteAuthorityRepo, fork.agent_id, limit: 500)

    refute Enum.any?(events, &(&1["type"] in ~w(operation.prepared result.consumed)))

    {:ok, %{"head_checkpoint" => forked_head}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, fork.agent_id)

    assert forked_head["data"]["consumed"] == []
    assert forked_head["data"]["order"] == []
    assert forked_head["data"]["results"] == %{}
  end

  test "inherited entries are marked and never counted as the new Agent's execution", ctx do
    {:ok, source} = open(ctx)
    source = complete_turn(source)
    {head, agent} = head(source)

    assert {:ok, fork} =
             Agent.fork(
               locator(source, source: %{freeze: :frozen, environment: :confirmed_stopped}),
               head["id"],
               agent["lock_version"],
               uuid()
             )

    locator = %{repo: SQLiteAuthorityRepo, agent_id: fork.agent_id}

    assert {:ok, page} = Agent.history(locator, %{view: :facts, origin: :inherited})
    assert length(page["events"]) == 4
    assert Enum.all?(page["events"], &(&1["origin"] == "inherited"))

    assert {:ok, page} = Agent.history(locator, %{view: :facts, origin: :performed})
    assert Enum.map(page["events"], & &1["type"]) == ["agent.forked"]

    assert {:ok, provenance} = Agent.history(locator, %{view: :provenance})
    assert provenance["forked_from_agent_id"] == source.agent_id
    assert provenance["forked_from_checkpoint_id"] == head["id"]
    assert provenance["inherited"]["counted_as_execution"] == false
    assert provenance["inherited"]["source_agent_ids"] == [source.agent_id]

    dir = Path.join(ctx.dir, "export")
    assert {:ok, manifest} = Agent.export(locator, nil, %{dir: dir})
    assert manifest["provenance"]["inherited_entries"] == 4
    assert manifest["provenance"]["performed_entries"] == 1
    assert manifest["provenance"]["inherited_counted_as_execution"] == false
    assert {:ok, _report} = Beamlet.Agent.TraceExport.verify(dir)
  end

  test "an unconfirmed shared-environment risk blocks execution until acceptance", ctx do
    {:ok, source} = open(ctx)
    source = complete_turn(source)
    {head, agent} = head(source)

    assert {:ok, fork} =
             Agent.fork(
               locator(source, source: %{freeze: :frozen, environment: :unconfirmed}),
               head["id"],
               agent["lock_version"],
               uuid()
             )

    assert fork.risk == "unconfirmed"

    {:ok, restored} = Durable.restore(fork.locator, fork.version, uuid())
    durable = restored.durable
    before = messages(durable)

    assert {:error, {:blocked, :environment_risk_unconfirmed}} =
             Durable.accept_input(durable, %{
               command_id: uuid(),
               turn_id: uuid(),
               messages: before ++ [%{"role" => "user", "content" => "start"}],
               checkpoint_id: uuid()
             })

    # Nothing was written by the refused input.
    assert messages(durable) == before

    # A stale version cannot record the acceptance.
    assert {:error, :conflict} =
             Durable.decide(%{durable | version: 0}, %{
               command_id: uuid(),
               checkpoint_id: uuid(),
               decision: %{"risk" => "accepted"}
             })

    assert {:ok, decision} =
             Durable.decide(durable, %{
               command_id: uuid(),
               checkpoint_id: uuid(),
               decision: %{"risk" => "accepted"}
             })

    assert decision.continuation == "await_input"
    durable = %{durable | version: decision.version}

    # Accepting again is not a new decision.
    assert {:error, {:blocked, :no_pending_risk}} =
             Durable.decide(durable, %{
               command_id: uuid(),
               checkpoint_id: uuid(),
               decision: %{"risk" => "accepted"}
             })

    assert {:ok, accepted} =
             Durable.accept_input(durable, %{
               command_id: uuid(),
               turn_id: uuid(),
               messages: before ++ [%{"role" => "user", "content" => "start"}],
               checkpoint_id: uuid()
             })

    assert accepted.turn_id

    {:ok, %{"head_checkpoint" => head}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, fork.agent_id)

    assert head["data"]["environment"]["risk"] == nil
    assert head["data"]["environment"]["risk_accepted"] == true

    {:ok, %{"events" => events}} =
      AgentRecords.history_page(SQLiteAuthorityRepo, fork.agent_id, limit: 500)

    accepted_event = Enum.find(events, &(&1["type"] == "agent.risk_accepted"))
    assert accepted_event["payload"]["source_agent_id"] == source.agent_id

    assert accepted_event["payload"]["source_checkpoint_id"] ==
             head["data"]["fork"]["source_checkpoint_id"]
  end

  test "a mid-turn source must be frozen before it can be forked", ctx do
    {:ok, source} = open(ctx)
    # `accept_input` leaves the head at await_model_result: still copyable for
    # inspection, but the turn is in flight.
    {_accepted, source} = accept_input(source, "hello")
    {head, agent} = head(source)

    assert {:error, :source_not_frozen} =
             Agent.fork(locator(source), head["id"], agent["lock_version"], uuid())

    assert {:ok, fork} =
             Agent.fork(
               locator(source, source: %{freeze: :frozen, environment: :confirmed_stopped}),
               head["id"],
               agent["lock_version"],
               uuid()
             )

    assert fork.agent_id != source.agent_id
  end

  test "a quiet head forks without an explicit freeze", ctx do
    {:ok, source} = open(ctx)
    {head, agent} = head(source)
    assert head["continuation"] == "await_input"

    # Only a mid-turn head needs a frozen source; the abandoned-Operation case is
    # scoped to the head checkpoint's own turn, so an idle head stays forkable.
    assert {:ok, fork} =
             Agent.fork(
               locator(source, source: %{freeze: :idle, environment: :confirmed_stopped}),
               head["id"],
               agent["lock_version"],
               uuid()
             )

    assert fork.agent_id != source.agent_id
  end

  test "a stale source version and a missing artifact are refused", ctx do
    {:ok, source} = open(ctx)
    source = complete_turn(source)
    {head, agent} = head(source)
    frozen = locator(source, source: %{freeze: :frozen, environment: :confirmed_stopped})

    assert {:error, :conflict} = Agent.fork(frozen, head["id"], agent["lock_version"] + 9, uuid())

    # A definition referencing an absent artifact cannot be copied by reference.
    missing = uuid()

    SQLiteAuthorityRepo.update_all(
      from(a in AgentRow, where: a.id == ^source.agent_id),
      set: [
        definition:
          Map.put(agent["definition"], "tools", %{
            "echo" => %{"artifact_refs" => [missing]}
          })
      ]
    )

    {:ok, %{"agent" => rebound, "head_checkpoint" => rebound_head}} =
      AgentRecords.fetch(SQLiteAuthorityRepo, source.agent_id)

    assert {:error, :artifact_missing} =
             Agent.fork(frozen, rebound_head["id"], rebound["lock_version"], uuid())

    assert child_count(source.agent_id) == 0
  end

  test "adopting late evidence advances context without overwriting the accepted Result", ctx do
    {:ok, source} = open(ctx)
    {_accepted, source} = accept_input(source, "hello")

    {:ok, operation} =
      Beamlet.Agent.Integration.Caller.operation(
        %{id: "echo-profile", capability: "echo"},
        %{"text" => "a"},
        262_144
      )

    calls = [
      %{
        id: "call-1",
        operation: operation,
        assistant: %{
          "role" => "assistant",
          "content" => nil,
          "calls" => [%{"id" => "call-1", "name" => "echo", "arguments" => %{"text" => "a"}}]
        }
      }
    ]

    [call] = calls
    {:ok, messages} = Context.append(messages(source), [call.assistant])

    {:ok, batch} =
      Durable.prepare_batch(source, %{
        calls: [%{id: call.id, operation: call.operation}],
        messages: messages,
        step: 1,
        checkpoint_id: uuid()
      })

    source = %{source | version: batch.version}
    [prepared] = batch.operations

    # The accepted Result is uncertain: the turn blocks, then the interrupted
    # observation is consumed so the Tool result slot is occupied once.
    {:ok, _} = accept_uncertain(source, prepared)

    {:ok, consumed} =
      Durable.consume_results(source, %{
        operations: [%{operation_id: prepared["operation_id"]}],
        messages:
          elem(
            Context.append(messages, [
              %{"role" => "tool", "call_id" => "call-1", "content" => ~s({"status":"uncertain"})}
            ]),
            1
          ),
        order: ["call-1"],
        checkpoint_id: uuid()
      })

    {:ok, blocked} =
      Durable.block(%{source | version: consumed.version}, :uncertain_external_effect)

    source = %{source | version: blocked.version}

    {:ok, %{"operation" => before_operation}} =
      OperationRecords.fetch(SQLiteAuthorityRepo, prepared["operation_id"])

    accepted_result = before_operation["accepted_result"]
    stored_version = before_operation["lock_version"]
    before = messages(source)
    assert length(Enum.filter(before, &(&1["role"] == "tool" and &1["call_id"] == "call-1"))) == 1

    evidence = %{"status" => "ok", "value" => %{"text" => "late"}, "receipt" => "r-1"}

    assert {:ok, decision} =
             Durable.decide(source, %{
               command_id: uuid(),
               checkpoint_id: uuid(),
               decision: %{
                 "resolution" => "confirmed_executed",
                 "operation_id" => prepared["operation_id"],
                 "evidence" => evidence
               }
             })

    assert decision.continuation == "await_input"

    # The accepted Result is untouched.
    {:ok, %{"operation" => stored}} =
      OperationRecords.fetch(SQLiteAuthorityRepo, prepared["operation_id"])

    assert stored["accepted_result"] == accepted_result
    assert stored["lock_version"] == stored_version

    # The paused context advanced by exactly one correction message and the
    # original Tool result slot is still occupied once.
    advanced = messages(source)
    assert length(advanced) == length(before) + 1
    assert List.last(advanced)["role"] == "user"
    assert List.last(advanced)["content"] =~ "Late evidence resolved Tool call call-1"

    assert length(Enum.filter(advanced, &(&1["role"] == "tool" and &1["call_id"] == "call-1"))) ==
             1

    assert {:ok, %{"head_checkpoint" => head}} =
             AgentRecords.fetch(SQLiteAuthorityRepo, source.agent_id)

    assert head["continuation"] == "await_input"

    {:ok, %{"events" => events}} =
      AgentRecords.history_page(SQLiteAuthorityRepo, source.agent_id, limit: 500)

    decision_event = Enum.find(events, &(&1["type"] == "agent.decision"))
    assert decision_event["payload"]["adopted"] == true
    assert decision_event["payload"]["evidence"] == evidence
    assert decision_event["payload"]["evidence_digest"] == digest_of(evidence)
  end

  defp accept_uncertain(durable, operation) do
    {:ok, %{"operation" => stored}} =
      OperationRecords.fetch(SQLiteAuthorityRepo, operation["operation_id"])

    {:ok, %{"agent" => agent}} = AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    OperationRecords.accept_result(SQLiteAuthorityRepo, %{
      operation_id: operation["operation_id"],
      expected_version: stored["lock_version"],
      agent: %{expected_generation: agent["generation"], accept_seq: operation["accept_seq"]},
      result: %{"status" => "uncertain", "value" => nil, "reason" => "deadline"},
      event: %{
        id: uuid(),
        type: "operation.result_accepted",
        payload: %{"operation_id" => operation["operation_id"]}
      }
    })
  end

  defp digest_of(value) do
    {:ok, digest} = Codec.digest(value, :event)
    digest
  end
end
