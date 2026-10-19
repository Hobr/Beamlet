defmodule Beamlet.Storage.Connections do
  @moduledoc false
  # 每条物理连接（含重连）都验证持久化设置，不能以 Repo 已注册替代验证。SQLite 保留 Exqlite 可中断 busy handler，PRAGMA busy_timeout=0 是预期值。
  @spec sqlite(keyword()) :: keyword()
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

  @spec postgres(keyword()) :: keyword()
  def postgres(config) do
    Keyword.merge(config,
      pool_size: 4,
      timeout: 5000,
      queue_target: 1000,
      after_connect: &__MODULE__.verify_postgres/1
    )
  end

  # DBConnection invokes this for every physical connection, including reconnects.
  @spec verify_sqlite(DBConnection.conn()) :: [:ok]
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

  @spec verify_postgres(DBConnection.conn()) :: [:ok]
  def verify_postgres(connection) do
    for setting <- ["fsync", "synchronous_commit"] do
      case Postgrex.query(connection, "SHOW " <> setting, []) do
        {:ok, %{rows: [["on"]]}} -> :ok
        _ -> raise "unsupported storage connection settings"
      end
    end
  end
end
