defmodule BeamletRuntime.Storage.SQLite.Schema do
  @moduledoc "Version 1 SQLite ledger: permanent submission identity, unique Outcome and ordered History."
  use Ecto.Migration

  def change do
    execute("""
    CREATE TABLE beamlet_intents (
      collection TEXT NOT NULL COLLATE BINARY,
      id TEXT NOT NULL COLLATE BINARY,
      namespace TEXT NOT NULL COLLATE BINARY,
      submission_key TEXT COLLATE BINARY,
      snapshot TEXT NOT NULL,
      phase TEXT NOT NULL CHECK (phase IN ('open', 'closed')),
      current_id TEXT,
      current_phase TEXT,
      lease_expires_at INTEGER,
      revision INTEGER NOT NULL CHECK (revision > 0),
      PRIMARY KEY (collection, id),
      UNIQUE (collection, namespace, submission_key)
    )
    """)

    execute("""
    CREATE TABLE beamlet_history (
      collection TEXT NOT NULL,
      intent_id TEXT NOT NULL,
      revision INTEGER NOT NULL,
      position INTEGER NOT NULL,
      event TEXT NOT NULL,
      PRIMARY KEY (collection, intent_id, revision, position),
      FOREIGN KEY (collection, intent_id) REFERENCES beamlet_intents (collection, id)
    )
    """)

    execute("""
    CREATE TABLE beamlet_outcomes (
      collection TEXT NOT NULL,
      intent_id TEXT NOT NULL,
      outcome TEXT NOT NULL,
      PRIMARY KEY (collection, intent_id),
      FOREIGN KEY (collection, intent_id) REFERENCES beamlet_intents (collection, id)
    )
    """)

    execute("CREATE INDEX beamlet_work ON beamlet_intents (collection, phase, current_phase, id)")
  end
end
