Code.require_file("../support/reference_fixture.ex", __DIR__)

defmodule Beamlet.Agent.HistoryExportTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Beamlet.Actions.Storage.OperationRecords, as: ActionsOperations
  alias Beamlet.Agent
  alias Beamlet.Agent.Durable
  alias Beamlet.Agent.Integration.Caller
  alias Beamlet.Agent.ReferenceFixture
  alias Beamlet.Agent.Storage.AgentRecords
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.Records
  alias Beamlet.Agent.Storage.Schema.Agent, as: AgentRow
  alias Beamlet.Agent.Storage.Schema.Event
  alias Beamlet.Agent.TraceExport
  alias Beamlet.Storage.Artifacts
  alias Beamlet.Storage.Schema.Artifact

  setup do
    ctx = ReferenceFixture.open()
    on_exit(fn -> ReferenceFixture.close(ctx) end)
    Map.put(ctx, :export_dir, Path.join(ctx.dir, "export"))
  end

  test "history and context are readable with no Agent, provider or executor", %{durable: d} do
    {d, _} = ReferenceFixture.complete(d)
    assert Process.whereis(Agent.Registry) == nil
    assert Process.whereis(Beamlet.Runtime.Gateway) == nil

    assert {:ok, %{"turns" => [turn]}} =
             Agent.history(ReferenceFixture.locator(d), %{view: :turns})

    assert turn["turn_id"] == d.turn_id

    assert {:ok, %{"messages" => messages}} =
             Agent.history(ReferenceFixture.locator(d), %{view: :context})

    assert length(messages) == 5
    assert List.last(messages)["content"] == "finished"
  end

  test "context at an older sequence excludes later accepted results", %{durable: d} do
    d = ReferenceFixture.input(d, "first")
    through = d.control["through_seq"]
    {d, _} = ReferenceFixture.model(d, %{"kind" => "text", "content" => "answer", "calls" => []})

    assert {:ok, early} =
             Agent.history(ReferenceFixture.locator(d), %{view: :context, as_of_seq: through})

    assert early["messages"] == [%{"role" => "user", "content" => "first"}]
    assert {:ok, later} = Agent.history(ReferenceFixture.locator(d), %{view: :context})
    assert length(later["messages"]) == 2
  end

  test "turns model operations tools results and evidence remain reachable", %{durable: d} do
    {d, members} = ReferenceFixture.complete(d)
    locator = ReferenceFixture.locator(d)
    assert {:ok, %{"steps" => steps}} = Agent.history(locator, %{view: :steps})
    assert length(steps) == 2
    assert hd(steps)["description"]["payload"]["request"]["messages"] != []
    assert {:ok, %{"operations" => tools}} = Agent.history(locator, %{view: :tools})
    assert Enum.map(tools, & &1["ordinal"]) == [0, 1]
    assert Enum.all?(tools, &(&1["accepted_result"]["status"] == "ok"))

    assert {:ok, %{"attempt" => attempt, "operation" => op}} =
             Agent.history(locator, %{view: :evidence, operation_id: hd(members)["operation_id"]})

    assert attempt["attempt_id"] == hd(members)["attempt_id"]
    assert op["accepted_result"]["status"] == "ok"
  end

  test "export captures both Agent and Operation high waters before paging", %{
    durable: d,
    export_dir: dir
  } do
    d = ReferenceFixture.input(d)
    {:ok, built} = Durable.context(d, %{})

    {:ok, op} =
      Caller.operation(ReferenceFixture.binding(), built.request, 262_144)

    {:ok, d, [member]} = Durable.prepare(d, [%{operation: op}], "model", built.sources)
    {:ok, fixed} = TraceExport.begin(d.repo, d.agent_id)

    assert {:ok, _} =
             ReferenceFixture.accept(d, member, "ok", %{
               "kind" => "text",
               "content" => "later",
               "calls" => []
             })

    {:ok, d} = Durable.consume(d, [member["operation_id"]], "completed")
    d = ReferenceFixture.input(d, "after cutoff")
    assert {:ok, manifest} = TraceExport.write(fixed, %{dir: dir, page: 1})
    assert manifest["high_water"]["history_seq"] < d.control["through_seq"]
    assert manifest["high_water"]["operations"][member["operation_id"]] == 1
    assert hd(lines(dir, "operations"))["operation"]["accepted_result"] == nil
    refute File.read!(Path.join(dir, "events.jsonl")) =~ "after cutoff"
    assert {:ok, _} = TraceExport.verify(dir)
  end

  test "artifacts throughout definition and accepted Result closure are verified", %{
    durable: d,
    export_dir: dir
  } do
    artifact = put_artifact(d.repo, "block")

    d.repo.update_all(from(a in AgentRow, where: a.id == ^d.agent_id),
      set: [definition: %{"artifact_id" => artifact.id}]
    )

    assert {:ok, manifest} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})
    assert [%{"id" => id}] = manifest["artifacts"]
    assert id == artifact.id
    assert {:ok, %{"artifacts" => 1}} = TraceExport.verify(dir)
    File.write!(Path.join([dir, "artifacts", id <> ".bin"]), "changed")
    assert {:error, :artifact_missing_or_corrupt} = TraceExport.verify(dir)
  end

  test "missing and corrupt authority content is explicit and never called complete", %{
    durable: d,
    export_dir: dir
  } do
    artifact = put_artifact(d.repo, "block")

    d.repo.update_all(from(a in AgentRow, where: a.id == ^d.agent_id),
      set: [definition: %{"artifact_id" => artifact.id}]
    )

    d.repo.update_all(from(a in Artifact, where: a.id == ^artifact.id),
      set: [content: "tampered"]
    )

    assert {:ok, manifest} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})
    refute manifest["history_complete"]
    assert [%{"kind" => "artifact", "id" => id}] = manifest["missing"]
    assert id == artifact.id
    assert {:ok, %{"history_complete" => false}} = TraceExport.verify(dir)
  end

  test "oversized individual records remain whole and marked", %{durable: d, export_dir: dir} do
    text = String.duplicate("x", 12_288)
    d = ReferenceFixture.input(d, text)

    assert {:ok, manifest} =
             Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir, page_bytes: 4096})

    assert manifest["files"]["events"]["oversized_records"] != []
    assert List.last(lines(dir, "events"))["payload"]["text"] == text
    assert {:ok, _} = TraceExport.verify(dir)
  end

  test "inherited closure contains direct content without ancestor history", %{
    durable: d,
    export_dir: dir
  } do
    {d, _} = ReferenceFixture.complete(d)
    {:ok, fork} = ReferenceFixture.fork(d)
    assert {:ok, manifest} = Agent.export(fork.locator, nil, %{dir: dir})
    assert manifest["provenance"]["inherited_references"] == 5
    assert manifest["provenance"]["performed_operations"] == 0
    assert manifest["history_complete"]
    refute manifest["provenance"]["parent_history_required"]
    assert length(lines(dir, "operations")) == 4
    assert {:ok, _} = TraceExport.verify(dir)
  end

  test "invalid query filters and foreign evidence are refused", %{durable: d} do
    locator = ReferenceFixture.locator(d)
    assert {:error, :invalid_data} = Agent.history(locator, %{view: :unknown})
    assert {:error, :invalid_data} = Agent.history(locator, %{view: :facts, limit: 0})
    assert {:error, :limit} = Agent.history(locator, %{view: :facts, limit: 10_000})

    assert {:error, :invalid_data} =
             Agent.history(locator, %{view: :evidence, operation_id: ReferenceFixture.uuid()})

    assert {:error, :invalid_data} = Agent.history(locator, %{view: :facts}, %{"bad" => true})
  end

  test "tampered manifest and structurally invalid lines refuse even after rehash", %{
    durable: d,
    export_dir: dir
  } do
    d = ReferenceFixture.input(d)
    {:ok, _} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})
    assert {:ok, %{"execution_authority" => "none"}} = TraceExport.verify(dir)
    path = Path.join(dir, "events.jsonl")
    File.write!(path, String.replace(File.read!(path), "hello", "changed"))
    assert {:error, :digest_or_count_mismatch} = TraceExport.verify(dir)
    File.write!(path, Jason.encode!(%{"seq" => 1}) <> "\n")

    rewrite_manifest(dir, fn m ->
      put_in(m, ["files", "events"], %{"count" => 1, "sha256" => Codec.hash(File.read!(path))})
    end)

    assert {:error, :invalid_history} = TraceExport.verify(dir)
    rewrite_manifest(dir, &Map.put(&1, "export_version", 99))
    assert {:error, {:unsupported_export_version, 99}} = TraceExport.verify(dir)
  end

  test "redaction removes prompts requests results definitions evidence and artifacts", %{
    durable: d,
    export_dir: dir
  } do
    d = ReferenceFixture.input(d, "secret-prompt")

    {d, _} =
      ReferenceFixture.model(d, %{"kind" => "text", "content" => "secret-reply", "calls" => []})

    assert {:ok, manifest} =
             Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir, redaction: :drop_content})

    refute manifest["history_complete"]
    assert manifest["artifacts"] == []

    for name <- ~w(events inputs operations definition) do
      refute File.read!(Path.join(dir, name <> ".jsonl")) =~ "secret-"
    end

    assert {:ok, %{"history_complete" => false}} = TraceExport.verify(dir)
  end

  test "missing and nonregular package files return safe errors", %{durable: d, export_dir: dir} do
    {:ok, _} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})
    File.rm!(Path.join(dir, "events.jsonl"))
    assert {:error, {:missing_or_oversize_file, "events.jsonl"}} = TraceExport.verify(dir)
    File.mkdir!(Path.join(dir, "events.jsonl"))
    assert {:error, {:missing_or_oversize_file, "events.jsonl"}} = TraceExport.verify(dir)
  end

  test "hand edited completeness claims cannot make a redacted trace complete", %{
    durable: d,
    export_dir: dir
  } do
    {:ok, _} =
      Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir, redaction: :drop_content})

    rewrite_manifest(dir, &Map.put(&1, "history_complete", true))
    assert {:error, :inconsistent_manifest} = TraceExport.verify(dir)
  end

  test "history cursors retain the original highwater across concurrent appends", %{durable: d} do
    {d, _} = ReferenceFixture.complete(d)
    locator = ReferenceFixture.locator(d)
    {:ok, first} = Agent.history(locator, %{view: :facts, limit: 2})
    _next = ReferenceFixture.input(d, "not in this traversal")
    events = drain(locator, first)
    assert Enum.map(events, & &1["seq"]) == Enum.to_list(1..d.control["through_seq"])
    refute inspect(events) =~ "not in this traversal"
  end

  test "tiny pages preserve ordered complete long histories and original request checksums", %{
    durable: d,
    export_dir: dir
  } do
    d =
      Enum.reduce(1..105, d, fn n, acc ->
        {:ok, response} =
          AgentRecords.advance(acc.repo, %{
            command_id: ReferenceFixture.uuid(),
            position: Durable.position(acc),
            turn_id: nil,
            type: "context.selected",
            payload: %{"selection" => n}
          })

        %{
          acc
          | version: response["lock_version"],
            control: Map.put(acc.control, "through_seq", response["through_seq"])
        }
      end)

    assert {:ok, manifest} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir, page: 2})
    assert length(lines(dir, "events")) == 106
    assert manifest["page_policy"]["page"] == 2
    assert {:ok, _} = TraceExport.verify(dir)
  end

  test "corrupt accepted output blocks restoration and makes export explicitly incomplete", %{
    durable: d,
    export_dir: dir
  } do
    {d, [member | _]} = ReferenceFixture.complete(d)

    d.repo.update_all(
      from(o in Beamlet.Actions.Storage.Schema.Operation, where: o.id == ^member["operation_id"]),
      set: [accepted_result: %{"status" => "error"}]
    )

    assert {:error, :invalid_reference} = Durable.inspect(ReferenceFixture.locator(d))
    assert {:ok, manifest} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})
    refute manifest["history_complete"]
    assert Enum.any?(manifest["missing"], &(&1["kind"] == "operation"))
    assert {:ok, %{"history_complete" => false}} = TraceExport.verify(dir)
  end

  test "source digest is verified beyond recomputed file and Result digests", %{
    durable: d,
    export_dir: dir
  } do
    {d, _} = ReferenceFixture.complete(d)
    {:ok, _} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})
    [first | rest] = lines(dir, "operations")

    tampered =
      put_in(first, ["operation", "accepted_result", "value"], %{
        "kind" => "text",
        "content" => "forged",
        "calls" => []
      })

    {:ok, digest} = Codec.digest(tampered["operation"]["accepted_result"], :result)
    tampered = put_in(tampered, ["accepted_event", "payload", "accepted_digest"], digest)
    path = Path.join(dir, "operations.jsonl")
    File.write!(path, Enum.map([tampered | rest], &[Jason.encode!(&1), "\n"]))

    rewrite_manifest(
      dir,
      &put_in(&1, ["files", "operations", "sha256"], Codec.hash(File.read!(path)))
    )

    assert {:error, :invalid_reference} = TraceExport.verify(dir)
  end

  test "offline verification rejects Operation sources attributed to another owner", %{
    durable: d,
    export_dir: dir
  } do
    {d, _} = ReferenceFixture.complete(d)
    {:ok, _} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})
    original = lines(dir, "operations")
    path = Path.join(dir, "operations.jsonl")

    for row <- original do
      forged = put_in(row, ["operation", "owner_agent_id"], ReferenceFixture.uuid())
      rows = Enum.map(original, &if(&1 == row, do: forged, else: &1))
      File.write!(path, Enum.map(rows, &[Jason.encode!(&1), "\n"]))

      rewrite_manifest(
        dir,
        &put_in(&1, ["files", "operations", "sha256"], Codec.hash(File.read!(path)))
      )

      assert {:error, :invalid_reference} = TraceExport.verify(dir)
    end
  end

  test "malformed inherited references return safe errors online and offline", %{
    durable: d,
    export_dir: dir
  } do
    {d, _} = ReferenceFixture.complete(d)
    {:ok, fork} = ReferenceFixture.fork(d)
    {:ok, _} = Agent.export(fork.locator, nil, %{dir: dir})
    original = lines(dir, "events")
    path = Path.join(dir, "events.jsonl")

    for invalid <- [42, %{"type" => "inherited_result", "reference" => 42}] do
      payload = %{"sources" => [invalid], "closure" => [invalid]}

      rows =
        Enum.map(
          original,
          &if(&1["type"] == "context.inherited", do: Map.put(&1, "payload", payload), else: &1)
        )

      File.write!(path, Enum.map(rows, &[Jason.encode!(&1), "\n"]))

      rewrite_manifest(
        dir,
        &put_in(&1, ["files", "events", "sha256"], Codec.hash(File.read!(path)))
      )

      assert {:error, _} = TraceExport.verify(dir)

      d.repo.update_all(
        from(e in Event,
          where: e.scope_id == ^fork.agent_id and e.type == "context.inherited"
        ),
        set: [payload: payload]
      )

      assert {:error, _} = TraceExport.begin(d.repo, fork.agent_id)
    end
  end

  test "reusing a nonempty output directory refuses rather than leaving redacted plaintext", %{
    durable: d,
    export_dir: dir
  } do
    d = ReferenceFixture.input(d, "private")
    {:ok, _} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})

    assert {:error, :export_directory_not_empty} =
             Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir, redaction: :drop_content})
  end

  test "existing large artifact budget remains readable offline", %{durable: d, export_dir: dir} do
    artifact = put_artifact(d.repo, String.duplicate("x", 4_194_305))

    d.repo.update_all(from(a in AgentRow, where: a.id == ^d.agent_id),
      set: [definition: %{"artifact_id" => artifact.id}]
    )

    assert {:ok, _} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})
    assert {:ok, %{"artifacts" => 1}} = TraceExport.verify(dir)
  end

  test "malformed manifest highwater returns an error rather than raising", %{
    durable: d,
    export_dir: dir
  } do
    {:ok, _} = Agent.export(ReferenceFixture.locator(d), nil, %{dir: dir})
    rewrite_manifest(dir, &put_in(&1, ["high_water", "history_seq"], "bad"))
    assert {:error, :invalid_data} = TraceExport.verify(dir)
  end

  test "receipt evidence and its artifacts are captured before later receipts", %{
    durable: d,
    export_dir: dir
  } do
    {d, [member | _]} = ReferenceFixture.complete(d)
    artifact = put_artifact(d.repo, "receipt attachment")
    evidence = put_evidence(d, member, %{"artifact_id" => artifact.id, "marker" => "original"})
    locator = ReferenceFixture.locator(d)

    assert {:ok, %{"evidence" => [^evidence]}} =
             Agent.history(locator, %{view: :evidence, operation_id: member["operation_id"]})

    {:ok, fixed} = TraceExport.begin(d.repo, d.agent_id)
    put_evidence(d, member, %{"marker" => "later"})
    assert {:ok, _} = TraceExport.write(fixed, dir: dir)
    row = Enum.find(lines(dir, "operations"), &(&1["operation"]["id"] == member["operation_id"]))
    assert row["evidence"] == [evidence]
    assert {:ok, %{"artifacts" => 1}} = TraceExport.verify(dir)
    path = Path.join(dir, "operations.jsonl")

    rows =
      Enum.map(lines(dir, "operations"), fn r ->
        if r == row,
          do: put_in(r, ["evidence", Access.at(0), "content", "marker"], "forged"),
          else: r
      end)

    File.write!(path, Enum.map(rows, &[Jason.encode!(&1), "\n"]))

    rewrite_manifest(
      dir,
      &put_in(&1, ["files", "operations", "sha256"], Codec.hash(File.read!(path)))
    )

    assert {:error, :invalid_reference} = TraceExport.verify(dir)
  end

  test "evidence overflow refuses a complete export", %{durable: d} do
    {d, [member | _]} = ReferenceFixture.complete(d)
    for n <- 1..32, do: put_evidence(d, member, %{"n" => n})
    assert {:ok, _} = TraceExport.begin(d.repo, d.agent_id)
    put_evidence(d, member, %{"n" => 33})
    assert {:error, :limit} = TraceExport.begin(d.repo, d.agent_id)
  end

  defp put_evidence(d, member, content) do
    {:ok, evidence} =
      ActionsOperations.record_evidence(d.repo, %{
        id: ReferenceFixture.uuid(),
        operation_id: member["operation_id"],
        attempt_id: member["attempt_id"],
        executor_id: d.runtime.executor_id,
        evidence_id: ReferenceFixture.uuid(),
        content: content
      })

    evidence
  end

  defp lines(dir, name),
    do: Path.join(dir, name <> ".jsonl") |> File.stream!() |> Enum.map(&Jason.decode!/1)

  defp rewrite_manifest(dir, fun) do
    path = Path.join(dir, "manifest.json")
    File.write!(path, Jason.encode!(fun.(Jason.decode!(File.read!(path)))))
  end

  defp drain(locator, page, acc \\ []) do
    acc = acc ++ page["events"]

    if page["next_cursor"] do
      {:ok, next} = Agent.history(locator, %{view: :facts, limit: 2}, page["next_cursor"])
      drain(locator, next, acc)
    else
      acc
    end
  end

  defp put_artifact(repo, bytes) do
    {:ok, artifact} =
      Records.transact(repo, fn ->
        Artifacts.put(repo, %{
          id: ReferenceFixture.uuid(),
          content: bytes,
          size: byte_size(bytes),
          digest: Codec.hash(bytes),
          media_type: "text/plain",
          recorded_at: DateTime.utc_now()
        })
      end)

    artifact
  end
end
