defmodule Beamlet.Storage.Migrations do
  @moduledoc "Explicit descriptor-driven installation; never invoked by open/verify."
  alias Beamlet.Storage.{Installation, Transaction}
  alias Ecto.Adapters.SQL

  @spec install_metadata(module(), String.t(), Installation.t()) ::
          {:ok, :ok} | {:error, term()} | {:error, term(), term(), map()}
  def install_metadata(repo, dataset_id, descriptor) do
    Transaction.write(repo, fn ->
      _ =
        SQL.query!(
          repo,
          "CREATE TABLE storage_metadata (id INTEGER PRIMARY KEY CHECK (id = 1), dataset_id VARCHAR(36) NOT NULL CHECK (LENGTH(dataset_id) = 36), profile VARCHAR(128) NOT NULL, format_version INTEGER NOT NULL CHECK (format_version > 0), restored_backup BOOLEAN NOT NULL, manifest TEXT NOT NULL, installed BOOLEAN NOT NULL)",
          [],
          log: false
        )

      _ =
        SQL.query!(
          repo,
          "INSERT INTO storage_metadata VALUES (1, $1, $2, 3, FALSE, $3, FALSE)",
          [dataset_id, descriptor.profile, Installation.manifest(descriptor)],
          log: false
        )

      :ok
    end)
  end

  @spec install(module(), Installation.t()) :: :ok
  def install(repo, descriptor) do
    migrations = Enum.map(descriptor.migrations, &{&1.id, &1.module})
    _ = Ecto.Migrator.run(repo, migrations, :up, all: true, log: false, log_migrations_sql: false)

    _ =
      SQL.query!(repo, "UPDATE storage_metadata SET installed = TRUE WHERE id = 1", [],
        log: false
      )

    :ok
  end
end

defmodule Beamlet.Storage.Migrations.FoundationV1 do
  @moduledoc "Shared content only. Migration ID 1 in every format3 profile."
  use Ecto.Migration

  @spec up() :: Ecto.Migration.Index.t()
  def up do
    execute "CREATE TABLE artifacts (id VARCHAR(255) PRIMARY KEY NOT NULL, digest VARCHAR(255) NOT NULL, media_type VARCHAR(255) NOT NULL, size BIGINT NOT NULL CHECK (size >= 0), content #{if repo().__adapter__() == Ecto.Adapters.Postgres, do: "BYTEA", else: "BLOB"} NOT NULL, recorded_at TIMESTAMP(6) NOT NULL)"
    create unique_index(:artifacts, [:digest])
  end

  @spec down() :: no_return()
  def down, do: raise("durable migrations are forward-only")
end
