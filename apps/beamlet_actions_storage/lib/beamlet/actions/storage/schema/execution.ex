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

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(attempt_id operation_id executor_id executor_boot_id description_digest dispatch_state budget lock_version recorded_at)a
    )
  end
end
