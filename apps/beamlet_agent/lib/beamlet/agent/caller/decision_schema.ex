defmodule Beamlet.Agent.Caller.DecisionSchema do
  @moduledoc false
  use Ecto.Migration

  def change do
    execute("""
    CREATE TABLE caller_decisions (
      owner TEXT NOT NULL COLLATE BINARY,
      computation TEXT NOT NULL COLLATE BINARY,
      step_key TEXT NOT NULL COLLATE BINARY,
      collection TEXT NOT NULL COLLATE BINARY,
      source_round TEXT NOT NULL COLLATE BINARY,
      next_round TEXT NOT NULL COLLATE BINARY,
      payload TEXT NOT NULL,
      PRIMARY KEY(owner,computation,step_key),
      UNIQUE(owner,next_round),
      FOREIGN KEY(owner,source_round) REFERENCES caller_rounds(owner,round_key),
      CHECK(source_round != next_round AND length(payload) <= 16777216)
    )
    """)

    execute("""
    CREATE TRIGGER caller_decision_immutable BEFORE UPDATE ON caller_decisions
    BEGIN SELECT RAISE(ABORT, 'caller decision is immutable'); END
    """)
  end
end
