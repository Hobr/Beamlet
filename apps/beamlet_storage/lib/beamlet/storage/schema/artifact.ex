defmodule Beamlet.Storage.Schema.Artifact do
  @moduledoc false
  # 隐藏的 SQL 记录：内容保持原始二进制，插入及读取复核 size 与 SHA-256，允许未插入结构但 changeset 要求完整字段。
  use Ecto.Schema
  alias Beamlet.Storage.ArtifactChangeset
  alias Beamlet.Storage.Codec
  @primary_key {:id, :string, autogenerate: false}
  schema "artifacts" do
    field :digest, :string
    field :media_type, :string
    field :size, :integer
    field :content, :binary
    field :recorded_at, :utc_datetime_usec
  end

  @typedoc "包含尚未插入的记录，字段可为 nil；有效内容与必填约束由 changeset 校验。

Includes uninserted Ecto records; required identity/content fields are enforced by changeset validation."
  @type t :: %__MODULE__{
          id: String.t() | nil,
          digest: String.t() | nil,
          media_type: String.t() | nil,
          size: non_neg_integer() | nil,
          content: binary() | nil,
          recorded_at: DateTime.t() | nil,
          __meta__: Ecto.Schema.Metadata.t()
        }
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
  def changeset(record, attrs) do
    cs =
      ArtifactChangeset.build(record, attrs, ~w(id digest media_type size content recorded_at)a)

    content = Ecto.Changeset.get_field(cs, :content)

    cond do
      not is_binary(content) ->
        Ecto.Changeset.add_error(cs, :content, "invalid_data")

      byte_size(content) > 16_777_216 ->
        Ecto.Changeset.add_error(cs, :content, "limit")

      Codec.hash(content) != Ecto.Changeset.get_field(cs, :digest) or
          byte_size(content) != Ecto.Changeset.get_field(cs, :size) ->
        Ecto.Changeset.add_error(cs, :content, "invalid_data")

      true ->
        cs
    end
  end
end
