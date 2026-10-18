defmodule Beamlet.Agent.Storage.DatasetTest do
  use ExUnit.Case, async: false

  alias Beamlet.Actions.Storage.DispatchScopes
  alias Beamlet.Actions.Storage.ExecutorJournalRepo
  alias Beamlet.Actions.Storage.Schema.Execution
  alias Beamlet.Actions.Storage.Schema.ExecutionEvidence
  alias Beamlet.Actions.Storage.Schema.JournalAttempt
  alias Beamlet.Actions.Storage.Schema.Operation
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.JSON
  alias Beamlet.Agent.Storage.Schema.Agent
  alias Beamlet.Agent.Storage.Schema.Checkpoint
  alias Beamlet.Agent.Storage.Schema.Command
  alias Beamlet.Agent.Storage.Schema.Event
  alias Beamlet.Agent.Storage.SQLiteAuthorityRepo
  alias Beamlet.Storage.Artifacts
  alias Beamlet.Storage.Dataset
  alias Beamlet.Storage.Migrations
  alias Beamlet.Storage.Schema.Artifact
  alias Beamlet.Storage.Transaction

  alias Ecto.Adapters.SQL
  @repo SQLiteAuthorityRepo

  setup do
    dir = Path.join(System.tmp_dir!(), "beamlet-storage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    opts = [
      descriptor: Beamlet.Agent.Storage.Profiles.authority(),
      database: Path.join(dir, "authority.db"),
      peer_database: Path.join(dir, "journal.db"),
      dataset_id: Ecto.UUID.generate()
    ]

    on_exit(fn ->
      File.rm_rf!(dir)
    end)

    %{dir: dir, opts: opts}
  end

  defp sql(statement, params \\ []), do: SQL.query!(@repo, statement, params, log: false)

  test "missing open does not create a dataset; explicit initialization and empty reopen", %{
    opts: opts
  } do
    assert {:error, :dataset_missing} = Dataset.open(@repo, opts)
    refute File.exists?(opts[:database])
    assert {:ok, pid} = Dataset.initialize(@repo, opts)
    assert Process.alive?(pid)
    assert {:error, :conflict} = Dataset.initialize(@repo, opts)

    assert [[opts[:dataset_id], "agent-authority", 3, 0]] ==
             sql(
               "SELECT dataset_id, profile, format_version, restored_backup FROM storage_metadata"
             ).rows

    @repo.stop()
    assert {:ok, _} = Dataset.open(@repo, opts)
  end

  test "old authority format is refused without rewriting file contents", %{opts: opts} do
    {:ok, _} = Dataset.initialize(@repo, opts)
    sql("UPDATE storage_metadata SET format_version = 1")
    sql("DELETE FROM schema_migrations WHERE version != 1")
    # Establish a consistent closed-file baseline; previous WAL cleanup is not
    # part of the subsequent open under test.
    sql("PRAGMA wal_checkpoint(TRUNCATE)")
    @repo.stop()
    before = File.read!(opts[:database])
    assert {:error, :schema_unsupported} = Dataset.open(@repo, opts)
    assert File.read!(opts[:database]) == before
  end

  test "actual PRAGMA settings and engine version", %{opts: opts} do
    assert {:ok, _} = Dataset.initialize(@repo, opts)

    for {pragma, expected} <- [
          {"journal_mode", "wal"},
          {"synchronous", 2},
          {"foreign_keys", 1},
          {"busy_timeout", 0}
        ] do
      assert [[expected]] == sql("PRAGMA " <> pragma).rows
    end

    assert [[version]] = sql("SELECT sqlite_version()").rows
    IO.puts("Storage SQLite engine: #{version}")
  end

  test "identity, role, backup and newer formats fail closed", %{opts: opts} do
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    @repo.stop()

    assert {:error, :dataset_mismatch} =
             Dataset.open(@repo, Keyword.put(opts, :dataset_id, Ecto.UUID.generate()))

    for {update, error} <- [
          {"profile = 'actions-journal'", :dataset_mismatch},
          {"format_version = 4", :schema_unsupported},
          {"restored_backup = 1", :restored_backup}
        ] do
      assert {:ok, _} = Dataset.open(@repo, opts)
      sql("UPDATE storage_metadata SET " <> update)
      @repo.stop()
      assert {:error, ^error} = Dataset.open(@repo, opts)

      # Explicit test-only repair to exercise each independent refusal; production never clears it.
      {:ok, _} = @repo.start_link(opts)

      sql(
        "UPDATE storage_metadata SET profile = 'agent-authority', format_version = 3, restored_backup = 0"
      )

      @repo.stop()
    end

    assert {:ok, _} = Dataset.open(@repo, opts)
    sql("INSERT INTO schema_migrations(version, inserted_at) VALUES (3, CURRENT_TIMESTAMP)")
    @repo.stop()
    assert {:error, :schema_unsupported} = Dataset.open(@repo, opts)
  end

  test "metadata missing never initializes on reopen", %{opts: opts} do
    File.write!(opts[:database], "")
    assert {:error, :dataset_missing} = Dataset.open(@repo, opts)
    {:ok, _} = @repo.start_link(opts)
    assert [[0]] == sql("SELECT COUNT(*) FROM sqlite_master WHERE name = 'storage_metadata'").rows
  end

  test "an already registered Repo is refused before touching its file", %{opts: opts} do
    peer =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    Process.register(peer, @repo)
    assert {:error, :conflict} = Dataset.initialize(@repo, opts)
    refute File.exists?(opts[:database])
    send(peer, :stop)
  end

  test "startup configuration cannot override checked file identity or Repo name", %{opts: opts} do
    assert {:error, :invalid_data} =
             Dataset.initialize(@repo, Keyword.put(opts, :name, :unexpected_repo))

    assert {:error, :invalid_data} =
             Dataset.initialize(@repo, Keyword.put(opts, :url, "sqlite:///not-opened"))

    assert {:error, :invalid_data} = Dataset.open(:not_a_storage_repo, password: "never-returned")
    refute File.exists?(opts[:database])
  end

  test "paths cannot alias through spelling, hardlinks or symlinks", %{opts: opts, dir: dir} do
    assert {:error, :path_alias} =
             Dataset.initialize(
               @repo,
               Keyword.put(opts, :peer_database, Path.join(dir, "./authority.db"))
             )

    File.write!(opts[:database], "")
    File.ln!(opts[:database], opts[:peer_database])
    assert {:error, :path_alias} = Dataset.open(@repo, opts)
    File.rm!(opts[:peer_database])
    File.ln_s!(opts[:database], opts[:peer_database])
    assert {:error, :invalid_data} = Dataset.open(@repo, opts)
  end

  test "concurrent initialization reserves exactly one file", %{opts: opts} do
    # Each task traps the linked Repo lifecycle and stops its successful installation.
    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          case Dataset.initialize(@repo, opts) do
            {:ok, _} ->
              @repo.stop()
              :initialized

            error ->
              error
          end
        end)
      end

    assert Enum.sort(Enum.map(tasks, &Task.await(&1, 10_000))) ==
             Enum.sort([:initialized, {:error, :dataset_exists}])

    assert {:ok, _} = Dataset.open(@repo, opts)
  end

  test "failed metadata insert rolls back migration DDL", %{opts: opts} do
    File.write!(opts[:database], "")
    {:ok, _} = @repo.start_link(opts)

    # A NOT NULL violation aborts and rolls back deterministically; it is not an
    # unknown outcome the caller must reconcile.
    assert {:error, :invalid_data} =
             Migrations.install_metadata(@repo, nil, Beamlet.Agent.Storage.Profiles.authority())

    assert [[0]] ==
             sql(
               "SELECT COUNT(*) FROM sqlite_master WHERE name IN ('agents', 'storage_metadata')"
             ).rows

    @repo.stop()
    assert {:error, :dataset_missing} = Dataset.open(@repo, opts)
  end

  test "exact table ownership and independent executor journal", %{opts: opts} do
    assert {:ok, _} = Dataset.initialize(@repo, opts)

    names =
      sql("SELECT name FROM sqlite_master WHERE type = 'table'").rows
      |> List.flatten()
      |> Enum.sort()

    assert names ==
             Enum.sort(
               ~w(agents agent_events agent_operations checkpoints operations executions execution_evidence operation_events dispatch_scopes commands artifacts storage_metadata schema_migrations)
             )

    journal = [
      descriptor: Beamlet.Actions.Storage.Profiles.journal(),
      database: opts[:peer_database],
      peer_database: opts[:database],
      dataset_id: Ecto.UUID.generate()
    ]

    assert {:ok, _} = Dataset.initialize(ExecutorJournalRepo, journal)

    assert SQL.query!(
             ExecutorJournalRepo,
             "SELECT name FROM sqlite_master WHERE type = 'table'",
             [],
             log: false
           ).rows
           |> List.flatten()
           |> Enum.sort() == ~w(artifacts journal_attempts schema_migrations storage_metadata)

    row = %{
      id: Ecto.UUID.generate(),
      authority_id: opts[:dataset_id],
      operation_id: Ecto.UUID.generate(),
      attempt_id: Ecto.UUID.generate(),
      description_digest: Codec.hash("{}"),
      executor_id: journal[:dataset_id],
      executor_boot_id: Ecto.UUID.generate(),
      state: "start_intent",
      acknowledged: false,
      schema_version: 1,
      lock_version: 0,
      recorded_at: DateTime.utc_now(),
      terminal_artifacts: %{"version" => 1, "items" => %{}}
    }

    assert {:ok, _} = ExecutorJournalRepo.insert(JournalAttempt.changeset(%JournalAttempt{}, row))

    refute JournalAttempt.changeset(%JournalAttempt{}, %{
             row
             | terminal_artifacts: %{"version" => 2, "items" => %{}}
           }).valid?

    refute JournalAttempt.changeset(%JournalAttempt{}, %{
             row
             | terminal_artifacts: %{"version" => 1, "items" => %{}, "extra" => true}
           }).valid?

    ExecutorJournalRepo.stop()
    assert {:ok, _} = Dataset.open(ExecutorJournalRepo, journal)

    assert ExecutorJournalRepo.get!(JournalAttempt, row.id).terminal_artifacts == %{
             "version" => 1,
             "items" => %{}
           }
  end

  test "ordinary reads do not reserve the writer; immediate writes do", %{opts: opts} do
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    {:ok, conn} = Exqlite.start_link(database: opts[:database], busy_timeout: 100)

    try do
      assert {:ok, :ok} =
               @repo.transaction(fn ->
                 sql("SELECT COUNT(*) FROM agents")
                 assert {:ok, _} = Exqlite.query(conn, "BEGIN IMMEDIATE")
                 Exqlite.query!(conn, "ROLLBACK")
                 :ok
               end)

      assert {:ok, :locked} =
               Transaction.write(@repo, fn ->
                 assert {:error, _} = Exqlite.query(conn, "BEGIN IMMEDIATE")
                 :locked
               end)
    after
      GenServer.stop(conn)
    end
  end

  test "custom busy handler bounds real contention and succeeds after release", %{opts: opts} do
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    {:ok, blocker} = Exqlite.start_link(database: opts[:database])

    try do
      Exqlite.query!(blocker, "BEGIN IMMEDIATE")
      started = System.monotonic_time(:millisecond)
      task = Task.async(fn -> Transaction.write(@repo, fn -> :written end) end)
      assert {:error, :storage_outcome_unknown} = Task.await(task, 6000)
      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed >= 1500 and elapsed < 5500
      Exqlite.query!(blocker, "ROLLBACK")

      Exqlite.query!(blocker, "BEGIN IMMEDIATE")
      task = Task.async(fn -> Transaction.write(@repo, fn -> :written end) end)
      assert Task.yield(task, 100) == nil
      Exqlite.query!(blocker, "ROLLBACK")
      assert {:ok, :written} = Task.await(task, 5000)
    after
      GenServer.stop(blocker)
    end
  end

  @tag capture_log: true
  test "driver timeout cancels a busy wait without an unbounded connection hang", %{opts: opts} do
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    {:ok, blocker} = Exqlite.start_link(database: opts[:database])
    {:ok, contender} = Exqlite.start_link(database: opts[:database], busy_timeout: 2000)

    try do
      Exqlite.query!(blocker, "BEGIN IMMEDIATE")

      task =
        Task.async(fn ->
          try do
            Exqlite.query(contender, "BEGIN IMMEDIATE", [], timeout: 100)
          catch
            :exit, _ -> {:error, :query_timeout}
          end
        end)

      assert {:error, _} = Task.await(task, 1500)
      # The connection can be shut down while the other connection still owns
      # the lock; releasing it first would miss an uninterruptible busy wait.
      started = System.monotonic_time(:millisecond)
      GenServer.stop(contender, :normal, 1500)
      assert System.monotonic_time(:millisecond) - started < 1500
      Exqlite.query!(blocker, "ROLLBACK")
    after
      if Process.alive?(contender), do: GenServer.stop(contender)
      GenServer.stop(blocker)
    end
  end

  test "DDL protects foreign keys, versions, sequence and nullable dedupe uniqueness", %{
    opts: opts
  } do
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    id = Ecto.UUID.generate()

    scope_id = Ecto.UUID.generate()
    assert {:ok, _} = DispatchScopes.create(@repo, %{id: scope_id})

    agent =
      Agent.changeset(%Agent{}, %{
        id: id,
        authority_id: opts[:dataset_id],
        dispatch_scope_id: scope_id,
        definition: %{},
        generation: 0,
        lock_version: 0,
        history_seq: 0
      })

    assert agent.valid?
    assert {:ok, _} = @repo.insert(agent)

    base = %{
      scope_id: id,
      type: "input.accepted",
      schema_version: 1,
      payload: %{"text" => "hello"},
      recorded_at: DateTime.utc_now()
    }

    for seq <- 1..2 do
      assert {:ok, _} =
               @repo.insert(
                 Event.changeset(%Event{}, Map.merge(base, %{id: Ecto.UUID.generate(), seq: seq}))
               )
    end

    cs =
      Event.changeset(
        %Event{},
        Map.merge(base, %{id: Ecto.UUID.generate(), seq: 3, dedupe_key: "consume:1"})
      )

    assert {:ok, _} = @repo.insert(cs)

    assert_raise Ecto.ConstraintError, fn ->
      @repo.insert!(
        Event.changeset(
          %Event{},
          Map.merge(base, %{id: Ecto.UUID.generate(), seq: 4, dedupe_key: "consume:1"})
        )
      )
    end

    assert_raise Exqlite.Error, fn -> sql("UPDATE agent_events SET schema_version = 2") end

    assert_raise Exqlite.Error, fn ->
      sql("UPDATE agents SET head_checkpoint_id = $1", [Ecto.UUID.generate()])
    end

    assert_raise Exqlite.Error, fn -> sql("UPDATE agent_events SET seq = 0") end

    assert_raise Exqlite.Error, fn ->
      sql("DELETE FROM agents WHERE id = $1", [id])
      |> then(fn _ ->
        sql(
          "INSERT INTO checkpoints (id, agent_id, data, continuation, schema_version, digest, safe_to_fork, recorded_at) VALUES ($1, $2, '{}', 'await_input', 1, $3, FALSE, CURRENT_TIMESTAMP)",
          [Ecto.UUID.generate(), id, Codec.hash("{}")]
        )
      end)
    end
  end

  test "Ecto.Multi content and references roll back and survive reopen", %{opts: opts} do
    assert {:ok, _} = Dataset.initialize(@repo, opts)

    attrs = %{
      id: Ecto.UUID.generate(),
      content: <<0, 255, 1>>,
      digest: Codec.hash(<<0, 255, 1>>),
      size: 3,
      media_type: "application/octet-stream",
      recorded_at: DateTime.utc_now()
    }

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:artifact, fn repo, _ -> Artifacts.put(repo, attrs) end)
      |> Ecto.Multi.run(:refs, fn repo, _ ->
        case Artifacts.verify_references(repo, [attrs.id]) do
          :ok -> {:ok, :valid}
          error -> error
        end
      end)

    assert {:error, :abort, :abort, _} =
             Transaction.write(@repo, Ecto.Multi.error(multi, :abort, :abort))

    assert {:error, :artifact_missing} = Artifacts.fetch(@repo, attrs.id)
    assert {:ok, _} = Transaction.write(@repo, multi)
    @repo.stop()
    assert {:ok, _} = Dataset.open(@repo, opts)
    assert {:ok, %{content: <<0, 255, 1>>}} = Artifacts.fetch(@repo, attrs.id)
    assert {:error, :invalid_data} = Artifacts.put(@repo, attrs)

    assert {:ok, {:error, :artifact_missing}} =
             Transaction.write(@repo, fn ->
               Artifacts.verify_references(@repo, [Ecto.UUID.generate()])
             end)

    exact = :binary.copy(<<0>>, 16_777_216)

    assert Artifacts.changeset(%{
             attrs
             | content: exact,
               digest: Codec.hash(exact),
               size: byte_size(exact)
           }).valid?

    refute Artifacts.changeset(%{attrs | digest: String.duplicate("0", 64)}).valid?

    refute Artifacts.changeset(%{
             attrs
             | content: :binary.copy(<<0>>, 16_777_216 + 1)
           }).valid?

    sql("UPDATE artifacts SET content = $1 WHERE id = $2", [<<1>>, attrs.id])
    assert {:error, :invalid_data} = Artifacts.fetch(@repo, attrs.id)
  end

  test "all schema entry points reject unknown fields and unsafe JSON", %{opts: opts} do
    assert {:ok, _} = Dataset.initialize(@repo, opts)

    for schema <- [
          Agent,
          Checkpoint,
          Event,
          Operation,
          Execution,
          ExecutionEvidence,
          Command,
          Artifact,
          JournalAttempt
        ] do
      cs = schema.changeset(struct(schema), %{"unapproved" => "value"})
      refute cs.valid?

      for field <- schema.__schema__(:fields),
          JSON.kind(schema.__schema__(:type, field)) != nil do
        refute schema.changeset(struct(schema), %{field => %{"nested" => self()}}).valid?
        refute schema.changeset(struct(schema), %{field => %{"password" => "not-logged"}}).valid?
      end
    end

    assert :error =
             Ecto.Type.dump(
               Operation.__schema__(:type, :description),
               String.duplicate("a", Codec.limit(:operation))
             )

    assert_raise Ecto.ChangeError, fn ->
      @repo.insert!(%Agent{
        id: Ecto.UUID.generate(),
        authority_id: Ecto.UUID.generate(),
        definition: %{"bad" => self()},
        generation: 0,
        lock_version: 0,
        history_seq: 0
      })
    end

    assert_raise Exqlite.Error, fn ->
      sql("INSERT INTO storage_metadata VALUES (2, 'bad', 'authority', 1, 0)")
    end

    assert_raise Exqlite.Error, fn ->
      sql(
        "INSERT INTO agents (id,authority_id,definition,generation,lock_version,history_seq) VALUES ('x','x','{}',-1,0,0)"
      )
    end
  end
end
