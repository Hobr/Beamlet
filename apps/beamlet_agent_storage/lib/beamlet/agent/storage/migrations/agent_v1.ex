defmodule Beamlet.Agent.Storage.Migrations.AgentV1 do
  @moduledoc "Agent-owned authority tables and read projection."
  use Ecto.Migration

  def up do
    execute(
      "CREATE TABLE agents (id VARCHAR(255) PRIMARY KEY NOT NULL, authority_id VARCHAR(255) NOT NULL, alias VARCHAR(255), definition TEXT NOT NULL, head_checkpoint_id VARCHAR(255) #{if repo().__adapter__() == Ecto.Adapters.SQLite3, do: "REFERENCES checkpoints(id)", else: ""}, generation BIGINT NOT NULL CHECK (generation >= 0), lock_version BIGINT NOT NULL CHECK (lock_version >= 0), history_seq BIGINT NOT NULL CHECK (history_seq >= 0), dispatch_scope_id VARCHAR(255) NOT NULL UNIQUE REFERENCES dispatch_scopes(id), forked_from_agent_id VARCHAR(255), forked_from_checkpoint_id VARCHAR(255))"
    )

    create(unique_index(:agents, [:authority_id, :alias]))

    execute(
      "CREATE TABLE checkpoints (id VARCHAR(255) PRIMARY KEY NOT NULL, agent_id VARCHAR(255) NOT NULL REFERENCES agents(id), turn_id VARCHAR(255), through_seq BIGINT NOT NULL CHECK (through_seq >= 0), reducer_version BIGINT NOT NULL CHECK (reducer_version > 0), data TEXT NOT NULL, continuation VARCHAR(255) NOT NULL CHECK (continuation IN ('await_input', 'model_prepared', 'tool_batch_prepared', 'await_model_result', 'await_tool_results', 'reply_recorded', 'results_to_consume', 'ready_for_next_step', 'await_delegation', 'await_peer', 'interrupted', 'blocked', 'completed')), schema_version BIGINT NOT NULL CHECK (schema_version = 1), digest VARCHAR(255) NOT NULL, safe_to_fork BOOLEAN NOT NULL CHECK (safe_to_fork IN (FALSE, TRUE)), recorded_at TIMESTAMP(6) NOT NULL)"
    )

    execute(
      "CREATE TABLE agent_events (id VARCHAR(255) PRIMARY KEY NOT NULL, scope_id VARCHAR(255) NOT NULL, seq BIGINT NOT NULL CHECK (seq > 0), type VARCHAR(255) NOT NULL, schema_version BIGINT NOT NULL CHECK (schema_version = 1), turn_id VARCHAR(255), operation_id VARCHAR(255), causation_id VARCHAR(255), payload TEXT NOT NULL, dedupe_key VARCHAR(255), source_agent_id VARCHAR(255), source_event_id VARCHAR(255), recorded_at TIMESTAMP(6) NOT NULL)"
    )

    create(unique_index(:agent_events, [:scope_id, :seq]))
    create(unique_index(:agent_events, [:scope_id, :dedupe_key]))

    execute(
      "CREATE TABLE commands (id VARCHAR(255) PRIMARY KEY NOT NULL, scope_id VARCHAR(255) NOT NULL, command_id VARCHAR(255) NOT NULL, request_digest VARCHAR(255) NOT NULL, response TEXT NOT NULL, recorded_at TIMESTAMP(6) NOT NULL)"
    )

    create(unique_index(:commands, [:scope_id, :command_id]))
    create(index(:agent_events, [:scope_id, :turn_id, :seq]))
    create(index(:checkpoints, [:agent_id]))

    execute(
      "CREATE TABLE agent_operations (id VARCHAR(255) PRIMARY KEY NOT NULL REFERENCES operations(id), owner_agent_id VARCHAR(255) NOT NULL REFERENCES agents(id), turn_id VARCHAR(255) NOT NULL, step_id VARCHAR(255) NOT NULL, role VARCHAR(255) NOT NULL, ordinal BIGINT CHECK (ordinal >= 0), tool_call_id VARCHAR(255), owner_generation BIGINT NOT NULL CHECK (owner_generation >= 0), prepared_seq BIGINT NOT NULL CHECK (prepared_seq > 0), sources TEXT NOT NULL)"
    )

    create(index(:agent_operations, [:owner_agent_id, :turn_id]))
    flush()

    if repo().__adapter__() == Ecto.Adapters.Postgres do
      execute(
        "ALTER TABLE agents ADD CONSTRAINT agents_head_checkpoint_id_fkey FOREIGN KEY (head_checkpoint_id) REFERENCES checkpoints(id)"
      )
    end

    execute(
      "CREATE VIEW agent_operation_projections AS SELECT o.*, a.owner_agent_id, a.turn_id, a.step_id, a.role, a.ordinal, a.tool_call_id, a.owner_generation, a.prepared_seq, a.sources FROM operations o JOIN agent_operations a ON a.id = o.id"
    )
  end

  def down, do: raise("forward only")
end
