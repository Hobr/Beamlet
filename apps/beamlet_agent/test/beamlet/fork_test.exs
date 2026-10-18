Code.require_file("../support/reference_fixture.ex", __DIR__)

defmodule Beamlet.Agent.ForkTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Beamlet.Actions.Storage.OperationRecords, as: ActionsOperations
  alias Beamlet.Agent
  alias Beamlet.Agent.ContextBuilder
  alias Beamlet.Agent.Durable
  alias Beamlet.Agent.Integration.Caller
  alias Beamlet.Agent.Loader
  alias Beamlet.Agent.ReferenceFixture
  alias Beamlet.Agent.Storage.AgentRecords
  alias Beamlet.Agent.Storage.Records
  alias Beamlet.Agent.Storage.Schema.Agent, as: AgentRow
  alias Beamlet.Agent.Storage.Schema.Command
  alias Beamlet.Agent.Storage.Schema.Event
  alias Beamlet.Agent.Storage.Schema.Operation
  alias Beamlet.Agent.TraceExport

  setup do
    ctx = ReferenceFixture.open()
    start_supervised!(Agent.AuthoritySupervisor)
    on_exit(fn -> ReferenceFixture.close(ctx) end)
    ctx
  end

  test "safe reference fork is independent and source rows never change", %{durable: d} do
    {d, _} = ReferenceFixture.complete(d)
    before = source_rows(d)
    {:ok, expected} = ContextBuilder.materialize(d.repo, d.control)
    assert {:ok, fork} = ReferenceFixture.fork(d)
    assert source_rows(d) == before
    assert fork.agent_id != d.agent_id
    assert {:ok, loaded} = Durable.inspect(fork.locator)
    assert loaded.control["paused"]
    assert loaded.control["continuation"] == "await_input"
    assert {:ok, ^expected} = ContextBuilder.materialize(d.repo, loaded.control)
    refute inspect(loaded.control) =~ "finished"
    assert loaded.agent["forked_from_agent_id"] == d.agent_id
  end

  test "pending work refuses without inserting child records", %{durable: d} do
    d = ReferenceFixture.input(d)
    {:ok, built} = Durable.context(d, %{})

    {:ok, op} =
      Caller.operation(ReferenceFixture.binding(), built.request, 262_144)

    {:ok, d, [_]} = Durable.prepare(d, [%{operation: op}], "model", built.sources)
    before = counts(d.repo)
    assert {:error, :unsafe_position} = ReferenceFixture.fork(d)
    assert counts(d.repo) == before
  end

  test "context over the native bound is refused rather than truncated", %{durable: d} do
    {d, _} =
      d
      |> ReferenceFixture.input()
      |> ReferenceFixture.model(%{
        "kind" => "text",
        "content" => String.duplicate("x", 1_048_576),
        "calls" => []
      })

    before = counts(d.repo)
    assert {:error, _} = ReferenceFixture.fork(d)
    assert counts(d.repo) == before
  end

  test "command replay returns the same identity and changed risk conflicts", %{durable: d} do
    d = ReferenceFixture.input(d)
    command = ReferenceFixture.uuid()
    assert {:ok, first} = ReferenceFixture.fork(d, command: command)
    assert {:ok, second} = ReferenceFixture.fork(d, command: command)
    assert first == second
    assert {:error, :conflict} = ReferenceFixture.fork(d, command: command, source: %{})

    assert d.repo.aggregate(
             from(a in AgentRow, where: a.forked_from_agent_id == ^d.agent_id),
             :count
           ) == 1
  end

  test "new control inherits no pending, consumption, command dedupe or execution", %{durable: d} do
    {d, _} = ReferenceFixture.complete(d)
    assert {:ok, fork} = ReferenceFixture.fork(d)
    assert {:ok, loaded} = Durable.inspect(fork.locator)
    assert loaded.control["pending"] == []
    assert loaded.control["consumed"] == []
    assert loaded.control["resolutions"] == %{}
    assert loaded.control["turn_id"] == nil

    assert d.repo.aggregate(
             from(o in Operation, where: o.owner_agent_id == ^fork.agent_id),
             :count
           ) == 0

    assert d.repo.aggregate(from(c in Command, where: c.scope_id == ^fork.agent_id), :count) == 0
    assert {:ok, restored} = Durable.restore(fork.locator, fork.version, ReferenceFixture.uuid())

    assert {:ok, resumed} =
             Durable.decide(restored.durable, %{
               decision: %{},
               command_id: ReferenceFixture.uuid()
             })

    assert {:ok, built} =
             Durable.context(
               ReferenceFixture.input(resumed, "new work"),
               ReferenceFixture.catalogue()
             )

    assert length(built.sources) == 6
  end

  test "inherited provenance and export never bill source operations as new execution", %{
    durable: d,
    dir: dir
  } do
    {d, _} = ReferenceFixture.complete(d)
    {:ok, fork} = ReferenceFixture.fork(d)
    assert {:ok, page} = Agent.history(fork.locator, %{view: :facts, origin: :inherited})
    assert [%{"type" => "context.inherited", "origin" => "inherited"}] = page["events"]
    assert {:ok, provenance} = Agent.history(fork.locator, %{view: :provenance})
    assert provenance["inherited"]["references"] == 5
    refute provenance["inherited"]["counted_as_execution"]
    assert {:ok, manifest} = Agent.export(fork.locator, nil, %{dir: Path.join(dir, "export")})
    assert manifest["provenance"]["performed_operations"] == 0
    assert manifest["history_complete"]
    assert {:ok, _} = TraceExport.verify(Path.join(dir, "export"))
  end

  test "default shared environment risk blocks until an explicit recorded decision", %{durable: d} do
    {d, _} = ReferenceFixture.complete(d)
    {:ok, fork} = ReferenceFixture.fork(d, source: %{})
    assert fork.risk == "unconfirmed"
    {:ok, restored} = Durable.restore(fork.locator, fork.version, ReferenceFixture.uuid())
    next = restored.durable

    attrs = %{
      text: "start",
      turn_id: ReferenceFixture.uuid(),
      command_id: ReferenceFixture.uuid()
    }

    before = counts(d.repo)
    assert {:error, {:blocked, :environment_risk_unconfirmed}} = Durable.accept_input(next, attrs)

    assert {:error, {:blocked, :environment_risk_unconfirmed}} =
             Durable.decide(next, %{decision: %{}, command_id: ReferenceFixture.uuid()})

    assert counts(d.repo) == before

    assert {:error, :conflict} =
             Durable.decide(%{next | version: 0}, %{
               decision: %{"risk" => "accepted"},
               command_id: ReferenceFixture.uuid()
             })

    assert {:ok, next} =
             Durable.decide(next, %{
               decision: %{"risk" => "accepted"},
               command_id: ReferenceFixture.uuid()
             })

    assert {:error, {:blocked, :no_pending_risk}} =
             Durable.decide(next, %{
               decision: %{"risk" => "accepted"},
               command_id: ReferenceFixture.uuid()
             })

    assert {:ok, next} = Durable.accept_input(next, attrs)
    assert {:ok, loaded} = Loader.load(d.repo, fork.agent_id)
    assert next.control == loaded.control
    assert {:ok, decisions} = Agent.history(fork.locator, %{view: :decisions})
    assert Enum.any?(decisions["events"], &(&1["payload"]["decision"] == %{"risk" => "accepted"}))
  end

  test "a registered source cannot be declared frozen", %{durable: d} do
    {:ok, ref} =
      Agent.start(node(), id: d.agent_id, model: ReferenceFixture.binding(), durable: d)

    assert {:error, :source_not_frozen} = ReferenceFixture.fork(d)
    assert :ok = Agent.close(ref)
  end

  test "quiet input-only positions can fork but default never grants execution", %{durable: d} do
    assert {:ok, quiet} = ReferenceFixture.fork(d, source: %{})
    assert quiet.risk == "unconfirmed"
    d = ReferenceFixture.input(d)
    assert {:ok, fork} = ReferenceFixture.fork(d)
    assert {:ok, restored} = Durable.restore(fork.locator, fork.version, ReferenceFixture.uuid())
    assert restored.control["continuation"] == "await_input"
  end

  test "stale version and missing local content refuse with zero child writes", %{durable: d} do
    {d, _} = ReferenceFixture.complete(d)
    before = counts(d.repo)
    assert {:error, :conflict} = ReferenceFixture.fork(%{d | version: d.version + 1})
    assert counts(d.repo) == before
    missing = ReferenceFixture.uuid()

    d.repo.update_all(from(a in AgentRow, where: a.id == ^d.agent_id),
      set: [definition: %{"artifact_id" => missing}]
    )

    assert {:error, :artifact_missing} = ReferenceFixture.fork(d)
    assert counts(d.repo) == before
  end

  test "late accepted evidence cannot change accepted output or advance a fork", %{durable: d} do
    {d, [member | _]} = ReferenceFixture.complete(d)
    {:ok, fork} = ReferenceFixture.fork(d)
    {:ok, before} = Durable.inspect(fork.locator)

    assert {:error, :conflict} =
             ActionsOperations.accept_result(d.repo, %{
               operation_id: member["operation_id"],
               expected_version: 1,
               result: %{
                 "status" => "ok",
                 "value" => %{"kind" => "text", "content" => "late", "calls" => []},
                 "reason" => nil
               }
             })

    assert {:ok, ^before} = Durable.inspect(fork.locator)
    {:ok, restored} = Durable.restore(fork.locator, fork.version, ReferenceFixture.uuid())
    assert {:error, _} = Durable.consume(restored.durable, [member["operation_id"]], "completed")
  end

  test "retired parent events are not required, even for chained forks and exports", %{
    durable: d,
    dir: dir
  } do
    {d, _} = ReferenceFixture.complete(d)
    {:ok, fork} = ReferenceFixture.fork(d)
    {:ok, loaded} = Durable.inspect(fork.locator)
    {:ok, expected} = ContextBuilder.materialize(d.repo, loaded.control)
    d.repo.delete_all(from(e in Event, where: e.scope_id == ^d.agent_id))
    assert {:ok, loaded} = Durable.inspect(fork.locator)
    assert {:ok, ^expected} = ContextBuilder.materialize(d.repo, loaded.control)
    {:ok, restored} = Durable.restore(fork.locator, fork.version, ReferenceFixture.uuid())
    assert {:ok, second} = ReferenceFixture.fork(restored.durable)
    assert {:ok, manifest} = Agent.export(second.locator, nil, %{dir: Path.join(dir, "retired")})
    assert manifest["history_complete"]
    assert {:ok, _} = TraceExport.verify(Path.join(dir, "retired"))
  end

  test "replayed fork remains the original response after either Agent advances", %{durable: d} do
    {d, _} = ReferenceFixture.complete(d)
    command = ReferenceFixture.uuid()
    {:ok, fork} = ReferenceFixture.fork(d, command: command)
    {:ok, restored} = Durable.restore(fork.locator, fork.version, ReferenceFixture.uuid())

    {:ok, _} =
      Durable.decide(restored.durable, %{decision: %{}, command_id: ReferenceFixture.uuid()})

    _next_source = ReferenceFixture.input(d, "source moves")
    assert {:ok, ^fork} = ReferenceFixture.fork(d, command: command)
  end

  test "forged direct manifests cannot smuggle a foreign or omitted source into a fork", %{
    durable: d
  } do
    d = ReferenceFixture.input(d)
    before = counts(d.repo)

    attrs = %{
      command_id: ReferenceFixture.uuid(),
      position: Durable.position(d),
      id: ReferenceFixture.uuid(),
      through_seq: d.control["through_seq"],
      timeline: [],
      inheritance: d.control["inheritance"],
      resolutions: %{},
      risk: nil,
      fork_request: %{"through_seq" => d.control["through_seq"], "expected_version" => d.version}
    }

    assert {:error, :conflict} = AgentRecords.fork(d.repo, attrs)
    assert counts(d.repo) == before
  end

  test "deleted inherited content blocks child reconstruction, not hash-as-body fallback", %{
    durable: d
  } do
    d = ReferenceFixture.input(d)
    {:ok, fork} = ReferenceFixture.fork(d)
    {:ok, loaded} = Durable.inspect(fork.locator)
    [ref] = loaded.control["timeline"]

    d.repo.delete_all(
      from(a in Beamlet.Storage.Schema.Artifact, where: a.id == ^ref["artifact_id"])
    )

    assert {:error, :invalid_reference} = Durable.inspect(fork.locator)
  end

  defp counts(repo),
    do: Enum.map([AgentRow, Command, Event, Operation], &repo.aggregate(&1, :count))

  defp source_rows(d),
    do: %{
      agent: d.repo.get!(AgentRow, d.agent_id) |> Records.plain(),
      events:
        d.repo.all(from(e in Event, where: e.scope_id == ^d.agent_id, order_by: e.seq))
        |> Records.plain()
    }
end
