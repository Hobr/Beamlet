defmodule Beamlet.Actions.Storage.Schema.ExecutionEvidence do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Actions.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "execution_evidence" do
    field(:operation_id, :string)
    field(:attempt_id, :string)
    field(:executor_id, :string)
    field(:evidence_id, :string)
    field(:digest, :string)
    field(:content, Beamlet.Actions.Storage.JSON)
    field(:resolution, Beamlet.Actions.Storage.JSON)
    field(:recorded_at, :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id operation_id attempt_id executor_id evidence_id digest content recorded_at)a
    )
  end
end
