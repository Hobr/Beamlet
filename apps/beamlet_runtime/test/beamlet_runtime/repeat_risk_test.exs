defmodule BeamletRuntime.RepeatRiskTest do
  use ExUnit.Case, async: false
  alias Beamlet.{Definition, Identity, Report}
  alias BeamletRuntime.Coordinator
  alias BeamletRuntime.Handlers.Echo
  alias BeamletRuntime.Storage.SQLite

  test "accepted repeat survives SQL restart, grants both attempts, and retains immutable submission identity" do
    directory = Path.join(System.tmp_dir!(), "beamlet-repeat-#{Ecto.UUID.generate()}")
    path = Path.join(directory, "authority.db")
    on_exit(fn -> File.rm_rf!(directory) end)
    repo = start_repo(path)
    :ok = SQLite.migrate(repo)

    c =
      Coordinator.new(
        repo: repo,
        collection: "collection",
        actor: "local",
        handlers: [{Echo, %{}}],
        ttl: 1000
      )

    {:ok, identity} = Identity.new(c.collection, "agent", "repeat")

    {:ok, definition} =
      Definition.new(%{
        operation: "beamlet.echo.v1",
        input: "result",
        policy: :retry_once,
        repeat_accepted: true
      })

    {:ok, submitted} = Coordinator.submit(c, identity, definition)
    id = submitted.facts.intent.id
    old = grant(c, id)
    assert {:success, "result"} = Echo.invoke(old, %{})
    Supervisor.stop(repo)
    repo = start_repo(path)
    :ok = SQLite.migrate(repo)
    c = %{c | repo: repo}
    assert {:ok, replay} = Coordinator.submit(c, identity, definition)
    assert replay.facts.intent.definition.repeat_accepted

    assert {:error, :definition_conflict} =
             Coordinator.submit(c, identity, %{definition | repeat_accepted: false})

    Process.sleep(1005)
    assert {:ok, _expired} = Coordinator.recover(c, id)
    assert {:ok, replacement} = Coordinator.recover(c, id)
    execution = replacement.facts.intent.current_execution_id
    assert replacement.facts.intent.executions[execution].replacement.basis == :repeat_accepted
    next = grant(c, id)
    assert {:success, "result"} = Echo.invoke(next, %{})
    assert {:success, "result"} = Echo.invoke(old, %{})

    report = %Report{
      id: "next",
      token: next.token,
      operation: definition.operation,
      kind: :success,
      body: "result"
    }

    assert {:ok, committed} = Coordinator.worker_report(c, report)
    assert committed.facts.intent.outcome.execution_id == execution
    assert {:ok, late} = Coordinator.worker_report(c, %{report | id: "old", token: old.token})
    assert late.facts.intent.outcome == committed.facts.intent.outcome
    assert late.facts.intent.executions[old.token.execution_id].result.kind == :success
  end

  defp start_repo(path),
    do:
      start_supervised!(
        Supervisor.child_spec({SQLite, database: path, pool_size: 1},
          id: make_ref(),
          restart: :temporary
        )
      )

  defp grant(c, id) do
    {:ok, prepared} = Coordinator.prepare(c, id)
    execution = prepared.facts.intent.current_execution_id

    {:ok, %{reply: {:claimed, token}}} =
      Coordinator.claim(c, id, execution, "worker", Ecto.UUID.generate(), 0)

    {:ok, committed} = Coordinator.authorize(c, token, %{"echo" => true})
    {:ok, grant} = Coordinator.grant(committed)
    grant
  end
end
