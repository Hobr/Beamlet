defmodule Beamlet.Actions.Storage.Schema.OperationEvent do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Actions.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "operation_events" do
    field(:operation_id, :string)
    field(:seq, :integer)
    field(:type, :string)
    field(:schema_version, :integer)
    field(:payload, Beamlet.Actions.Storage.JSON)
    field(:recorded_at, :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id operation_id seq type schema_version payload recorded_at)a
    )
    |> Ecto.Changeset.validate_inclusion(:type, ~w(operation.prepared operation.result_accepted))
  end
end
