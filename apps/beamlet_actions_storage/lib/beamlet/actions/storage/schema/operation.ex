defmodule Beamlet.Actions.Storage.Schema.Operation do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Actions.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "operations" do
    field(:dispatch_scope_id, :string)
    field(:dispatch_epoch, :integer)
    field(:description, Beamlet.Actions.Storage.JSON, kind: :operation)
    field(:description_digest, :string)
    field(:accepted_result, Beamlet.Actions.Storage.JSON, kind: :result)
    field(:accepted_evidence_id, :string)
    field(:lock_version, :integer)
    field(:history_seq, :integer)
    field(:schema_version, :integer)
    field(:recorded_at, :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id description description_digest lock_version history_seq schema_version recorded_at)a
    )
  end
end
