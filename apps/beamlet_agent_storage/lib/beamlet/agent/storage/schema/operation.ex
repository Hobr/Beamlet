defmodule Beamlet.Agent.Storage.Schema.Operation do
  @moduledoc false
  # 只读联接视图：Agent 关联与 Actions 事实各归原层所有；changeset 不代表允许通过视图写入 Operation。
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

  @type t :: %__MODULE__{
          id: String.t() | nil,
          owner_agent_id: String.t() | nil,
          turn_id: String.t() | nil,
          tool_call_id: String.t() | nil,
          ordinal: integer() | nil,
          step_id: String.t() | nil,
          role: String.t() | nil,
          owner_generation: integer() | nil,
          prepared_seq: integer() | nil,
          sources: Beamlet.Agent.Storage.Records.value(),
          dispatch_scope_id: String.t() | nil,
          dispatch_epoch: integer() | nil,
          description: Beamlet.Agent.Storage.Records.value(),
          description_digest: String.t() | nil,
          accepted_result: Beamlet.Agent.Storage.Records.value(),
          accepted_evidence_id: String.t() | nil,
          lock_version: integer() | nil,
          history_seq: integer() | nil,
          schema_version: integer() | nil,
          recorded_at: DateTime.t() | nil
        }
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id sources description description_digest lock_version history_seq schema_version recorded_at)a
    )
  end
end
