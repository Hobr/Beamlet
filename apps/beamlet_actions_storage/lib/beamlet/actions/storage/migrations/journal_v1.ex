defmodule Beamlet.Actions.Storage.Migrations.JournalV1 do
  @moduledoc false
  # 已安装的 format3 前向迁移，描述符绑定模块身份；打开数据集不会运行或修复迁移。
  # flush returns the adapter-specific DDL results; the migration runner ignores them.
  @spec up() :: [term()]
  @spec down() :: no_return()
  use Ecto.Migration

  def up do
    execute(
      "CREATE TABLE journal_attempts (id VARCHAR(255) PRIMARY KEY NOT NULL, authority_id VARCHAR(255) NOT NULL, operation_id VARCHAR(255) NOT NULL, attempt_id VARCHAR(255) NOT NULL, description_digest VARCHAR(255) NOT NULL, executor_id VARCHAR(255) NOT NULL, executor_boot_id VARCHAR(255) NOT NULL, state VARCHAR(255) NOT NULL CHECK (state IN ('start_intent', 'terminal', 'unknown_after_restart')), stop_reason VARCHAR(255) CHECK (stop_reason IN ('deadline', 'cancelled')), termination TEXT, terminal_result TEXT, terminal_artifacts TEXT, receipt_id VARCHAR(255), receipt_digest VARCHAR(255), receipt TEXT, acknowledged BOOLEAN NOT NULL, schema_version BIGINT NOT NULL CHECK (schema_version = 1), lock_version BIGINT NOT NULL CHECK (lock_version >= 0), recorded_at TIMESTAMP(6) NOT NULL)"
    )

    _ = create(unique_index(:journal_attempts, [:authority_id, :attempt_id]))
    _ = create(unique_index(:journal_attempts, [:receipt_id]))
    flush()
  end

  def down, do: raise("durable migrations are forward-only; restore a verified backup")
end
