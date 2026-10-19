defmodule Beamlet.Storage.ArtifactChangeset do
  @moduledoc false
  # 只供制品 schema 使用；拒绝未知字段及混合原子/字符串键，避免 cast 忽略额外输入。
  import Ecto.Changeset
  alias Beamlet.Storage.Codec

  @spec build(Ecto.Schema.t(), term(), [atom()]) :: Ecto.Changeset.t()
  def build(record, attrs, required) when is_map(attrs) and not is_struct(attrs) do
    fields = record.__struct__.__schema__(:fields)
    allowed = Enum.map(fields, &Atom.to_string/1)
    known? = Enum.all?(Map.keys(attrs), &((is_atom(&1) and &1 in fields) or &1 in allowed))

    if known? and homogeneous?(Map.keys(attrs)) do
      record
      |> cast(attrs, fields, empty_values: [])
      |> validate_required(required)
      |> validate_fields(fields)
    else
      invalid(record)
    end
  end

  def build(record, _, _), do: invalid(record)
  @spec homogeneous?([term()]) :: boolean()
  defp homogeneous?([]), do: true
  defp homogeneous?([key | keys]), do: Enum.all?(keys, &(is_atom(&1) == is_atom(key)))
  @spec invalid(Ecto.Schema.t()) :: Ecto.Changeset.t()
  defp invalid(record), do: record |> change() |> add_error(:base, "invalid_data")

  @spec validate_fields(Ecto.Changeset.t(), [atom()]) :: Ecto.Changeset.t()
  defp validate_fields(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      validate_field(acc, field, get_field(acc, field))
    end)
  end

  @spec validate_field(Ecto.Changeset.t(), atom(), term()) :: Ecto.Changeset.t()
  defp validate_field(cs, _, nil), do: cs

  defp validate_field(cs, :id, value) do
    if Codec.uuid?(value), do: cs, else: add_error(cs, :id, "invalid_data")
  end

  defp validate_field(cs, :size, _), do: validate_number(cs, :size, greater_than_or_equal_to: 0)
  defp validate_field(cs, :digest, _), do: validate_format(cs, :digest, ~r/\A[0-9a-f]{64}\z/)
  defp validate_field(cs, field, value), do: validate_string(cs, field, value)

  @spec validate_string(Ecto.Changeset.t(), atom(), term()) :: Ecto.Changeset.t()
  defp validate_string(cs, field, value) when is_binary(value) and field != :content do
    if String.valid?(value) and byte_size(value) <= 255,
      do: cs,
      else: add_error(cs, field, "invalid_data")
  end

  defp validate_string(cs, _, _), do: cs
end
