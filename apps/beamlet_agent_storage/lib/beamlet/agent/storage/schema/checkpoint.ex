defmodule Beamlet.Agent.Storage.Schema.Checkpoint do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Agent.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "checkpoints" do
    field(:agent_id, :string)
    field(:turn_id, :string)
    field(:through_seq, :integer)
    field(:reducer_version, :integer)
    field(:data, Beamlet.Agent.Storage.JSON, kind: :checkpoint)
    field(:continuation, :string)
    field(:schema_version, :integer)
    field(:digest, :string)
    field(:safe_to_fork, :boolean)
    field(:recorded_at, :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: String.t() | nil,
          agent_id: String.t() | nil,
          turn_id: String.t() | nil,
          through_seq: integer() | nil,
          reducer_version: integer() | nil,
          data: Beamlet.Agent.Storage.Records.value(),
          continuation: String.t() | nil,
          schema_version: integer() | nil,
          digest: String.t() | nil,
          safe_to_fork: boolean() | nil,
          recorded_at: DateTime.t() | nil
        }
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id agent_id through_seq reducer_version data continuation schema_version digest safe_to_fork recorded_at)a
    )
  end
end
