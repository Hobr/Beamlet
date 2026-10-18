defmodule Beamlet.Actions.Storage.Records do
  @moduledoc """
  Shared boundary for the record transaction facades. Validation and comparison
  helpers are pure; transaction helpers run inside the caller's already-open
  transaction. Every facade revalidates identity, stored identity and CAS inputs
  instead of trusting an upstream caller. Errors stay plain atoms from the
  stage-A taxonomy; SQL, connection and configuration detail never escape.
  """
  alias Beamlet.Actions.Storage.Codec
  alias Beamlet.Actions.Storage.Read
  alias Beamlet.Storage.Transaction

  @errors ~w(invalid_data limit conflict stale_epoch schema_unsupported artifact_missing storage_unavailable storage_outcome_unknown)a
  @digest ~r/\A[0-9a-f]{64}\z/

  @doc "Runs one write transaction; rollback keeps the whole write set out of the dataset."
  def transact(repo, fun) do
    case Transaction.write(repo, fn -> settle(repo, fun) end) do
      {:ok, response} -> {:ok, response}
      {:error, reason} when reason in @errors -> {:error, reason}
      {:error, _} -> {:error, :storage_outcome_unknown}
    end
  rescue
    Ecto.ConstraintError -> {:error, :conflict}
    Ecto.Query.CastError -> {:error, :invalid_data}
    Ecto.ChangeError -> {:error, :invalid_data}
    error in ArgumentError -> Read.read(fn -> reraise(error, __STACKTRACE__) end)
  end

  defp settle(repo, fun) do
    case fun.() do
      {:ok, response} -> response
      {:error, reason} when is_atom(reason) -> repo.rollback(reason)
      _ -> repo.rollback(:storage_outcome_unknown)
    end
  end

  def fields(attrs, required, optional) do
    keys = if is_map(attrs) and not is_struct(attrs), do: Map.keys(attrs)

    cond do
      is_nil(keys) -> {:error, :invalid_data}
      not Enum.all?(keys, &is_atom/1) -> {:error, :invalid_data}
      not Enum.all?(required, &Map.has_key?(attrs, &1)) -> {:error, :invalid_data}
      not Enum.all?(keys, &(&1 in required or &1 in optional)) -> {:error, :invalid_data}
      true -> {:ok, attrs}
    end
  end

  def uuid(value) do
    if Codec.uuid?(value), do: {:ok, value}, else: {:error, :invalid_data}
  end

  def optional_uuid(nil), do: {:ok, nil}
  def optional_uuid(value), do: uuid(value)

  def text(value, max) when is_binary(value) do
    if String.valid?(value) and byte_size(value) in 1..max,
      do: {:ok, value},
      else: {:error, :invalid_data}
  end

  def text(_, _), do: {:error, :invalid_data}

  def optional_text(nil, _), do: {:ok, nil}
  def optional_text(value, max), do: text(value, max)

  def count(value) when is_integer(value) and value >= 0, do: {:ok, value}
  def count(_), do: {:error, :invalid_data}

  def digest(value) when is_binary(value) do
    if Regex.match?(@digest, value), do: {:ok, value}, else: {:error, :invalid_data}
  end

  def digest(_), do: {:error, :invalid_data}

  def json(value, kind) do
    case Codec.encode(value, kind) do
      {:ok, _bytes} -> {:ok, value}
      {:error, reason} when reason in [:limit, :invalid_data] -> {:error, reason}
      _ -> {:error, :invalid_data}
    end
  end

  def enum(value, allowed) when is_atom(value) and not is_nil(value),
    do: enum(Atom.to_string(value), allowed)

  def enum(value, allowed) when is_binary(value) do
    if value in allowed, do: {:ok, value}, else: {:error, :invalid_data}
  end

  def enum(_, _), do: {:error, :invalid_data}

  def get(repo, schema, id) do
    case repo.get(schema, id, log: false) do
      nil -> {:error, :conflict}
      record -> {:ok, record}
    end
  end

  def insert(repo, changeset) do
    case repo.insert(changeset, log: false) do
      {:ok, record} -> {:ok, record}
      {:error, changeset} -> {:error, changeset_error(changeset)}
    end
  end

  def changeset_error(changeset) do
    errors =
      Enum.map(changeset.errors, fn {_field, {message, opts}} ->
        {message, Keyword.get(opts, :constraint)}
      end)

    cond do
      Enum.any?(errors, &(elem(&1, 0) == "limit")) -> :limit
      Enum.any?(errors, &(elem(&1, 1) == :unique)) -> :conflict
      true -> :invalid_data
    end
  end

  @doc "Plain, atom-free data: timestamps become ISO 8601 strings and struct meta is dropped."
  def plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def plain(nil), do: nil

  def plain(%_{} = struct) do
    struct |> Map.from_struct() |> Map.delete(:__meta__) |> plain()
  end

  def plain(%{} = map) do
    Map.new(map, fn {key, value} -> {plain_key(key), plain(value)} end)
  end

  def plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  def plain(value), do: value

  defp plain_key(key) when is_atom(key), do: Atom.to_string(key)
  defp plain_key(key), do: key
end
