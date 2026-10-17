defmodule Beamlet.Storage.ContractFixture do
  @moduledoc false
  # Adapter-specific setup for the shared storage contract suite. Everything that
  # differs between SQLite and PostgreSQL (files vs. throwaway database, PRAGMA
  # vs. server settings, sqlite_master vs. information_schema) lives here; the
  # contract assertions themselves are shared.
  #
  # SQLite: isolated directory of real files under the system temp dir.
  # PostgreSQL: a throwaway database in the isolated cluster named by
  # BEAMLET_PG_SOCKET_DIR (loopback/Unix socket only, never an existing database).

  alias Beamlet.Storage.{Dataset, PostgresAuthorityRepo, SQLiteAuthorityRepo}
  alias Ecto.Adapters.SQL

  def open(:sqlite) do
    # Unique per VM *and* per wall clock: a leftover directory from an interrupted
    # run must not turn into :dataset_exists on the next run.
    dir =
      Path.join(
        System.tmp_dir!(),
        "beamlet-contract-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    opts = [
      database: Path.join(dir, "authority.db"),
      peer_database: Path.join(dir, "journal.db"),
      dataset_id: Ecto.UUID.generate()
    ]

    {:ok, _pid} = Dataset.initialize(SQLiteAuthorityRepo, opts)
    base(%{backend: :sqlite, repo: SQLiteAuthorityRepo, opts: opts, dir: dir})
  end

  def open(:postgres) do
    socket = System.fetch_env!("BEAMLET_PG_SOCKET_DIR")
    database = "beamlet_contract_#{System.unique_integer([:positive])}"
    admin = [socket_dir: socket, port: pg_port(), username: pg_user(), database: "postgres"]

    with {:ok, conn} <- Postgrex.start_link(admin),
         {:ok, _} <- Postgrex.query(conn, "CREATE DATABASE #{database}", []) do
      GenServer.stop(conn)

      opts = [
        database: database,
        socket_dir: socket,
        port: pg_port(),
        username: pg_user(),
        dataset_id: Ecto.UUID.generate()
      ]

      case Dataset.initialize(PostgresAuthorityRepo, opts) do
        {:ok, _pid} ->
          base(%{backend: :postgres, repo: PostgresAuthorityRepo, opts: opts, database: database})

        error ->
          drop_database(admin, database)
          raise "PostgreSQL contract dataset could not be initialized: #{inspect(error)}"
      end
    end
  end

  defp base(fixture) do
    Map.merge(fixture, %{
      authority_id: fixture.opts[:dataset_id],
      pool_size: if(fixture.backend == :postgres, do: 4, else: 1)
    })
  end

  def close(%{backend: :sqlite, dir: dir}) do
    stop(SQLiteAuthorityRepo)
    File.rm_rf!(dir)
  end

  def close(%{backend: :postgres, database: database}) do
    stop(PostgresAuthorityRepo)

    drop_database(
      [
        socket_dir: System.fetch_env!("BEAMLET_PG_SOCKET_DIR"),
        port: pg_port(),
        username: pg_user(),
        database: "postgres"
      ],
      database
    )
  end

  defp drop_database(admin, database) do
    case Postgrex.start_link(admin) do
      {:ok, conn} ->
        Postgrex.query(conn, "DROP DATABASE IF EXISTS #{database} WITH (FORCE)", [])
        GenServer.stop(conn)

      _ ->
        :ok
    end
  end

  defp stop(repo) do
    repo.stop()
  catch
    _, _ -> :ok
  end

  def sql(fixture, statement, params \\ []) do
    SQL.query!(fixture.repo, statement, params, log: false)
  end

  def tables(%{backend: :sqlite, repo: repo}) do
    "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
    |> then(&SQL.query!(repo, &1, [], log: false))
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  def tables(%{backend: :postgres, repo: repo}) do
    "SELECT table_name FROM information_schema.tables WHERE table_schema = current_schema() ORDER BY table_name"
    |> then(&SQL.query!(repo, &1, [], log: false))
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  # Reads the durability settings of every physical connection in the pool.
  # SQLite has pool_size 1, so its single connection is every connection.
  def settings(%{backend: :sqlite, repo: repo}) do
    values =
      Map.new(
        ["journal_mode", "synchronous", "foreign_keys", "busy_timeout"],
        fn pragma ->
          {pragma, SQL.query!(repo, "PRAGMA " <> pragma, [], log: false).rows}
        end
      )

    %{
      connections: 1,
      per_connection: [
        Map.new(values, fn {pragma, [[value]]} -> {pragma, value} end)
      ],
      required: %{
        # Exqlite 0.42 installs an interruptible NIF busy handler, so SQLite's
        # PRAGMA stays 0; the configured 2000 ms budget lives in the handler.
        "journal_mode" => "wal",
        "synchronous" => 2,
        "foreign_keys" => 1,
        "busy_timeout" => 0
      }
    }
  end

  def settings(%{backend: :postgres, repo: repo}) do
    # Hold pool_size checkouts at once so every physical connection is sampled.
    tasks =
      for _ <- 1..4 do
        Task.async(fn ->
          repo.checkout(
            fn ->
              rows =
                SQL.query!(
                  repo,
                  "SELECT pg_backend_pid(), current_setting('synchronous_commit'), current_setting('fsync')",
                  [],
                  log: false
                ).rows

              Process.sleep(200)
              rows
            end,
            timeout: 10_000
          )
        end)
      end

    rows = Enum.map(tasks, &Task.await(&1, 20_000))
    pids = MapSet.new(rows, fn [[pid, _commit, _fsync]] -> pid end)

    %{
      connections: MapSet.size(pids),
      per_connection:
        Enum.map(rows, fn [[_pid, commit, fsync]] ->
          %{"synchronous_commit" => commit, "fsync" => fsync}
        end),
      required: %{"synchronous_commit" => "on", "fsync" => "on"}
    }
  end

  # Negative control: a connection downgraded away from synchronous durability must
  # be rejected by the same `after_connect` guard used for pooled connections.
  def reject_downgraded(%{backend: :postgres}) do
    {:ok, conn} =
      Postgrex.start_link(
        socket_dir: System.fetch_env!("BEAMLET_PG_SOCKET_DIR"),
        port: pg_port(),
        username: pg_user(),
        database: "postgres"
      )

    {:ok, _} = Postgrex.query(conn, "SET synchronous_commit = off", [])

    result =
      try do
        Beamlet.Storage.Connections.verify_postgres(conn)
      rescue
        error -> {:raised, Exception.message(error)}
      catch
        :exit, reason -> {:raised, inspect(reason)}
      end

    GenServer.stop(conn)
    result
  end

  # A driver-level failure inside a write transaction: the outcome is unknown, so
  # the caller must not treat it as "not executed".
  #
  # PostgreSQL: a real statement timeout on a real pooled transaction.
  # SQLite: the same failure class through the Transaction boundary. Exqlite's
  # interruptible handler bounds contention, not an arbitrary long statement, so a
  # live SQLite statement timeout cannot be produced cheaply; the mapping is
  # exercised with the real driver exception instead.
  def driver_failure(%{backend: :postgres, repo: repo}) do
    Beamlet.Storage.Transaction.write(repo, fn ->
      # Kill our own backend inside the transaction: the commit outcome is unknown.
      SQL.query!(repo, "SELECT pg_terminate_backend(pg_backend_pid())", [], log: false)
      SQL.query!(repo, "INSERT INTO commands (id) VALUES ('never')", [], log: false)
    end)
  end

  def driver_failure(%{backend: :sqlite, repo: repo}) do
    defmodule DriverFailureStub do
      def __adapter__, do: Ecto.Adapters.SQLite3
      def transaction(_fun, _opts), do: raise(DBConnection.ConnectionError, "connection lost")
    end

    # Exercise the facade boundary every caller uses, not just Transaction.write/2.
    if repo, do: Beamlet.Storage.Records.transact(DriverFailureStub, fn -> :ok end)
  end

  # Adapter-specific private connection used to mutate the installation metadata
  # while the Repo is stopped (reopen-refusal scenarios).
  def raw_connection(%{backend: :sqlite, database: database}) do
    {:ok, conn} = Exqlite.Sqlite3.open(database)
    {:ok, {:sqlite, conn}}
  end

  def raw_connection(%{backend: :postgres, database: database}) do
    {:ok, conn} =
      Postgrex.start_link(
        socket_dir: System.fetch_env!("BEAMLET_PG_SOCKET_DIR"),
        port: pg_port(),
        username: pg_user(),
        database: database
      )

    {:ok, {:postgres, conn}}
  end

  def run_raw({:sqlite, conn}, statement), do: :ok = Exqlite.Sqlite3.execute(conn, statement)

  def run_raw({:postgres, conn}, statement) do
    {:ok, _} = Postgrex.query(conn, statement, [])
    :ok
  end

  def close_raw({:sqlite, conn}), do: Exqlite.Sqlite3.close(conn)
  def close_raw({:postgres, conn}), do: GenServer.stop(conn)

  defp pg_user, do: System.get_env("BEAMLET_PG_USER", "beamlet")
  defp pg_port, do: String.to_integer(System.get_env("BEAMLET_PG_PORT", "5432"))
end
