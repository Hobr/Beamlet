defmodule Beamlet.Storage.Schema.Event do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "events" do
    field :scope_id, :string
    field :seq, :integer
    field :type, :string
    field :schema_version, :integer
    field :turn_id, :string
    field :operation_id, :string
    field :causation_id, :string
    field :payload, Beamlet.Storage.JSON
    field :dedupe_key, :string
    field :source_agent_id, :string
    field :source_event_id, :string
    field :recorded_at, :utc_datetime_usec
  end

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id scope_id seq type schema_version payload recorded_at)a
    )
  end
end
