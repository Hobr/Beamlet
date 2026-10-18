defmodule Beamlet.Storage.Schema.Artifact do
  @moduledoc false
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
