defmodule Beamlet.Agent.Storage.Schema.Event do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Agent.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "agent_events" do
    field(:scope_id, :string)
    field(:seq, :integer)
    field(:type, :string)
    field(:schema_version, :integer)
    field(:turn_id, :string)
    field(:operation_id, :string)
    field(:causation_id, :string)
    field(:payload, Beamlet.Agent.Storage.JSON)
    field(:dedupe_key, :string)
    field(:source_agent_id, :string)
    field(:source_event_id, :string)
    field(:recorded_at, :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: String.t() | nil,
          scope_id: String.t() | nil,
          seq: integer() | nil,
          type: String.t() | nil,
          schema_version: integer() | nil,
          turn_id: String.t() | nil,
          operation_id: String.t() | nil,
          causation_id: String.t() | nil,
          payload: Beamlet.Agent.Storage.Records.value(),
          dedupe_key: String.t() | nil,
          source_agent_id: String.t() | nil,
          source_event_id: String.t() | nil,
          recorded_at: DateTime.t() | nil
        }
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id scope_id seq type schema_version payload recorded_at)a
    )
  end
end
