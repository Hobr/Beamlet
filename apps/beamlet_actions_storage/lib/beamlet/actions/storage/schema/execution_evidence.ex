defmodule Beamlet.Actions.Storage.Schema.ExecutionEvidence do
  @moduledoc false
  # 内部 Ecto 行映射，包含尚未插入的 nil 构造状态；对外通过记录门面校验身份和事务约束。
  use Ecto.Schema
  alias Beamlet.Actions.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "execution_evidence" do
    field(:operation_id, :string)
    field(:attempt_id, :string)
    field(:executor_id, :string)
    field(:evidence_id, :string)
    field(:digest, :string)
    field(:content, Beamlet.Actions.Storage.JSON)
    field(:resolution, Beamlet.Actions.Storage.JSON)
    field(:recorded_at, :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: String.t() | nil,
          operation_id: String.t() | nil,
          attempt_id: String.t() | nil,
          executor_id: String.t() | nil,
          evidence_id: String.t() | nil,
          digest: String.t() | nil,
          content: Beamlet.Actions.Storage.Records.value(),
          resolution: Beamlet.Actions.Storage.Records.value(),
          recorded_at: DateTime.t() | nil
        }
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id operation_id attempt_id executor_id evidence_id digest content recorded_at)a
    )
  end
end
