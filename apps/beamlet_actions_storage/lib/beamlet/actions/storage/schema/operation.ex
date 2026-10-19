defmodule Beamlet.Actions.Storage.Schema.Operation do
  @moduledoc false
  # 内部 Ecto 行映射，包含尚未插入的 nil 构造状态；对外通过记录门面校验身份和事务约束。
  use Ecto.Schema
  alias Beamlet.Actions.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "operations" do
    field(:dispatch_scope_id, :string)
    field(:dispatch_epoch, :integer)
    field(:description, Beamlet.Actions.Storage.JSON, kind: :operation)
    field(:description_digest, :string)
    field(:accepted_result, Beamlet.Actions.Storage.JSON, kind: :result)
    field(:accepted_evidence_id, :string)
    field(:lock_version, :integer)
    field(:history_seq, :integer)
    field(:schema_version, :integer)
    field(:recorded_at, :utc_datetime_usec)
  end

  @typedoc "内部 Ecto 行形状，允许尚未插入的 nil 字段；changeset 与 SQL 才实施持久化约束。

Ecto record including unvalidated construction state; persisted constraints are checked by the changeset and SQL."
  @type t :: %__MODULE__{
          id: String.t() | nil,
          dispatch_scope_id: String.t() | nil,
          dispatch_epoch: integer() | nil,
          description: Beamlet.Actions.Storage.Records.value(),
          description_digest: String.t() | nil,
          accepted_result: Beamlet.Actions.Storage.Records.value(),
          accepted_evidence_id: String.t() | nil,
          lock_version: integer() | nil,
          history_seq: integer() | nil,
          schema_version: integer() | nil,
          recorded_at: DateTime.t() | nil
        }
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id description description_digest lock_version history_seq schema_version recorded_at)a
    )
  end
end
