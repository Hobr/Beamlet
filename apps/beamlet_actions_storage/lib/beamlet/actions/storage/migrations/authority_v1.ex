defmodule Beamlet.Actions.Storage.Migrations.AuthorityV1 do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute(
      "CREATE TABLE dispatch_scopes (id VARCHAR(255) PRIMARY KEY NOT NULL, epoch BIGINT NOT NULL CHECK (epoch >= 0))"
    )

    execute(
      "CREATE TABLE operations (id VARCHAR(255) PRIMARY KEY NOT NULL, dispatch_scope_id VARCHAR(255) REFERENCES dispatch_scopes(id), dispatch_epoch BIGINT CHECK (dispatch_epoch >= 0), description TEXT NOT NULL, description_digest VARCHAR(255) NOT NULL, accepted_result TEXT, accepted_evidence_id VARCHAR(255) #{if repo().__adapter__() == Ecto.Adapters.SQLite3, do: "REFERENCES execution_evidence(id)", else: ""}, lock_version BIGINT NOT NULL CHECK (lock_version >= 0), history_seq BIGINT NOT NULL CHECK (history_seq >= 0), schema_version BIGINT NOT NULL CHECK (schema_version = 1), recorded_at TIMESTAMP(6) NOT NULL)"
    )

    execute(
      "CREATE TABLE executions (attempt_id VARCHAR(255) PRIMARY KEY NOT NULL, operation_id VARCHAR(255) NOT NULL REFERENCES operations(id), executor_id VARCHAR(255) NOT NULL, executor_boot_id VARCHAR(255) NOT NULL, description_digest VARCHAR(255) NOT NULL, dispatch_state VARCHAR(255) NOT NULL CHECK (dispatch_state IN ('prepared', 'send_claimed')), observation TEXT, budget TEXT NOT NULL, lock_version BIGINT NOT NULL CHECK (lock_version >= 0), recorded_at TIMESTAMP(6) NOT NULL)"
    )

    create(unique_index(:executions, [:operation_id]))

    execute(
      "CREATE TABLE execution_evidence (id VARCHAR(255) PRIMARY KEY NOT NULL, operation_id VARCHAR(255) NOT NULL REFERENCES operations(id), attempt_id VARCHAR(255) NOT NULL REFERENCES executions(attempt_id), executor_id VARCHAR(255) NOT NULL, evidence_id VARCHAR(255) NOT NULL, digest VARCHAR(255) NOT NULL, content TEXT NOT NULL, resolution TEXT, recorded_at TIMESTAMP(6) NOT NULL)"
    )

    create(unique_index(:execution_evidence, [:executor_id, :evidence_id]))

    execute(
      "CREATE TABLE operation_events (id VARCHAR(255) PRIMARY KEY NOT NULL, operation_id VARCHAR(255) NOT NULL REFERENCES operations(id), seq BIGINT NOT NULL CHECK (seq > 0), type VARCHAR(255) NOT NULL, schema_version BIGINT NOT NULL CHECK (schema_version = 1), payload TEXT NOT NULL, recorded_at TIMESTAMP(6) NOT NULL)"
    )

    create(unique_index(:operation_events, [:operation_id, :seq]))
    flush()

    if repo().__adapter__() == Ecto.Adapters.Postgres do
      execute(
        "ALTER TABLE operations ADD CONSTRAINT operations_accepted_evidence_id_fkey FOREIGN KEY (accepted_evidence_id) REFERENCES execution_evidence(id)"
      )
    end
  end

  def down, do: raise("forward only")
end
