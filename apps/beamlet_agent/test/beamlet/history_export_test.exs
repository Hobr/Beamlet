defmodule Beamlet.Agent.HistoryExportModel do
  @moduledoc false
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.Models.Deterministic

  @impl true
  defdelegate validate_invocation(invocation), to: Deterministic

  @impl true
  def complete(request, invocation, context \\ %Beamlet.Harness.Context{}),
    do: Deterministic.complete(request, invocation, context)
end

defmodule Beamlet.Agent.HistoryExportTest do
  @moduledoc """
  Stage D: durable history queries and bounded trace export, exercised through
  real SQLite authority files (no in-memory database) and the public surfaces
  `Beamlet.Agent.history/3`, `Beamlet.Agent.export/3` and
  `Beamlet.Agent.TraceExport.verify/1`.
  """
  use ExUnit.Case, async: false
  import Ecto.Query

  alias Beamlet.Agent
  alias Beamlet.Agent.{Durable, TraceExport}
  alias Beamlet.Agent.Integration.Caller
  alias Beamlet.Harness.{Context, Model}

  alias Beamlet.Storage.{
    AgentRecords,
    Artifacts,
    Codec,
    Dataset,
    ExecutorJournalRepo,
    OperationRecords,
    Records,
    SQLiteAuthorityRepo
  }

  @tools %{"echo" => %{id: "echo-profile", capability: "echo"}}

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "beamlet-agent-history-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    authority = Path.join(dir, "authority.db")
    journal = Path.join(dir, "journal.db")

    {:ok, _} =
      Dataset.initialize(SQLiteAuthorityRepo,
        database: authority,
        peer_database: journal,
        dataset_id: Ecto.UUID.generate()
      )

    {:ok, _} =
      Dataset.initialize(ExecutorJournalRepo,
        database: journal,
        peer_database: authority,
        dataset_id: Ecto.UUID.generate()
      )

    start_supervised!({Beamlet.Agent.AuthoritySupervisor, model_providers: providers()})

    on_exit(fn ->
      stop_repo(SQLiteAuthorityRepo)
      stop_repo(ExecutorJournalRepo)
      File.rm_rf!(dir)
    end)

    %{
      dir: Path.join(dir, "export"),
      authority_id: Ecto.UUID.generate(),
      executor_id: Ecto.UUID.generate(),
      executor_boot_id: Ecto.UUID.generate(),
      report: self()
    }
  end

  defp providers do
    Map.merge(Model.default_providers(), %{
      "counting" => Beamlet.Agent.HistoryExportModel
    })
  end

  defp stop_repo(repo) do
    if pid = Process.whereis(repo), do: Supervisor.stop(pid)
    :ok
  catch
    _, _ -> :ok
  end

  defp uuid, do: Ecto.UUID.generate()

  defp model_binding(
         config \\ %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
       ) do
    %{provider: "counting", config: config}
  end

  defp definition(overrides \\ %{}) do
    Map.merge(
      %{
        "schema_version" => 1,
        "model" => %{"provider" => "counting", "config" => %{}},
        "tools" => %{"echo" => %{"profile" => "echo-profile"}}
      },
      overrides
    )
  end

  defp runtime_config(ctx) do
    %{
      authority_repo: SQLiteAuthorityRepo,
      journal_repo: ExecutorJournalRepo,
      executor_id: ctx.executor_id,
      executor_boot_id: ctx.executor_boot_id
    }
  end

  defp open(ctx, opts \\ []) do
    {:ok, durable} =
      Durable.open(SQLiteAuthorityRepo, %{
        agent_id: uuid(),
        authority_id: ctx.authority_id,
        alias: "history#{System.unique_integer([:positive])}",
        definition: Keyword.get(opts, :definition, definition()),
        command_id: uuid()
      })

    elem(Durable.with_runtime(durable, runtime_config(ctx)), 1)
  end

  defp locator(durable), do: %{repo: SQLiteAuthorityRepo, agent_id: durable.agent_id}

  defp input(durable, text) do
    {:ok, head} = AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    {:ok, messages} =
      Context.append(head["head_checkpoint"]["data"]["messages"], [
        %{"role" => "user", "content" => text}
      ])

    {:ok, response} =
      Durable.accept_input(durable, %{
        command_id: uuid(),
        turn_id: uuid(),
        messages: messages,
        checkpoint_id: uuid()
      })

    {:ok, %{"agent" => agent}} = AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    {Map.put(response, :history_seq, agent["history_seq"]),
     %{durable | version: response.version, turn_id: response.turn_id}}
  end

  defp reply(durable, step, content, calls \\ []) do
    {:ok, head} = AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    assistant = %{"role" => "assistant", "content" => content, "calls" => calls}

    {:ok, messages} =
      Context.append(head["head_checkpoint"]["data"]["messages"], [assistant])

    {:ok, response} =
      Durable.record_reply(durable, %{
        request: %{"messages" => messages, "step" => step},
        messages: messages,
        reply: %{
          "kind" => if(calls == [], do: "text", else: "tool_calls"),
          "content" => content,
          "calls" => calls
        },
        step: step,
        checkpoint_id: uuid()
      })

    {response, %{durable | version: response.version}}
  end

  defp plain_calls do
    Enum.map(calls(), fn call ->
      %{"id" => call.id, "name" => call.name, "arguments" => call.arguments}
    end)
  end

  defp calls do
    [
      %{id: "call-1", name: "echo", arguments: %{"text" => "first"}},
      %{id: "call-2", name: "echo", arguments: %{"text" => "second"}}
    ]
  end

  defp prepare_batch(durable) do
    {:ok, head} = AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    assistant = %{
      "role" => "assistant",
      "content" => nil,
      "calls" =>
        Enum.map(calls(), fn call ->
          %{"id" => call.id, "name" => call.name, "arguments" => call.arguments}
        end)
    }

    {:ok, messages} =
      Context.append(head["head_checkpoint"]["data"]["messages"], [assistant])

    operations =
      Enum.map(calls(), fn call ->
        {:ok, operation} =
          Caller.operation(
            @tools[call.name],
            call.arguments,
            262_144
          )

        %{id: call.id, operation: operation}
      end)

    {:ok, response} =
      Durable.prepare_batch(durable, %{
        calls: operations,
        messages: messages,
        step: 1,
        checkpoint_id: uuid()
      })

    {response, %{durable | version: response.version}}
  end

  defp accept_result(durable, operation, value) do
    {:ok, %{"operation" => stored}} =
      OperationRecords.fetch(SQLiteAuthorityRepo, operation["operation_id"])

    {:ok, %{"agent" => agent}} = AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)

    {:ok, accepted} =
      OperationRecords.accept_result(SQLiteAuthorityRepo, %{
        operation_id: operation["operation_id"],
        expected_version: stored["lock_version"],
        agent: %{expected_generation: agent["generation"], accept_seq: operation["accept_seq"]},
        result: %{"status" => "ok", "value" => value, "reason" => nil},
        event: %{
          id: uuid(),
          type: "operation.result_accepted",
          payload: %{"operation_id" => operation["operation_id"], "status" => "ok"}
        }
      })

    {accepted, operation}
  end

  defp evidence!(ctx, operation) do
    {:ok, _} =
      OperationRecords.record_evidence(SQLiteAuthorityRepo, %{
        id: uuid(),
        operation_id: operation["operation_id"],
        attempt_id: operation["attempt_id"],
        executor_id: ctx.executor_id,
        evidence_id: uuid(),
        content: %{"version" => 1, "termination" => %{"kind" => "returned"}},
        resolution: nil
      })
  end

  defp turn(ctx) do
    {_input, durable} = input(open(ctx), "hello")
    {_reply, durable} = reply(durable, 0, "on it", plain_calls())
    {response, durable} = prepare_batch(durable)

    {operations, _durable} =
      Enum.map_reduce(response.operations, durable, fn operation, durable ->
        evidence!(ctx, operation)
        {_accepted, operation} = accept_result(durable, operation, %{"text" => "done"})
        {operation, durable}
      end)

    {durable, operations}
  end

  defp source_marker_event!(durable, source_agent_id) do
    {:ok, agent} = AgentRecords.fetch(SQLiteAuthorityRepo, durable.agent_id)
    seq = agent["agent"]["history_seq"] + 1

    {:ok, event} =
      Records.transact(SQLiteAuthorityRepo, fn ->
        Records.insert(
          SQLiteAuthorityRepo,
          Records.event_changeset(%{
            id: uuid(),
            scope_id: durable.agent_id,
            seq: seq,
            type: "context.inherited",
            schema_version: 1,
            payload: %{"role" => "user", "content" => "from the source Agent"},
            source_agent_id: source_agent_id,
            source_event_id: uuid(),
            recorded_at: DateTime.utc_now()
          })
        )
      end)

    {1, _} =
      SQLiteAuthorityRepo.update_all(
        from(a in Beamlet.Storage.Schema.Agent, where: a.id == ^durable.agent_id),
        set: [history_seq: seq]
      )

    event
  end

  test "history is readable with no live Agent and after Runtime retention", ctx do
    runtime =
      start_supervised!(
        {Beamlet.Runtime,
         execution: true,
         handlers: %{
           "agent.native" =>
             {Beamlet.Agent.Integration.Handler, %{model_providers: providers(), profiles: %{}}}
         },
         capabilities: ["model.provider:counting"],
         limits: [refresh_ms: 10, expiry_ms: 50]}
      )

    durable = open(ctx)

    {:ok, ref} =
      Agent.start(node(), id: durable.agent_id, model: model_binding(), durable: durable)

    assert {:ok, turn_id} = Agent.input(ref, "hello durable", uuid())
    assert :ok = Agent.close(ref)
    refute Process.alive?(ref.pid)
    assert {:error, _} = Agent.lookup(node(), durable.agent_id)
    assert Process.alive?(runtime)

    {:ok, %{"view" => "turns", "turns" => [turn]}} =
      Agent.history(locator(durable), %{view: :turns})

    assert turn["turn_id"] == turn_id
    assert turn["continuation"] == "await_model_result"

    {:ok, %{"view" => "facts", "events" => events}} =
      Agent.history(locator(durable), %{view: :facts})

    assert Enum.map(events, & &1["type"]) == ["agent.created", "input.accepted"]
    assert Enum.all?(events, &(&1["origin"] == "performed"))

    {:ok, %{"view" => "context", "messages" => messages}} =
      Agent.history(locator(durable), %{view: :context})

    assert Enum.any?(messages, &(&1["content"] == "hello durable"))
  end

  test "as_of_seq returns the context at that point and later evidence does not rewrite it",
       ctx do
    durable = open(ctx)
    {accepted, durable} = input(durable, "first")
    input_seq = accepted.history_seq
    {_reply, durable} = reply(durable, 0, "answer")

    {:ok, %{"messages" => early, "as_of_seq" => ^input_seq, "derived_by" => "commit_order"}} =
      Agent.history(locator(durable), %{view: :context, as_of_seq: input_seq})

    assert length(early) == 1
    assert hd(early)["content"] == "first"

    {:ok, %{"messages" => later}} = Agent.history(locator(durable), %{view: :context})
    assert length(later) == 2

    # More committed evidence must not rewrite the earlier effective context.
    {_response, durable} = prepare_batch(durable)

    {:ok, %{"messages" => again}} =
      Agent.history(locator(durable), %{view: :context, as_of_seq: input_seq})

    assert again == early
  end

  test "turns, model steps, tool requests/results and execution evidence are reachable", ctx do
    {durable, operations} = turn(ctx)

    {:ok, %{"turns" => [turn]}} = Agent.history(locator(durable), %{view: :turns})
    assert turn["events"] >= 4

    {:ok, %{"steps" => [step], "step_operations" => "external"}} =
      Agent.history(locator(durable), %{view: :steps})

    assert step["kind"] == "tool_calls"
    assert step["reply"]["calls"] |> length() == 2
    assert is_binary(step["request_digest"])

    {:ok, %{"operations" => tools}} = Agent.history(locator(durable), %{view: :tools})
    assert length(tools) == 2
    assert Enum.map(tools, & &1["ordinal"]) == [1, 2]
    assert Enum.all?(tools, &(&1["accepted_result"]["status"] == "ok"))

    operation_id = hd(operations)["operation_id"]

    {:ok, %{"view" => "evidence", "attempt" => attempt, "evidence" => [evidence]}} =
      Agent.history(locator(durable), %{view: :evidence, operation_id: operation_id})

    assert attempt["attempt_id"] == hd(operations)["attempt_id"]
    assert is_binary(evidence["digest"])

    {:ok, %{"decisions" => decisions}} = Agent.history(locator(durable), %{view: :decisions})
    assert Enum.any?(decisions, &(&1["kind"] == "execution_result"))
  end

  test "export fixes the high-water mark before paging", ctx do
    {durable, _operations} = turn(ctx)

    {:ok, fixed} = TraceExport.begin(SQLiteAuthorityRepo, %{agent_id: durable.agent_id})
    {appended, _durable} = input(durable, "after the mark")

    {:ok, manifest} = TraceExport.write(fixed, %{dir: ctx.dir, page: 2, page_bytes: 65_536})

    assert manifest["high_water"]["history_seq"] == fixed.history_seq
    assert appended.history_seq > fixed.history_seq
    assert manifest["counts"]["events"] == fixed.history_seq
    assert manifest["ordering"] == "per_scope_sequence"

    {:ok, %{"events" => exported}} = verify_events(ctx.dir)
    assert Enum.all?(exported, &(&1["seq"] <= fixed.history_seq))

    # A second export of the same scope reports the appended event afterwards.
    {:ok, later} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id},
        dir: Path.join(ctx.dir, "later"),
        page: 2
      )

    assert later["high_water"]["history_seq"] > manifest["high_water"]["history_seq"]
    assert later["counts"]["events"] == later["high_water"]["history_seq"]
  end

  test "JSONL lines parse, artifact digests verify, missing or corrupt artifacts are reported",
       ctx do
    artifact_id = put_artifact!("token block")

    durable =
      open(ctx,
        definition:
          definition(%{
            "tools" => %{
              "echo" => %{
                "profile" => "echo-profile",
                "artifact_refs" => [artifact_id]
              }
            }
          })
      )

    {_input, durable} = input(durable, "hello")

    {:ok, manifest} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id}, dir: ctx.dir)

    assert [%{"id" => ^artifact_id, "digest" => digest}] = manifest["artifacts"]
    assert is_binary(digest)
    assert manifest["missing"] == []
    assert manifest["history_complete"] == true

    assert {:ok, verified} = TraceExport.verify(ctx.dir)
    assert verified["events"] == manifest["counts"]["events"]
    assert verified["checkpoints"] == manifest["counts"]["checkpoints"]
    assert verified["artifacts"] == 1

    # A corrupt stored artifact is reported, never silently skipped.
    SQLiteAuthorityRepo.update_all(
      from(a in Beamlet.Storage.Schema.Artifact, where: a.id == ^artifact_id),
      set: [content: "tampered"]
    )

    {:error, _} = Artifacts.fetch(SQLiteAuthorityRepo, artifact_id)

    {:ok, corrupt} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id},
        dir: Path.join(ctx.dir, "corrupt")
      )

    assert [%{"kind" => "artifact_corrupt", "id" => ^artifact_id}] = corrupt["missing"]
    assert corrupt["history_complete"] == false

    # A referenced artifact that is absent is reported too.
    missing_id = uuid()

    {:ok, absent} =
      run_export(
        definition(%{
          "tools" => %{"echo" => %{"profile" => "echo-profile", "artifact_refs" => [missing_id]}}
        }),
        Path.join(ctx.dir, "absent")
      )

    assert [%{"kind" => "artifact_missing", "id" => ^missing_id}] = absent["missing"]
    assert absent["history_complete"] == false
  end

  test "an oversized single record is written whole and reported", ctx do
    durable = open(ctx)
    large = String.duplicate("x", 12_288)
    {_accepted, durable} = input(durable, large)

    {:ok, manifest} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id},
        dir: ctx.dir,
        page_bytes: 4_096
      )

    assert [%{"kind" => "oversized_record"} = oversized] = manifest["oversized_records"]
    assert is_binary(oversized["checkpoint_id"])

    checkpoints =
      Path.join(ctx.dir, "checkpoints.jsonl")
      |> File.stream!()
      |> Enum.map(fn line -> Jason.decode!(String.trim_trailing(line, "\n")) end)

    stored = Enum.find(checkpoints, &(&1["id"] == oversized["checkpoint_id"]))
    assert hd(stored["data"]["messages"])["content"] == large
    assert {:ok, _} = TraceExport.verify(ctx.dir)
  end

  test "inherited entries keep their source markers and are not counted as this Agent's work",
       ctx do
    durable = open(ctx)
    {_accepted, durable} = input(durable, "own input")
    source_agent_id = uuid()
    event = source_marker_event!(durable, source_agent_id)

    {:ok, %{"events" => inherited, "view" => "facts"}} =
      Agent.history(locator(durable), %{view: :facts, origin: :inherited})

    assert [%{"seq" => seq} = entry] = inherited
    assert seq == event.seq
    assert entry["origin"] == "inherited"
    assert entry["source_agent_id"] == source_agent_id
    assert is_binary(entry["source_event_id"])

    {:ok, %{"inherited" => %{"counted_as_execution" => false}}} =
      Agent.history(locator(durable), %{view: :provenance})

    fixed = begin_export!(durable)

    {:ok, manifest} =
      TraceExport.write(fixed, %{dir: ctx.dir, page: 4})

    assert manifest["provenance"]["inherited_entries"] == 1
    assert manifest["provenance"]["performed_entries"] == 2
    assert manifest["provenance"]["inherited_counted_as_execution"] == false

    {:ok, %{"events" => events}} = verify_events(ctx.dir)
    exported = Enum.find(events, &(&1["seq"] == seq))
    assert exported["source_agent_id"] == source_agent_id
  end

  test "a fork source is external, never assembled recursively", ctx do
    {:ok, created} =
      AgentRecords.create_agent(SQLiteAuthorityRepo, %{
        command: %{scope_id: ctx.authority_id, command_id: uuid(), params: %{"create" => true}},
        id: uuid(),
        authority_id: ctx.authority_id,
        definition: definition(),
        generation: 0,
        forked_from_agent_id: uuid(),
        forked_from_checkpoint_id: uuid(),
        checkpoint: %{id: uuid(), data: Durable.state(%{}), safe_to_fork: true},
        event: %{id: uuid(), type: "agent.created", payload: %{"inherited" => true}}
      })

    locator = %{repo: SQLiteAuthorityRepo, agent_id: created["agent_id"]}

    {:ok, %{"external" => [source], "inherited" => %{"events" => 0}}} =
      Agent.history(locator, %{view: :provenance})

    assert source["relation"] == "fork_source"
    assert source["history_included?"] == false

    {:ok, manifest} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: created["agent_id"]}, dir: ctx.dir)

    assert [%{"kind" => "ancestor_history"}] = manifest["missing"]
    assert [%{"included" => false}] = manifest["provenance"]["external"]
    assert manifest["history_complete"] == false
  end

  test "reports missing fields and rejects invalid queries without widening scope", ctx do
    durable = open(ctx)
    {_accepted, durable} = input(durable, "hello")

    {:error, :invalid_data} = Agent.history(locator(durable), %{view: :unknown})
    {:error, :invalid_data} = Agent.history(locator(durable), %{view: :facts, limit: 0})
    {:error, :limit} = Agent.history(locator(durable), %{view: :facts, limit: 10_000})
    {:error, :invalid_data} = Agent.history(locator(durable), %{view: :evidence})

    {:error, :conflict} =
      Agent.history(%{repo: SQLiteAuthorityRepo, agent_id: uuid()}, %{view: :provenance})
  end

  test "the verifier rejects a tampered manifest or line and grants no execution", ctx do
    durable = open(ctx)
    {_accepted, durable} = input(durable, "hello")

    {:ok, _manifest} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id}, dir: ctx.dir)

    assert {:ok, %{"execution_authority" => "none"}} = TraceExport.verify(ctx.dir)

    events_path = Path.join(ctx.dir, "events.jsonl")
    original = File.read!(events_path)
    File.write!(events_path, String.replace(original, "input.accepted", "input.accepteD"))
    assert {:error, :digest_mismatch} = TraceExport.verify(ctx.dir)

    # A structural line defect is caught even when the digest is recomputed.
    File.write!(events_path, "{\"scope_id\":\"#{durable.agent_id}\",\"seq\":1}\n")

    manifest_path = Path.join(ctx.dir, "manifest.json")
    {:ok, manifest} = Jason.decode(File.read!(manifest_path))

    manifest =
      put_in(
        manifest,
        ["digests", "events_sha256"],
        Codec.hash(File.read!(events_path))
      )
      |> put_in(["counts", "events"], 1)

    File.write!(manifest_path, Jason.encode!(manifest))
    assert {:error, {:missing_line_key, _}} = TraceExport.verify(ctx.dir)

    # A tampered manifest identity is refused before any line is trusted.
    File.write!(manifest_path, Jason.encode!(Map.put(manifest, "agent_id", "not-a-uuid")))
    assert {:error, :invalid_data} = TraceExport.verify(ctx.dir)

    File.write!(manifest_path, Jason.encode!(Map.put(manifest, "export_version", 99)))
    assert {:error, {:unsupported_export_version, 99}} = TraceExport.verify(ctx.dir)
  end

  test "redaction drops content while marking it and never claims a restorable export", ctx do
    durable = open(ctx)
    {_accepted, durable} = input(durable, "sensitive prompt")

    {:ok, manifest} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id},
        dir: ctx.dir,
        redaction: :drop_content
      )

    assert manifest["redaction"]["policy"] == "drop_content"
    assert manifest["redaction"]["restorable"] == false

    assert manifest["redaction"]["dropped_entries"] ==
             manifest["counts"]["events"] + manifest["counts"]["checkpoints"]

    assert manifest["history_complete"] == false

    {:ok, %{"events" => events}} = verify_events(ctx.dir)
    assert Enum.all?(events, &(&1["payload"] == %{"redacted" => true}))
    assert Enum.all?(events, &(&1["redacted"] == ["payload"]))

    refute File.read!(Path.join(ctx.dir, "events.jsonl")) =~ "sensitive prompt"
    refute File.read!(Path.join(ctx.dir, "checkpoints.jsonl")) =~ "sensitive prompt"
    assert {:ok, %{"history_complete" => false}} = TraceExport.verify(ctx.dir)
  end

  test "a missing or non-regular package file is reported, not raised", ctx do
    durable = open(ctx)
    {_accepted, durable} = input(durable, "hello")

    {:ok, _manifest} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id}, dir: ctx.dir)

    assert {:ok, _} = TraceExport.verify(ctx.dir)

    File.rm!(Path.join(ctx.dir, "events.jsonl"))
    assert {:error, {:missing_file, "events.jsonl"}} = TraceExport.verify(ctx.dir)
  end

  test "a hand-edited completeness claim is refused", ctx do
    durable = open(ctx)
    {_accepted, durable} = input(durable, "hello")

    {:ok, manifest} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id},
        dir: ctx.dir,
        redaction: :drop_content
      )

    # The export is genuinely not restorable; claiming otherwise is inconsistent.
    assert manifest["redaction"]["restorable"] == false

    manifest_path = Path.join(ctx.dir, "manifest.json")
    honest = File.read!(manifest_path)
    tampered = Jason.encode!(Map.put(manifest, "history_complete", true))
    File.write!(manifest_path, tampered)

    assert {:error, :inconsistent_manifest} = TraceExport.verify(ctx.dir)
    File.write!(manifest_path, honest)
    assert {:ok, %{"history_complete" => false}} = TraceExport.verify(ctx.dir)
  end

  test "history cursors round-trip without skipping or repeating a record", ctx do
    {durable, _operations} = turn(ctx)

    {:ok, first} = Agent.history(locator(durable), %{view: :facts, limit: 2})
    assert length(first["events"]) <= 2

    all = drain_facts(locator(durable), first)
    {:ok, one_page} = Agent.history(locator(durable), %{view: :facts, limit: 500})

    assert Enum.map(all, & &1["seq"]) == Enum.map(one_page["events"], & &1["seq"])
    assert Enum.map(all, & &1["seq"]) == Enum.sort(Enum.map(all, & &1["seq"]))
  end

  test "paging is keyset and ordered even with a tiny page", ctx do
    {durable, _operations} = turn(ctx)

    {:ok, manifest} =
      TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id},
        dir: ctx.dir,
        page: 2
      )

    {:ok, %{"events" => events}} = verify_events(ctx.dir)
    assert length(events) == manifest["counts"]["events"]
    assert Enum.map(events, & &1["seq"]) == Enum.sort(Enum.map(events, & &1["seq"]))
    assert Enum.map(events, & &1["seq"]) == Enum.uniq(Enum.map(events, & &1["seq"]))
    assert manifest["page_policy"]["page"] == 2
  end

  defp drain_facts(locator, page, acc \\ []) do
    acc = acc ++ page["events"]

    case page["next_cursor"] do
      nil ->
        acc

      cursor ->
        {:ok, next} = Agent.history(locator, %{view: :facts, after_seq: cursor, limit: 2})
        drain_facts(locator, next, acc)
    end
  end

  ## Fixtures

  defp put_artifact!(content) do
    {:ok, artifact} =
      Records.transact(SQLiteAuthorityRepo, fn ->
        Artifacts.put(SQLiteAuthorityRepo, %{
          id: uuid(),
          digest: Codec.hash(content),
          media_type: "text/plain",
          size: byte_size(content),
          content: content,
          recorded_at: DateTime.utc_now()
        })
      end)

    artifact.id
  end

  defp run_export(definition, dir) do
    durable =
      open(%{authority_id: uuid(), executor_id: uuid(), executor_boot_id: uuid()},
        definition: definition
      )

    _ = durable

    TraceExport.export(SQLiteAuthorityRepo, %{agent_id: durable.agent_id}, dir: dir)
  end

  defp begin_export!(durable) do
    {:ok, fixed} = TraceExport.begin(SQLiteAuthorityRepo, %{agent_id: durable.agent_id})
    fixed
  end

  defp verify_events(dir) do
    path = Path.join(dir, "events.jsonl")

    events =
      path
      |> File.stream!()
      |> Enum.map(fn line -> Jason.decode!(String.trim_trailing(line, "\n")) end)

    {:ok, %{"events" => events}}
  end
end
