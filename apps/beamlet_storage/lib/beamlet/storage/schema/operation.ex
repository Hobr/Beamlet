defmodule Beamlet.Storage.Schema.Operation do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "operations" do
    field :owner_agent_id, :string
    field :turn_id, :string
    field :tool_call_id, :string
    field :ordinal, :integer
    field :step_id, :string
    field :role, :string
    field :owner_generation, :integer
    field :prepared_seq, :integer
    field :sources, Beamlet.Storage.JSON, kind: :operation
    field :description, Beamlet.Storage.JSON, kind: :operation
    field :description_digest, :string
    field :accepted_result, Beamlet.Storage.JSON, kind: :result
    field :accepted_evidence_id, :string
    field :lock_version, :integer
    field :history_seq, :integer
    field :schema_version, :integer
    field :recorded_at, :utc_datetime_usec
  end

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id sources description description_digest lock_version history_seq schema_version recorded_at)a
    )
  end
end
