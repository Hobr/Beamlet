defmodule BeamletRuntime.Storage.SQLiteTest do
  use ExUnit.Case, async: false
  import Kernel, except: [binding: 0]
  alias Beamlet.{Definition, Identity, Report}
  alias BeamletRuntime.Storage.{Codec, Commit, Error}
  alias BeamletRuntime.Storage.SQLite
  alias BeamletRuntime.Storage.SQLite.Repo
  alias Ecto.Adapters.SQL

  setup do
    directory =
      Path.join(System.tmp_dir!(), "beamlet-sqlite-test-#{System.unique_integer([:positive])}")

    path = Path.join(directory, "ledger.db")
    {:ok, repo} = SQLite.start_link(database: path, pool_size: 4, busy_timeout: 1000)
    Process.unlink(repo)
    :ok = SQLite.migrate(repo)

    on_exit(fn ->
      if Process.alive?(repo), do: Supervisor.stop(repo)
      File.rm_rf!(directory)
    end)

    %{repo: repo, path: path}
  end

  defp definition(input \\ nil, policy \\ :stop_on_failure) do
    {:ok, value} = Definition.new(%{operation: "request.v1", input: input, policy: policy})
    value
  end

  defp identity(key \\ "key", collection \\ "collection", namespace \\ "namespace") do
    {:ok, value} = Identity.new(collection, namespace, key)
    value
  end

  defp submit(repo, key \\ "key") do
    assert {:ok, %Commit{} = result} = SQLite.submit(repo, identity(key), definition(), "actor")
    result.facts.intent.id
  end

  defp command(repo, id, command, opts \\ []) do
    assert {:ok, %Commit{} = result} =
             SQLite.command(repo, "collection", id, command, "actor", opts)

    result
  end

  defp prepared(repo) do
    id = submit(repo)
    command(repo, id, {:create_execution, "execution"})
    id
  end

  defp claimed(repo, ttl \\ 60_000) do
    id = prepared(repo)
    result = command(repo, id, {:claim, "execution", "worker", "session", 0, ttl})
    {:claimed, token} = result.reply
    {id, token}
  end

  defp binding do
    %{
      "operation" => "request.v1",
      "handler" => "handler.v1",
      "protocol" => "invoke.v1",
      "resource" => %{"account" => "account"},
      "completion" => %{"correlation" => "correlation"}
    }
  end

  defp authorized(repo) do
    {id, token} = claimed(repo)
    command(repo, id, {:authorize, token, binding()})
    {id, token}
  end

  defp report(token, kind \\ :success, body \\ nil),
    do: %Report{id: "report", token: token, operation: "request.v1", kind: kind, body: body}

  defp sql(repo, statement, params \\ []),
    do: SQL.query!(repo, statement, params, log: false)

  test "uses persistent WAL, FULL synchronous writes and enforced foreign keys", %{repo: repo} do
    assert [["wal"]] = sql(repo, "PRAGMA journal_mode").rows
    assert [[2]] = sql(repo, "PRAGMA synchronous").rows
    assert [[1]] = sql(repo, "PRAGMA foreign_keys").rows
    assert_raise ArgumentError, fn -> SQLite.start_link(database: ":memory:") end
  end

  test "same keyed identity returns unchanged facts; conflicting definitions are rejected", %{
    repo: repo
  } do
    id = submit(repo)
    assert {:ok, existing} = SQLite.submit(repo, identity(), definition(), "actor")
    assert existing.facts.intent.id == id
    assert existing.facts.revision == 1
    assert existing.events == []

    assert {:error, :definition_conflict} =
             SQLite.submit(repo, identity(), definition("changed"), "actor")

    assert [[1]] = sql(repo, "SELECT count(*) FROM beamlet_intents").rows
  end

  test "unkeyed submissions and different namespace/collection identities remain independent", %{
    repo: repo
  } do
    first = submit(repo, nil)
    second = submit(repo, nil)
    assert first != second
    assert {:ok, other} = SQLite.submit(repo, identity("key", "other"), definition(), "actor")

    assert {:ok, sibling} =
             SQLite.submit(repo, identity("key", "collection", "other"), definition(), "actor")

    assert other.facts.intent.id != sibling.facts.intent.id
    assert {:error, :intent_not_found} = SQLite.read(repo, "collection", other.facts.intent.id)
  end

  test "independent Repo pools serialize simultaneous same-key submissions", %{
    repo: repo,
    path: path
  } do
    {:ok, second} = SQLite.start_link(database: path, pool_size: 2, busy_timeout: 1000)
    Process.unlink(second)
    on_exit(fn -> if Process.alive?(second), do: Supervisor.stop(second) end)

    results =
      1..12
      |> Task.async_stream(
        fn n ->
          SQLite.submit(
            if(rem(n, 2) == 0, do: repo, else: second),
            identity(),
            definition(),
            "actor"
          )
        end,
        max_concurrency: 12,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, {:ok, result}} -> result end)

    assert results |> Enum.map(& &1.facts.intent.id) |> Enum.uniq() |> length() == 1
    assert [[1]] = sql(repo, "SELECT count(*) FROM beamlet_history").rows
  end

  test "two workers race for generation zero and only one owner wins", %{repo: repo} do
    id = prepared(repo)

    results =
      ["worker-a", "worker-b"]
      |> Task.async_stream(fn worker ->
        SQLite.command(
          repo,
          "collection",
          id,
          {:claim, "execution", worker, "session", 0, 60_000},
          "actor"
        )
      end)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, %Commit{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :generation_mismatch}, &1)) == 1
    assert {:ok, facts} = SQLite.read(repo, "collection", id)
    assert facts.intent.executions["execution"].lease.token.generation == 1
  end

  test "lost Claim reply is recovered without allocating another generation or audit group", %{
    repo: repo
  } do
    {id, token} = claimed(repo)
    assert {:ok, before} = SQLite.read(repo, "collection", id)
    replay = command(repo, id, {:claim, "execution", "worker", "session", 0, 60_000})
    assert replay.reply == {:claimed, token}
    assert replay.facts.revision == before.revision
    assert replay.events == []
  end

  test "report, unique Outcome, Closed and ordered History commit together", %{repo: repo} do
    {id, token} = authorized(repo)
    result = command(repo, id, {:record_report, report(token, :success, %{"answer" => "ok"})})
    assert result.facts.intent.phase == :closed
    assert result.facts.intent.outcome.value == %{"answer" => "ok"}
    assert [[bytes]] = sql(repo, "SELECT outcome FROM beamlet_outcomes").rows
    assert {:ok, outcome} = Codec.decode(bytes)
    assert outcome === result.facts.intent.outcome
    assert {:ok, page} = SQLite.history(repo, "collection", id, result.facts.revision)

    assert Enum.map(Enum.take(page.entries, -2), & &1.event.kind) == [
             :report_recorded,
             :outcome_accepted
           ]

    assert Enum.take(page.entries, -2) |> Enum.map(& &1.revision) |> Enum.uniq() == [
             result.facts.revision
           ]
  end

  test "SQL failure at History insertion rolls back snapshot, report and Outcome", %{repo: repo} do
    {id, token} = authorized(repo)
    assert {:ok, before} = SQLite.read(repo, "collection", id)

    sql(
      repo,
      "CREATE TRIGGER fail_history BEFORE INSERT ON beamlet_history BEGIN SELECT RAISE(ABORT, 'fault'); END"
    )

    assert {:error, %Error{}} =
             SQLite.command(repo, "collection", id, {:record_report, report(token)}, "actor")

    assert {:ok, after_failure} = SQLite.read(repo, "collection", id)
    assert after_failure === before
    assert [[0]] = sql(repo, "SELECT count(*) FROM beamlet_outcomes").rows
    sql(repo, "DROP TRIGGER fail_history")

    assert command(repo, id, {:record_report, report(token)}).facts.intent.outcome.kind ==
             :succeeded
  end

  test "duplicate report adds neither state revision nor audit; contradictory report preserves Outcome",
       %{repo: repo} do
    {id, token} = authorized(repo)
    success = command(repo, id, {:record_report, report(token)})
    duplicate = command(repo, id, {:record_report, report(token)})
    assert duplicate.events == []
    assert duplicate.facts === success.facts
    conflict = command(repo, id, {:record_report, report(token, :failure)})
    assert conflict.facts.intent.outcome === success.facts.intent.outcome
    assert conflict.facts.intent.executions["execution"].conflict
    assert length(conflict.facts.intent.executions["execution"].reports) == 2
    assert [[1]] = sql(repo, "SELECT count(*) FROM beamlet_outcomes").rows
  end

  test "two simultaneous conflicting reports retain both and accept at most one Outcome", %{
    repo: repo
  } do
    {id, token} = authorized(repo)

    results =
      [:success, :failure]
      |> Task.async_stream(fn kind ->
        SQLite.command(repo, "collection", id, {:record_report, report(token, kind)}, "actor")
      end)
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, %Commit{}}}, &1))
    assert {:ok, facts} = SQLite.read(repo, "collection", id)
    assert facts.intent.phase == :closed
    assert facts.intent.executions["execution"].conflict
    assert length(facts.intent.executions["execution"].reports) == 2
    assert [[1]] = sql(repo, "SELECT count(*) FROM beamlet_outcomes").rows
  end

  test "cancellation and completion race without overwriting the first Outcome", %{repo: repo} do
    {id, token} = authorized(repo)

    tasks =
      [{:cancel, "cancelled"}, {:record_report, report(token)}]
      |> Enum.map(fn action ->
        Task.async(fn -> SQLite.command(repo, "collection", id, action, "actor") end)
      end)

    Enum.each(tasks, fn task -> assert {:ok, %Commit{}} = Task.await(task) end)
    assert {:ok, facts} = SQLite.read(repo, "collection", id)
    assert facts.intent.outcome.kind in [:succeeded, :cancelled]
    assert [[1]] = sql(repo, "SELECT count(*) FROM beamlet_outcomes").rows
    assert command(repo, id, {:cancel, "different"}).facts.intent.outcome === facts.intent.outcome
  end

  test "lock wait is included in Authority time and expiry rejection durably saves its barrier",
       %{repo: repo} do
    {id, token} = claimed(repo, 40)
    parent = self()

    holder =
      Task.async(fn ->
        prior = Repo.put_dynamic_repo(repo)

        try do
          Repo.transaction(
            fn ->
              send(parent, :locked)

              receive do
                :release -> :ok
              after
                80 -> :ok
              end
            end,
            mode: :immediate
          )
        after
          Repo.put_dynamic_repo(prior)
        end
      end)

    assert_receive :locked
    result = command(repo, id, {:authorize, token, binding()})
    Task.await(holder)
    assert result.reply == {:rejected, :lease_expired}
    assert result.facts.intent.executions["execution"].lease.invalidated
    assert [%{kind: :lease_expired, at: at}] = result.events
    assert at >= result.facts.intent.executions["execution"].lease.expires_at
    assert {:ok, read} = SQLite.read(repo, "collection", id)
    assert read === result.facts
  end

  test "restart retains original grants and allows late authenticated completion", %{
    repo: repo,
    path: path
  } do
    {id, token} = authorized(repo)
    pending = command(repo, id, {:record_report, report(token, :pending)})
    Supervisor.stop(repo)
    {:ok, restarted} = SQLite.start_link(database: path, pool_size: 2)
    Process.unlink(restarted)
    on_exit(fn -> if Process.alive?(restarted), do: Supervisor.stop(restarted) end)
    assert {:ok, facts} = SQLite.read(restarted, "collection", id)
    assert facts === pending.facts
    replay = command(restarted, id, {:authorize, token, %{}})
    assert replay.reply == {:authorized, token, binding()}
    assert replay.events == []
    completion = %{report(token) | id: "completion"}

    assert command(restarted, id, {:record_report, completion}).facts.intent.outcome.kind ==
             :succeeded
  end

  test "lost committed submission and completion replies can be recovered using stable identities",
       %{repo: repo} do
    # Discard the first committed reply, as a transport can do after commit.
    {:ok, _discarded} = SQLite.submit(repo, identity(), definition(), "actor")
    id = submit(repo)
    command(repo, id, {:create_execution, "execution"})
    claim = command(repo, id, {:claim, "execution", "worker", "session", 0, 60_000})
    {:claimed, token} = claim.reply
    command(repo, id, {:authorize, token, binding()})

    {:ok, _discarded} =
      SQLite.command(repo, "collection", id, {:record_report, report(token)}, "actor")

    duplicate = command(repo, id, {:record_report, report(token)})
    assert duplicate.reply == :duplicate_report
    assert duplicate.facts.intent.outcome.kind == :succeeded
    assert [[1]] = sql(repo, "SELECT count(*) FROM beamlet_outcomes").rows
  end

  test "history pages stay anchored to the read revision while later facts are added", %{
    repo: repo
  } do
    {id, token} = authorized(repo)
    assert {:ok, before} = SQLite.read(repo, "collection", id)
    assert {:ok, first} = SQLite.history(repo, "collection", id, before.revision, {0, 0}, 2)
    assert length(first.entries) == 2
    assert first.next != nil
    command(repo, id, {:record_report, report(token)})
    assert {:ok, second} = SQLite.history(repo, "collection", id, before.revision, first.next, 2)
    assert second.next == nil
    assert Enum.all?(second.entries, &(&1.revision <= before.revision))
    refute Enum.any?(first.entries ++ second.entries, &(&1.event.kind == :outcome_accepted))
  end

  test "discovery can be rescanned after restart and does not allocate permission", %{repo: repo} do
    id = prepared(repo)
    assert {:ok, [%{intent_id: ^id, phase: "prepared"}]} = SQLite.discover(repo, "collection")
    assert {:ok, facts} = SQLite.read(repo, "collection", id)
    assert facts.intent.executions["execution"].authorization == nil
    assert {:ok, []} = SQLite.discover(repo, "other")
    command(repo, id, {:cancel, nil})
    assert {:ok, []} = SQLite.discover(repo, "collection")
  end

  test "replacement is persisted with the original attempt and its audit basis", %{repo: repo} do
    assert {:ok, created} = SQLite.submit(repo, identity(), definition(nil, :retry_once), "actor")
    id = created.facts.intent.id
    command(repo, id, {:create_execution, "execution"})
    replaced = command(repo, id, {:replace_execution, "execution", "retry", "recover"})
    assert replaced.reply == {:replaced, "retry", :unstarted}
    assert {:ok, facts} = SQLite.read(repo, "collection", id)
    assert facts === replaced.facts
    assert facts.intent.current_execution_id == "retry"
    assert map_size(facts.intent.executions) == 2
    assert [%{kind: :execution_replaced, details: %{basis: :unstarted}}] = replaced.events
  end

  test "independent callback completes persisted Pending without a Worker token", %{repo: repo} do
    {id, token} = authorized(repo)
    command(repo, id, {:record_report, report(token, :pending)})

    source = %Beamlet.Report.Source{
      kind: :callback,
      collection: token.collection,
      intent_id: token.intent_id,
      execution_id: token.execution_id,
      binding: binding()["completion"]
    }

    callback = %Report{
      id: "callback",
      source: source,
      operation: "request.v1",
      kind: :success,
      body: "done"
    }

    completed = command(repo, id, {:record_report, callback})
    assert completed.facts.intent.outcome.value == "done"
    assert {:ok, facts} = SQLite.read(repo, "collection", id)
    assert facts === completed.facts
    assert facts.intent.outcome.report_identity == {source, "callback"}
  end

  test "busy BEGIN exhausts a bounded retry budget without changing facts", %{
    repo: repo,
    path: path
  } do
    id = prepared(repo)
    assert {:ok, before} = SQLite.read(repo, "collection", id)
    {:ok, contender} = SQLite.start_link(database: path, pool_size: 1, busy_timeout: 5)
    Process.unlink(contender)
    on_exit(fn -> if Process.alive?(contender), do: Supervisor.stop(contender) end)
    # Establish the second connection before taking the writer lock.
    assert {:ok, _} = SQLite.read(contender, "collection", id)
    parent = self()

    holder =
      Task.async(fn ->
        prior = Repo.put_dynamic_repo(repo)

        try do
          Repo.transaction(
            fn ->
              send(parent, :held)

              receive do
                :release -> :ok
              after
                1000 -> :ok
              end
            end,
            mode: :immediate
          )
        after
          Repo.put_dynamic_repo(prior)
        end
      end)

    assert_receive :held
    result = SQLite.command(contender, "collection", id, {:cancel, nil}, "actor", retries: 1)
    send(holder.pid, :release)
    Task.await(holder)
    assert {:error, %Error{kind: :busy_exhausted}} = result
    assert {:ok, after_failure} = SQLite.read(repo, "collection", id)
    assert after_failure === before
  end

  test "foreign-key and unique-outcome constraints protect the SQL ledger", %{repo: repo} do
    assert_raise Exqlite.Error, fn ->
      sql(repo, "INSERT INTO beamlet_outcomes VALUES(?,?,?)", ["collection", "missing", "invalid"])
    end

    {id, token} = authorized(repo)
    command(repo, id, {:record_report, report(token)})

    assert_raise Exqlite.Error, fn ->
      sql(repo, "INSERT INTO beamlet_outcomes VALUES(?,?,?)", ["collection", id, "invalid"])
    end
  end
end
