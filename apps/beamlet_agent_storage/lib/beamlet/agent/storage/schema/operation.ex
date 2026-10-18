defmodule Beamlet.Agent.Storage.Schema.Operation do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Agent.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "agent_operation_projections" do
    field(:owner_agent_id, :string)
    field(:turn_id, :string)
    field(:tool_call_id, :string)
    field(:ordinal, :integer)
    field(:step_id, :string)
    field(:role, :string)
    field(:owner_generation, :integer)
    field(:prepared_seq, :integer)
    field(:sources, Beamlet.Agent.Storage.JSON, kind: :operation)
    field(:dispatch_scope_id, :string)
    field(:dispatch_epoch, :integer)
    field(:description, Beamlet.Agent.Storage.JSON, kind: :operation)
    field(:description_digest, :string)
    field(:accepted_result, Beamlet.Agent.Storage.JSON, kind: :result)
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
      ~w(id sources description description_digest lock_version history_seq schema_version recorded_at)a
    )
  end
end
