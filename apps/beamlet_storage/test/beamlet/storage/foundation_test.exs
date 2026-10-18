defmodule Beamlet.Storage.FoundationTest do
  use ExUnit.Case, async: false

  alias Beamlet.Storage.{
    Admission,
    Artifacts,
    Codec,
    Dataset,
    Host,
    Installation,
    SQLiteRepo,
    Transaction
  }

  alias Ecto.Adapters.SQL
  @repo SQLiteRepo

  defmodule ExtraMigration do
    use Ecto.Migration
    def up, do: execute("CREATE TABLE example_items (id INTEGER PRIMARY KEY)")
    def down, do: raise("forward only")
  end

  defmodule FailingMigration do
    use Ecto.Migration
    def up, do: raise("intentional test installation failure")
    def down, do: raise("forward only")
  end

  defp descriptor do
    %{
      profile: "foundation-test",
      format_version: 3,
      components: [Installation.foundation_component()],
      migrations: [Installation.foundation_migration()]
    }
  end

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "foundation-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    opts = [
      database: Path.join(dir, "data.db"),
      peer_database: Path.join(dir, "peer.db"),
      dataset_id: Ecto.UUID.generate(),
      descriptor: descriptor()
    ]

    on_exit(fn ->
      try do
        if Process.whereis(@repo), do: @repo.stop()
      catch
        :exit, _ -> :ok
      end

      File.rm_rf!(dir)
    end)

    %{opts: opts}
  end

  defp sql(s, args \\ []), do: SQL.query!(@repo, s, args, log: false)

  test "descriptor exact fields, ordering, complete component ownership and identities", %{
    opts: opts
  } do
    d = descriptor()
    assert :ok = Installation.validate(d)

    assert Installation.manifest(d) ==
             ~s({"components":[{"name":"foundation","version":1}],"migrations":[{"component":"foundation","id":1,"module":"Elixir.Beamlet.Storage.Migrations.FoundationV1"}]})

    assert Installation.foundation_component() == %{name: "foundation", version: 1}

    assert Installation.foundation_migration() == %{
             id: 1,
             component: "foundation",
             module: Beamlet.Storage.Migrations.FoundationV1
           }

    for bad <- [
          nil,
          Map.put(d, :extra, true),
          %{d | format_version: 2},
          %{d | components: []},
          %{d | migrations: []},
          %{d | migrations: d.migrations ++ d.migrations},
          %{d | components: d.components ++ [%{name: "extra", version: 1}]},
          %{
            d
            | migrations: d.migrations ++ [%{id: 2, component: "unknown", module: ExtraMigration}]
          }
        ] do
      assert {:error, :invalid_data} =
               Dataset.initialize(@repo, Keyword.put(opts, :descriptor, bad))

      refute File.exists?(opts[:database])
    end

    assert {:error, :invalid_data} = Dataset.initialize(@repo, Keyword.delete(opts, :descriptor))
  end

  test "new install, exact neutral tables, open verify and real settings", %{opts: opts} do
    assert {:error, :dataset_missing} = Dataset.open(@repo, opts)
    refute File.exists?(opts[:database])
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    assert :ok = Dataset.verify(@repo, opts)

    assert {:error, :conflict} =
             Dataset.initialize(@repo, Keyword.put(opts, :database, opts[:database] <> ".other"))

    refute File.exists?(opts[:database] <> ".other")
    assert :admitted = Admission.probe(@repo, opts)

    assert sql("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").rows ==
             [["artifacts"], ["schema_migrations"], ["storage_metadata"]]

    for {pragma, value} <- [
          {"journal_mode", "wal"},
          {"synchronous", 2},
          {"foreign_keys", 1},
          {"busy_timeout", 0}
        ] do
      assert [[value]] == sql("PRAGMA " <> pragma).rows
    end

    @repo.stop()
    assert {:error, :storage_unavailable} = Dataset.verify(@repo, opts)
    assert {:error, :dataset_exists} = Dataset.initialize(@repo, opts)
    assert {:ok, _} = Dataset.open(@repo, opts)
  end

  test "old authority2 and journal1 refused with identical schema, bytes and business content", %{
    opts: opts
  } do
    for version <- [2, 1] do
      {:ok, conn} = Exqlite.Sqlite3.open(opts[:database])

      :ok =
        Exqlite.Sqlite3.execute(
          conn,
          "CREATE TABLE storage_metadata (id INTEGER, format_version INTEGER); INSERT INTO storage_metadata VALUES (1, #{version}); CREATE TABLE old_business (payload TEXT); INSERT INTO old_business VALUES ('retained')"
        )

      :ok = Exqlite.Sqlite3.close(conn)
      before = File.read!(opts[:database])
      assert {:error, :schema_unsupported} = Dataset.open(@repo, opts)
      refute Process.whereis(@repo)
      assert before == File.read!(opts[:database])
      refute File.exists?(opts[:database] <> "-wal")
      File.rm!(opts[:database])
    end
  end

  test "identity/profile/component/migration/backup/incomplete mismatches never repair", %{
    opts: opts
  } do
    assert {:ok, _} = Dataset.initialize(@repo, opts)

    assert {:error, :dataset_mismatch} =
             Dataset.verify(@repo, Keyword.put(opts, :dataset_id, Ecto.UUID.generate()))

    d = descriptor()

    for changed <- [
          %{d | profile: "other"},
          %{d | components: [%{name: "foundation", version: 2}]}
        ] do
      assert {:error, _} = Dataset.verify(@repo, Keyword.put(opts, :descriptor, changed))
    end

    mismatched = %{
      d
      | components: d.components ++ [%{name: "extra", version: 1}],
        migrations: d.migrations ++ [%{id: 100, component: "extra", module: ExtraMigration}]
    }

    assert {:error, :schema_unsupported} =
             Dataset.verify(@repo, Keyword.put(opts, :descriptor, mismatched))

    original = Installation.manifest(d)

    for {update, expected} <- [
          {"manifest = '{}'", :schema_unsupported},
          {"restored_backup = TRUE", :restored_backup},
          {"installed = FALSE", :schema_unsupported},
          {"format_version = 4", :schema_unsupported}
        ] do
      sql("UPDATE storage_metadata SET " <> update)
      sql("PRAGMA wal_checkpoint(TRUNCATE)")
      @repo.stop()
      before = File.read!(opts[:database])
      assert {:error, ^expected} = Dataset.open(@repo, opts)
      assert File.read!(opts[:database]) == before
      {:ok, _} = @repo.start_link(opts)

      sql(
        "UPDATE storage_metadata SET manifest = $1, restored_backup = FALSE, installed = TRUE, format_version = 3",
        [original]
      )
    end

    sql("INSERT INTO schema_migrations VALUES (99, CURRENT_TIMESTAMP)")
    assert {:error, :schema_unsupported} = Dataset.verify(@repo, opts)
  end

  test "trusted component composition is explicit; open never adds a migration", %{opts: opts} do
    d = descriptor()

    expanded = %{
      d
      | components: d.components ++ [%{name: "example", version: 1}],
        migrations: d.migrations ++ [%{id: 100, component: "example", module: ExtraMigration}]
    }

    assert :ok = Installation.validate(expanded)
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    @repo.stop()

    assert {:error, :schema_unsupported} =
             Dataset.open(@repo, Keyword.put(opts, :descriptor, expanded))

    assert {:ok, _} = Dataset.open(@repo, opts)
    assert [[0]] == sql("SELECT COUNT(*) FROM sqlite_master WHERE name='example_items'").rows
    @repo.stop()
    File.rm!(opts[:database])
    expanded_opts = Keyword.put(opts, :descriptor, expanded)
    assert {:ok, _} = Dataset.initialize(@repo, expanded_opts)
    assert :ok = Dataset.verify(@repo, expanded_opts)

    wrong_identity = %{
      expanded
      | migrations: [
          Installation.foundation_migration(),
          %{id: 100, component: "example", module: FailingMigration}
        ]
    }

    assert :ok = Installation.validate(wrong_identity)

    assert {:error, :schema_unsupported} =
             Dataset.verify(@repo, Keyword.put(opts, :descriptor, wrong_identity))

    assert [[1]] == sql("SELECT COUNT(*) FROM sqlite_master WHERE name='example_items'").rows
  end

  @tag capture_log: true
  test "failed installation stays incomplete and raw Repo startup never migrates", %{opts: opts} do
    d = descriptor()

    broken = %{
      d
      | components: d.components ++ [%{name: "broken", version: 1}],
        migrations: d.migrations ++ [%{id: 100, component: "broken", module: FailingMigration}]
    }

    broken_opts = Keyword.put(opts, :descriptor, broken)
    assert {:error, :storage_unavailable} = Dataset.initialize(@repo, broken_opts)
    refute Process.whereis(@repo)
    assert {:error, :schema_unsupported} = Dataset.open(@repo, broken_opts)
    {:ok, _} = @repo.start_link(opts)
    assert [[0]] == sql("SELECT installed FROM storage_metadata").rows
    assert [[1]] == sql("SELECT version FROM schema_migrations").rows
    @repo.stop()
    File.rm!(opts[:database])
    {:ok, _} = @repo.start_link(opts)
    assert [[0]] == sql("SELECT COUNT(*) FROM sqlite_master WHERE name='storage_metadata'").rows
  end

  test "peer isolation rejects aliases and symlinks before writes", %{opts: opts} do
    assert {:error, :path_alias} =
             Dataset.initialize(@repo, Keyword.put(opts, :peer_database, opts[:database]))

    refute File.exists?(opts[:database])
    File.write!(opts[:database], "")
    File.ln!(opts[:database], opts[:peer_database])
    assert {:error, :path_alias} = Dataset.open(@repo, opts)
    File.rm!(opts[:peer_database])
    File.ln_s!(opts[:database], opts[:peer_database])
    assert {:error, :invalid_data} = Dataset.open(@repo, opts)
  end

  test "participant requires existing transaction; rollback shared content and safe errors", %{
    opts: opts
  } do
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    assert {:error, :transaction_required} = Transaction.participate(@repo, fn -> :never end)

    attrs = %{
      id: Ecto.UUID.generate(),
      content: <<0, 255>>,
      digest: Codec.hash(<<0, 255>>),
      size: 2,
      media_type: "application/octet-stream",
      recorded_at: DateTime.utc_now()
    }

    assert {:error, :abort} =
             Transaction.write(@repo, fn ->
               assert {:ok, _} =
                        Transaction.participate(@repo, fn -> Artifacts.put(@repo, attrs) end)

               @repo.rollback(:abort)
             end)

    assert {:error, :artifact_missing} = Artifacts.fetch(@repo, attrs.id)
    assert {:ok, {:ok, _}} = Transaction.write(@repo, fn -> Artifacts.put(@repo, attrs) end)
    @repo.stop()
    assert {:ok, _} = Dataset.open(@repo, opts)
    assert {:ok, %{content: <<0, 255>>}} = Artifacts.fetch(@repo, attrs.id)

    assert {:error, :invalid_data} =
             Transaction.write(@repo, fn -> sql("UPDATE artifacts SET size = -1") end)
  end

  test "deferred reads and immediate writes plus busy handler unknown outcome", %{opts: opts} do
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    {:ok, conn} = Exqlite.start_link(database: opts[:database], busy_timeout: 100)

    try do
      assert {:ok, :ok} =
               @repo.transaction(fn ->
                 sql("SELECT COUNT(*) FROM artifacts")
                 assert {:ok, _} = Exqlite.query(conn, "BEGIN IMMEDIATE")
                 Exqlite.query!(conn, "ROLLBACK")
                 :ok
               end)

      assert {:ok, :locked} =
               Transaction.write(@repo, fn ->
                 assert {:error, _} = Exqlite.query(conn, "BEGIN IMMEDIATE")
                 :locked
               end)

      Exqlite.query!(conn, "BEGIN IMMEDIATE")
      task = Task.async(fn -> Transaction.write(@repo, fn -> :written end) end)
      assert {:error, :storage_outcome_unknown} = Task.await(task, 6000)
      Exqlite.query!(conn, "ROLLBACK")
      assert {:ok, :written} = Transaction.write(@repo, fn -> :written end)
    after
      GenServer.stop(conn)
    end
  end

  test "host owns generic resources, never initializes, fresh status; admission failure gate", %{
    opts: opts
  } do
    spec = %{key: :sample, repo: @repo, options: opts}
    {:ok, host} = Host.start_link(name: :foundation_host, datasets: [spec])
    assert %{sample: {:error, :dataset_missing}} = Host.status(host)
    refute File.exists?(opts[:database])
    GenServer.stop(host)
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    @repo.stop()
    {:ok, host} = Host.start_link(name: :foundation_host, datasets: [spec])
    assert {:ok, %{sample: @repo}} = Host.handles(host)
    assert %{sample: :admitted} = Host.status(host)
    {:ok, admission} = Admission.start_link([name: :foundation_admission, repo: @repo] ++ opts)
    assert :admitted = Admission.status(:foundation_admission)
    Admission.failure(:storage_outcome_unknown, :foundation_admission)
    assert {:error, :durable_not_admitted} = Admission.consult(:foundation_admission)
    assert :admitted = Admission.status(:foundation_admission)
    sql("UPDATE storage_metadata SET restored_backup = TRUE")
    assert %{sample: {:error, :restored_backup}} = Host.status(host)
    GenServer.stop(admission)
    GenServer.stop(host)
    refute Process.whereis(@repo)
  end
end
