defmodule Beamlet.Storage.Schema.Checkpoint do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "checkpoints" do
    field :agent_id, :string
    field :turn_id, :string
    field :data, Beamlet.Storage.JSON, kind: :checkpoint
    field :continuation, :string
    field :schema_version, :integer
    field :digest, :string
    field :safe_to_fork, :boolean
    field :recorded_at, :utc_datetime_usec
  end

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id agent_id data continuation schema_version digest safe_to_fork recorded_at)a
    )
  end
end
