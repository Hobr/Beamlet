defmodule Beamlet.Actions.Storage.Schema.Execution do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Actions.Storage.RecordChangeset
  @primary_key {:attempt_id, :string, autogenerate: false}
  schema "executions" do
    field(:operation_id, :string)
    field(:executor_id, :string)
    field(:executor_boot_id, :string)
    field(:description_digest, :string)
    field(:dispatch_state, :string)
    field(:observation, Beamlet.Actions.Storage.JSON)
    field(:budget, Beamlet.Actions.Storage.JSON)
    field(:lock_version, :integer)
    field(:recorded_at, :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          attempt_id: String.t() | nil,
          operation_id: String.t() | nil,
          executor_id: String.t() | nil,
          executor_boot_id: String.t() | nil,
          description_digest: String.t() | nil,
          dispatch_state: String.t() | nil,
          observation: Beamlet.Actions.Storage.Records.value(),
          budget: Beamlet.Actions.Storage.Records.value(),
          lock_version: integer() | nil,
          recorded_at: DateTime.t() | nil
        }
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(attempt_id operation_id executor_id executor_boot_id description_digest dispatch_state budget lock_version recorded_at)a
    )
  end
end
