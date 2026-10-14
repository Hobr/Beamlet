defmodule Beamlet.Agent.Caller.Schema do
  @moduledoc false
  use Ecto.Migration

  def change do
    execute("""
    CREATE TABLE caller_rounds (
      owner TEXT NOT NULL COLLATE BINARY,
      round_key TEXT NOT NULL COLLATE BINARY,
      collection TEXT NOT NULL COLLATE BINARY,
      manifest TEXT NOT NULL,
      progress TEXT NOT NULL,
      PRIMARY KEY(owner,round_key),
      CHECK(length(manifest) <= 16777216 AND length(progress) <= 16777216)
    )
    """)

    execute("""
    CREATE TRIGGER caller_manifest_immutable
    BEFORE UPDATE OF owner,round_key,collection,manifest ON caller_rounds
    BEGIN SELECT RAISE(ABORT, 'caller manifest is immutable'); END
    """)
  end
end
