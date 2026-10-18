defmodule Beamlet.Storage.FoundationPostgresTest do
  use ExUnit.Case, async: false
  @moduletag :postgres_db
  alias Beamlet.Storage.{Admission, Dataset, Installation, PostgresRepo, Transaction}
  alias Ecto.Adapters.SQL
  @repo PostgresRepo

  setup do
    database = "foundation_#{System.unique_integer([:positive])}"

    admin = [
      socket_dir: System.fetch_env!("BEAMLET_PG_SOCKET_DIR"),
      port: String.to_integer(System.get_env("BEAMLET_PG_PORT", "5432")),
      username: System.get_env("BEAMLET_PG_USER", System.get_env("USER")),
      database: "postgres"
    ]

    {:ok, conn} = Postgrex.start_link(admin)
    Postgrex.query!(conn, "CREATE DATABASE " <> database, [])
    GenServer.stop(conn)

    d = %{
      profile: "foundation-test",
      format_version: 3,
      components: [Installation.foundation_component()],
      migrations: [Installation.foundation_migration()]
    }

    opts =
      Keyword.merge(admin, database: database, dataset_id: Ecto.UUID.generate(), descriptor: d)

    on_exit(fn ->
      try do
        if Process.whereis(@repo), do: @repo.stop()
      catch
        :exit, _ -> :ok
      end

      {:ok, conn} = Postgrex.start_link(admin)
      Postgrex.query!(conn, "DROP DATABASE " <> database <> " WITH (FORCE)", [])
      GenServer.stop(conn)
    end)

    %{opts: opts}
  end

  defp sql(s), do: SQL.query!(@repo, s, [], log: false)

  test "explicit install/open, exact manifest, rollback admission and durability", %{opts: opts} do
    assert {:error, :dataset_missing} = Dataset.open(@repo, opts)
    assert {:ok, _} = Dataset.initialize(@repo, opts)
    assert :ok = Dataset.verify(@repo, opts)
    assert :admitted = Admission.probe(@repo, opts)

    for setting <- ["fsync", "synchronous_commit"],
        do: assert([["on"]] == sql("SHOW " <> setting).rows)

    assert [["artifacts"], ["schema_migrations"], ["storage_metadata"]] ==
             sql(
               "SELECT table_name FROM information_schema.tables WHERE table_schema = current_schema() ORDER BY table_name"
             ).rows

    assert {:error, :abort} =
             Transaction.write(@repo, fn ->
               :ok =
                 Transaction.participate(@repo, fn ->
                   sql("UPDATE storage_metadata SET restored_backup = TRUE")
                   :ok
                 end)

               @repo.rollback(:abort)
             end)

    assert :ok = Dataset.verify(@repo, opts)
    @repo.stop()
    assert {:error, :dataset_exists} = Dataset.initialize(@repo, opts)
    assert {:ok, _} = Dataset.open(@repo, opts)

    assert {:error, :dataset_mismatch} =
             Dataset.verify(@repo, Keyword.put(opts, :dataset_id, Ecto.UUID.generate()))

    sql("UPDATE storage_metadata SET manifest = '{}'")
    assert {:error, :schema_unsupported} = Dataset.verify(@repo, opts)
    sql("UPDATE storage_metadata SET restored_backup = TRUE")
    assert {:error, :restored_backup} = Dataset.verify(@repo, opts)
  end

  test "old format2 refusal makes no schema or business writes", %{opts: opts} do
    {:ok, _} = @repo.start_link(opts)
    sql("CREATE TABLE storage_metadata (id INTEGER, format_version INTEGER)")
    sql("INSERT INTO storage_metadata VALUES (1, 2)")
    sql("CREATE TABLE old_business (payload TEXT)")
    sql("INSERT INTO old_business VALUES ('retained')")
    @repo.stop()
    assert {:error, :schema_unsupported} = Dataset.open(@repo, opts)
    {:ok, _} = @repo.start_link(opts)
    assert [["retained"]] == sql("SELECT payload FROM old_business").rows

    assert [["old_business"], ["storage_metadata"]] ==
             sql(
               "SELECT table_name FROM information_schema.tables WHERE table_schema = current_schema() ORDER BY table_name"
             ).rows
  end
end
