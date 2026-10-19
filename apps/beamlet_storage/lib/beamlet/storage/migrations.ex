defmodule Beamlet.Storage.Migrations do
  @moduledoc "由可信描述符驱动的显式初始化流程；open/verify 不调用安装。

Explicit descriptor-driven installation; never invoked by open/verify."
  alias Beamlet.Storage.{Installation, Transaction}
  alias Ecto.Adapters.SQL

  @doc "初始化专用：在事务中创建单行元数据并记录 installed=false 和精确清单。由 Dataset 在确认空目标后调用，不是已有库升级入口。"
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

  @doc "初始化专用：运行描述符完整迁移列表，全部成功后标记 installed=true。中途异常保留不完整状态供 open 拒绝，不自动清理或修复。"
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
  @moduledoc "仅创建共享内容表，作为每个 format3 profile 的迁移 ID1；只支持向前安装。

Shared content only. Migration ID 1 in every format3 profile."
  use Ecto.Migration

  @doc "创建共享制品表和摘要唯一索引；不安装任何领域表。"
  @spec up() :: Ecto.Migration.Index.t()
  def up do
    execute "CREATE TABLE artifacts (id VARCHAR(255) PRIMARY KEY NOT NULL, digest VARCHAR(255) NOT NULL, media_type VARCHAR(255) NOT NULL, size BIGINT NOT NULL CHECK (size >= 0), content #{if repo().__adapter__() == Ecto.Adapters.Postgres, do: "BYTEA", else: "BLOB"} NOT NULL, recorded_at TIMESTAMP(6) NOT NULL)"
    create unique_index(:artifacts, [:digest])
  end

  @doc "迁移仅向前，回退调用抛出异常；应保留旧数据集而非执行逆迁移。"
  @spec down() :: no_return()
  def down, do: raise("durable migrations are forward-only")
end
