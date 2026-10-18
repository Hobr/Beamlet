defmodule Beamlet.Storage.Migrations do
  @moduledoc false
  alias Beamlet.Storage.Transaction
  alias Ecto.Adapters.SQL

  # The metadata DDL and identity are one atomic transaction, before business
  # migrations. An interrupted installation remains fail-closed, never a reopen.
  def install_metadata(repo, dataset_id, role) do
    Transaction.write(repo, fn ->
      SQL.query!(
        repo,
        "CREATE TABLE storage_metadata (id INTEGER PRIMARY KEY CHECK (id = 1), dataset_id VARCHAR(36) NOT NULL CHECK (LENGTH(dataset_id) = 36), role VARCHAR(16) NOT NULL CHECK (role IN ('authority', 'journal')), format_version INTEGER NOT NULL CHECK (format_version > 0), restored_backup BOOLEAN NOT NULL CHECK (restored_backup IN (FALSE, TRUE)))",
        [],
        log: false
      )

      SQL.query!(
        repo,
        "INSERT INTO storage_metadata (id, dataset_id, role, format_version, restored_backup) VALUES (1, $1, $2, $3, FALSE)",
        [dataset_id, role, if(role == "authority", do: 2, else: 1)],
        log: false
      )

      :ok
    end)
  end
end
