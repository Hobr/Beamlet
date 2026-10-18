defmodule Beamlet.Actions.Storage.Schema.JournalAttempt do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Actions.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "journal_attempts" do
    field(:authority_id, :string)
    field(:operation_id, :string)
    field(:attempt_id, :string)
    field(:description_digest, :string)
    field(:executor_id, :string)
    field(:executor_boot_id, :string)
    field(:state, :string)
    field(:stop_reason, :string)
    field(:termination, Beamlet.Actions.Storage.JSON)
    field(:terminal_artifacts, Beamlet.Actions.Storage.JSON, kind: :journal_artifacts)
    field(:terminal_result, Beamlet.Actions.Storage.JSON, kind: :result)
    field(:receipt_id, :string)
    field(:receipt_digest, :string)
    field(:receipt, Beamlet.Actions.Storage.JSON)
    field(:acknowledged, :boolean)
    field(:schema_version, :integer)
    field(:lock_version, :integer)
    field(:recorded_at, :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id authority_id operation_id attempt_id description_digest executor_id executor_boot_id state acknowledged schema_version lock_version recorded_at)a
    )
    |> Ecto.Changeset.validate_change(:terminal_artifacts, fn field, value ->
      if valid_attachment_container?(value), do: [], else: [{field, "invalid_data"}]
    end)
  end

  # Full attachment/base64/digest/reference validation belongs to ExecutorJournal
  # alongside its atomic terminal protocol, not this generic column boundary.
  defp valid_attachment_container?(%{"version" => 1, "items" => items} = value)
       when map_size(value) == 2 and is_map(items) and not is_struct(items) do
    map_size(items) <= 64
  end

  defp valid_attachment_container?(_), do: false
end
