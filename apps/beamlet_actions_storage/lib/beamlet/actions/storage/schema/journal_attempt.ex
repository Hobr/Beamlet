defmodule Beamlet.Actions.Storage.Schema.JournalAttempt do
  @moduledoc false
  # 内部 Ecto 行映射，包含尚未插入的 nil 构造状态；对外通过记录门面校验身份和事务约束。
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

  @type t :: %__MODULE__{
          id: String.t() | nil,
          authority_id: String.t() | nil,
          operation_id: String.t() | nil,
          attempt_id: String.t() | nil,
          description_digest: String.t() | nil,
          executor_id: String.t() | nil,
          executor_boot_id: String.t() | nil,
          state: String.t() | nil,
          stop_reason: String.t() | nil,
          termination: Beamlet.Actions.Storage.Records.value(),
          terminal_artifacts: Beamlet.Actions.Storage.Records.value(),
          terminal_result: Beamlet.Actions.Storage.Records.value(),
          receipt_id: String.t() | nil,
          receipt_digest: String.t() | nil,
          receipt: Beamlet.Actions.Storage.Records.value(),
          acknowledged: boolean() | nil,
          schema_version: integer() | nil,
          lock_version: integer() | nil,
          recorded_at: DateTime.t() | nil
        }
  @spec valid_attachment_container?(term()) :: boolean()
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
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
