defmodule BeamletRuntime.Object.Schema do
  @moduledoc false
  use Ecto.Migration

  def change do
    execute("""
    CREATE TABLE object_service (
      singleton INTEGER PRIMARY KEY CHECK(singleton=1),
      identity TEXT NOT NULL, instance TEXT NOT NULL
    )
    """)

    execute("""
    CREATE TABLE resource_objects (
      account TEXT NOT NULL COLLATE BINARY,
      object_ref TEXT NOT NULL COLLATE BINARY,
      initial_content TEXT NOT NULL,
      content TEXT NOT NULL,
      version INTEGER NOT NULL CHECK(version >= 0 AND version <= 9007199254740991),
      PRIMARY KEY(account,object_ref)
    )
    """)

    execute("""
    CREATE TABLE object_receipts (
      account TEXT NOT NULL COLLATE BINARY,
      object_ref TEXT NOT NULL COLLATE BINARY,
      operation TEXT NOT NULL COLLATE BINARY,
      collection TEXT NOT NULL COLLATE BINARY,
      intent_id TEXT NOT NULL COLLATE BINARY,
      request TEXT NOT NULL,
      applied INTEGER NOT NULL CHECK(applied IN (0,1)),
      version INTEGER NOT NULL CHECK(version >= 0 AND version <= 9007199254740991),
      receipt_ref TEXT NOT NULL UNIQUE,
      PRIMARY KEY(account,object_ref,operation,collection,intent_id),
      FOREIGN KEY(account,object_ref) REFERENCES resource_objects(account,object_ref)
    )
    """)

    execute("""
    CREATE TRIGGER immutable_object_receipt BEFORE UPDATE ON object_receipts
    BEGIN SELECT RAISE(ABORT, 'object receipt is immutable'); END
    """)

    execute("""
    CREATE TRIGGER retained_object_receipt BEFORE DELETE ON object_receipts
    BEGIN SELECT RAISE(ABORT, 'object receipt must be retained'); END
    """)

    execute("""
    CREATE TRIGGER immutable_object_identity
    BEFORE UPDATE OF account,object_ref,initial_content ON resource_objects
    BEGIN SELECT RAISE(ABORT, 'object identity is immutable'); END
    """)

    execute("""
    CREATE TRIGGER immutable_object_service BEFORE UPDATE ON object_service
    BEGIN SELECT RAISE(ABORT, 'object service is immutable'); END
    """)
  end
end
