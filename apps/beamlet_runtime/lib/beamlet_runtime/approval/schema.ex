defmodule BeamletRuntime.Approval.Schema do
  @moduledoc false
  use Ecto.Migration

  def change do
    execute(
      "CREATE TABLE approval_service (singleton INTEGER PRIMARY KEY CHECK(singleton=1), identity TEXT NOT NULL, instance TEXT NOT NULL)"
    )

    execute("""
    CREATE TABLE approvals (
      collection TEXT NOT NULL COLLATE BINARY,
      intent_id TEXT NOT NULL COLLATE BINARY,
      request TEXT NOT NULL,
      decision TEXT CHECK (decision IN ('approved','denied')),
      decision_ref TEXT UNIQUE,
      responder TEXT,
      PRIMARY KEY(collection, intent_id),
      CHECK ((decision IS NULL AND decision_ref IS NULL AND responder IS NULL) OR
             (decision IS NOT NULL AND decision_ref IS NOT NULL AND responder IS NOT NULL))
    )
    """)
  end
end
