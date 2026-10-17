defmodule Beamlet.Storage.Connections do
  @moduledoc false
  def sqlite(config) do
    Keyword.merge(config,
      pool_size: 1,
      pool: DBConnection.ConnectionPool,
      url: nil,
      timeout: 5000,
      busy_timeout: 2000,
      journal_mode: :wal,
      synchronous: :full,
      foreign_keys: :on,
      default_transaction_mode: :deferred,
      queue_target: 1000,
      after_connect: &__MODULE__.verify_sqlite/1
    )
  end

  # DBConnection invokes this for every physical connection, including reconnects.
  def verify_sqlite(connection) do
    for {pragma, expected} <- [
          {"journal_mode", "wal"},
          {"synchronous", 2},
          {"foreign_keys", 1},
          # Exqlite 0.42 uses its interruptible NIF busy handler, not SQLite's
          # PRAGMA handler. Do not overwrite it with PRAGMA busy_timeout=... .
          {"busy_timeout", 0}
        ] do
      case Exqlite.query(connection, "PRAGMA " <> pragma, []) do
        {:ok, %{rows: [[^expected]]}} -> :ok
        _ -> raise "unsupported storage connection settings"
      end
    end
  end

  def verify_postgres(connection) do
    for setting <- ["fsync", "synchronous_commit"] do
      case Postgrex.query(connection, "SHOW " <> setting, []) do
        {:ok, %{rows: [["on"]]}} -> :ok
        _ -> raise "unsupported storage connection settings"
      end
    end
  end
end
