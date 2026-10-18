defmodule Beamlet.Storage.Migrations.AuthorityV2 do
  use Ecto.Migration

  def up do
    execute "CREATE TABLE agents (id VARCHAR(255) PRIMARY KEY NOT NULL, authority_id VARCHAR(255) NOT NULL, alias VARCHAR(255), definition TEXT NOT NULL, head_checkpoint_id VARCHAR(255) #{if repo().__adapter__() == Ecto.Adapters.SQLite3, do: "REFERENCES checkpoints(id)", else: ""}, generation BIGINT NOT NULL CHECK (generation >= 0), lock_version BIGINT NOT NULL CHECK (lock_version >= 0), history_seq BIGINT NOT NULL CHECK (history_seq >= 0), forked_from_agent_id VARCHAR(255), forked_from_checkpoint_id VARCHAR(255))"

    create unique_index(:agents, [:authority_id, :alias])

    execute "CREATE TABLE checkpoints (id VARCHAR(255) PRIMARY KEY NOT NULL, agent_id VARCHAR(255) NOT NULL REFERENCES agents(id), turn_id VARCHAR(255), through_seq BIGINT NOT NULL CHECK (through_seq >= 0), reducer_version BIGINT NOT NULL CHECK (reducer_version > 0), data TEXT NOT NULL, continuation VARCHAR(255) NOT NULL CHECK (continuation IN ('await_input', 'model_prepared', 'tool_batch_prepared', 'await_model_result', 'await_tool_results', 'reply_recorded', 'results_to_consume', 'ready_for_next_step', 'await_delegation', 'await_peer', 'interrupted', 'blocked', 'completed')), schema_version BIGINT NOT NULL CHECK (schema_version = 1), digest VARCHAR(255) NOT NULL, safe_to_fork BOOLEAN NOT NULL CHECK (safe_to_fork IN (FALSE, TRUE)), recorded_at TIMESTAMP(6) NOT NULL)"

    execute "CREATE TABLE events (id VARCHAR(255) PRIMARY KEY NOT NULL, scope_id VARCHAR(255) NOT NULL, seq BIGINT NOT NULL CHECK (seq > 0), type VARCHAR(255) NOT NULL, schema_version BIGINT NOT NULL CHECK (schema_version = 1), turn_id VARCHAR(255), operation_id VARCHAR(255), causation_id VARCHAR(255), payload TEXT NOT NULL, dedupe_key VARCHAR(255), source_agent_id VARCHAR(255), source_event_id VARCHAR(255), recorded_at TIMESTAMP(6) NOT NULL)"

    create unique_index(:events, [:scope_id, :seq])
    create unique_index(:events, [:scope_id, :dedupe_key])

    execute "CREATE TABLE operations (id VARCHAR(255) PRIMARY KEY NOT NULL, owner_agent_id VARCHAR(255) REFERENCES agents(id), turn_id VARCHAR(255), tool_call_id VARCHAR(255), ordinal BIGINT CHECK (ordinal >= 0), step_id VARCHAR(255), role VARCHAR(255), owner_generation BIGINT, prepared_seq BIGINT, sources TEXT NOT NULL, description TEXT NOT NULL, description_digest VARCHAR(255) NOT NULL, accepted_result TEXT, accepted_evidence_id VARCHAR(255) #{if repo().__adapter__() == Ecto.Adapters.SQLite3, do: "REFERENCES execution_evidence(id)", else: ""}, lock_version BIGINT NOT NULL CHECK (lock_version >= 0), history_seq BIGINT NOT NULL CHECK (history_seq >= 0), schema_version BIGINT NOT NULL CHECK (schema_version = 1), recorded_at TIMESTAMP(6) NOT NULL)"

    execute "CREATE TABLE executions (attempt_id VARCHAR(255) PRIMARY KEY NOT NULL, operation_id VARCHAR(255) NOT NULL REFERENCES operations(id), executor_id VARCHAR(255) NOT NULL, executor_boot_id VARCHAR(255) NOT NULL, description_digest VARCHAR(255) NOT NULL, dispatch_state VARCHAR(255) NOT NULL CHECK (dispatch_state IN ('prepared', 'send_claimed')), observation TEXT, budget TEXT NOT NULL, lock_version BIGINT NOT NULL CHECK (lock_version >= 0), recorded_at TIMESTAMP(6) NOT NULL)"

    create unique_index(:executions, [:operation_id])

    execute "CREATE TABLE execution_evidence (id VARCHAR(255) PRIMARY KEY NOT NULL, operation_id VARCHAR(255) NOT NULL REFERENCES operations(id), attempt_id VARCHAR(255) NOT NULL REFERENCES executions(attempt_id), executor_id VARCHAR(255) NOT NULL, evidence_id VARCHAR(255) NOT NULL, digest VARCHAR(255) NOT NULL, content TEXT NOT NULL, resolution TEXT, recorded_at TIMESTAMP(6) NOT NULL)"

    create unique_index(:execution_evidence, [:executor_id, :evidence_id])

    execute "CREATE TABLE commands (id VARCHAR(255) PRIMARY KEY NOT NULL, scope_id VARCHAR(255) NOT NULL, command_id VARCHAR(255) NOT NULL, request_digest VARCHAR(255) NOT NULL, response TEXT NOT NULL, recorded_at TIMESTAMP(6) NOT NULL)"

    create unique_index(:commands, [:scope_id, :command_id])

    execute "CREATE TABLE artifacts (id VARCHAR(255) PRIMARY KEY NOT NULL, digest VARCHAR(255) NOT NULL, media_type VARCHAR(255) NOT NULL, size BIGINT NOT NULL CHECK (size >= 0), content #{if repo().__adapter__() == Ecto.Adapters.Postgres, do: "BYTEA", else: "BLOB"} NOT NULL, recorded_at TIMESTAMP(6) NOT NULL)"

    create unique_index(:artifacts, [:digest])
    create index(:events, [:scope_id, :turn_id, :seq])
    create index(:operations, [:owner_agent_id, :turn_id])
    create index(:checkpoints, [:agent_id])
    create index(:execution_evidence, [:operation_id])
    flush()
    # SQLite accepts cyclic FK declarations before the referenced table exists;
    # PostgreSQL needs these two edges added after both endpoints are created.
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      execute "ALTER TABLE agents ADD CONSTRAINT agents_head_checkpoint_id_fkey FOREIGN KEY (head_checkpoint_id) REFERENCES checkpoints(id)"

      execute "ALTER TABLE operations ADD CONSTRAINT operations_accepted_evidence_id_fkey FOREIGN KEY (accepted_evidence_id) REFERENCES execution_evidence(id)"
    end
  end

  def down, do: raise("durable migrations are forward-only; restore a verified backup")
end
