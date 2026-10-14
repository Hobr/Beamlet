defmodule BeamletRuntime.Object.FenceSchema do
  @moduledoc false
  use Ecto.Migration

  def change do
    execute("""
    CREATE TABLE object_fences (
      account TEXT NOT NULL COLLATE BINARY,
      object_ref TEXT NOT NULL COLLATE BINARY,
      operation TEXT NOT NULL COLLATE BINARY,
      collection TEXT NOT NULL COLLATE BINARY,
      intent_id TEXT NOT NULL COLLATE BINARY,
      execution_id TEXT NOT NULL COLLATE BINARY,
      request TEXT NOT NULL,
      authorization TEXT NOT NULL,
      evidence_ref TEXT NOT NULL UNIQUE,
      PRIMARY KEY(account,object_ref,operation,collection,intent_id,execution_id),
      FOREIGN KEY(account,object_ref) REFERENCES resource_objects(account,object_ref)
    )
    """)

    execute("""
    CREATE TRIGGER immutable_object_fence BEFORE UPDATE ON object_fences
    BEGIN SELECT RAISE(ABORT, 'object exclusion is immutable'); END
    """)

    execute("""
    CREATE TRIGGER retained_object_fence BEFORE DELETE ON object_fences
    BEGIN SELECT RAISE(ABORT, 'object exclusion must be retained'); END
    """)
  end
end
