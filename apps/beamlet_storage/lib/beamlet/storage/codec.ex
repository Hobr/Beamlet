defmodule Beamlet.Storage.Codec do
  @moduledoc """
  Strict persisted JSON, independent of Erlang wire limits. Strings are not
  secret-scanned: callers must enforce their content policy. Structured credential
  fields are rejected recursively. Numbers retain integer versus float spelling.
  """
  @depth 32
  @nodes 100_000
  @secret_keys ~w(credentials credential api_key apikey token access_token refresh_token password secret authorization private_key)
  # A heuristic, not a secret scanner: exact credential names plus underscore- or
  # dash-separated credential segments (client_secret, bearer_token, api-key).
  # Reference-shaped keys (secret_ref, credential_id, api_key_name) are legitimate
  # because persisted definitions point at secrets instead of holding them, and the
  # plural "tokens" is absent so counters such as max_tokens remain storable.
  @secret_segments ~w(credential credentials password passwd secret secrets token)
  @reference_suffixes ~w(ref refs id ids name names path)

  def limit(bytes) when is_integer(bytes) and bytes > 0, do: bytes

  @doc "Validates and emits sorted-key UTF-8 JSON, never ETF or inspected terms."
  def encode(value, kind \\ 4_194_304) do
    with {:ok, _} <- walk(value, 0, {@nodes, limit(kind)}),
         encoded <- value |> canonical() |> IO.iodata_to_binary(),
         true <- byte_size(encoded) <= limit(kind) do
      {:ok, encoded}
    else
      false -> {:error, :limit}
      {:error, _} = error -> error
    end
  end

  def decode(bytes, kind \\ 4_194_304)

  def decode(bytes, kind) when is_binary(bytes) do
    if byte_size(bytes) <= limit(kind) do
      with :ok <- scan_depth(bytes, 0, false, false),
           {:ok, value} <- Jason.decode(bytes, objects: :ordered_objects),
           {:ok, value} <- plain_objects(value),
           {:ok, _} <- encode(value, kind) do
        {:ok, value}
      else
        {:error, reason} when reason in [:limit, :invalid_data] -> {:error, reason}
        _ -> {:error, :invalid_data}
      end
    else
      {:error, :limit}
    end
  end

  def decode(_, _), do: {:error, :invalid_data}

  def digest(value, kind \\ 4_194_304) do
    with {:ok, bytes} <- encode(value, kind), do: {:ok, hash(bytes)}
  end

  def hash(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  def uuid?(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, ^value} -> true
      _ -> false
    end
  end

  def uuid?(_), do: false

  # Byte accounting happens during traversal, before constructing a whole JSON value.
  defp walk(_, depth, {nodes, bytes}) when depth > @depth or nodes <= 0 or bytes < 0,
    do: {:error, :limit}

  defp walk(value, _, budget) when is_boolean(value) or is_nil(value) or is_integer(value),
    do: spend(budget, byte_size(Jason.encode!(value)))

  defp walk(value, _, budget) when is_float(value) do
    # BEAM floats cannot represent NaN/infinity; malformed JSON numbers are
    # rejected by Jason before reaching this clause.
    spend(budget, byte_size(Jason.encode!(value)))
  end

  defp walk(value, _, {_, bytes} = budget) when is_binary(value) do
    cond do
      byte_size(value) > bytes -> {:error, :limit}
      not String.valid?(value) -> {:error, :invalid_data}
      true -> spend(budget, byte_size(Jason.encode!(value)))
    end
  end

  defp walk(value, depth, budget) when is_list(value) do
    with {:ok, left} <- spend(budget, 2), do: walk_list(value, depth, left, false)
  end

  defp walk(%{__struct__: _}, _, _), do: {:error, :invalid_data}

  defp walk(value, depth, budget) when is_map(value) do
    with {:ok, left} <- spend(budget, if(map_size(value) == 0, do: 2, else: 1)) do
      Enum.reduce_while(value, {:ok, left}, &walk_pair(&1, &2, depth))
    end
  end

  defp walk(_, _, _), do: {:error, :invalid_data}

  defp walk_pair({key, item}, {:ok, remaining}, depth) do
    if is_binary(key) and byte_size(key) <= elem(remaining, 1) and
         not credential_key?(key) do
      with {:ok, left} <- walk(key, depth + 1, remaining),
           {:ok, left} <- spend_bytes(left, 2),
           {:ok, left} <- walk(item, depth + 1, left) do
        {:cont, {:ok, left}}
      else
        error -> {:halt, error}
      end
    else
      {:halt, {:error, :invalid_data}}
    end
  end

  defp credential_key?(key) do
    normalized = key |> String.downcase() |> String.replace("-", "_")
    segments = String.split(normalized, "_", trim: true)

    cond do
      normalized in @secret_keys -> true
      segments == [] -> false
      List.last(segments) in @reference_suffixes -> false
      true -> Enum.any?(segments, &(&1 in @secret_segments))
    end
  end

  defp spend({nodes, bytes}, used) when bytes >= used and nodes > 0,
    do: {:ok, {nodes - 1, bytes - used}}

  defp spend(_, _), do: {:error, :limit}
  defp spend_bytes({nodes, bytes}, used) when bytes >= used, do: {:ok, {nodes, bytes - used}}
  defp spend_bytes(_, _), do: {:error, :limit}
  defp walk_list([], _, budget, _), do: {:ok, budget}

  defp walk_list([head | tail], depth, budget, comma?) do
    with {:ok, left} <- spend_bytes(budget, if(comma?, do: 1, else: 0)),
         {:ok, left} <- walk(head, depth + 1, left),
         do: walk_list(tail, depth, left, true)
  end

  defp walk_list(_, _, _, _), do: {:error, :invalid_data}

  # Bound parser recursion before Jason allocates a decoded tree.
  defp scan_depth(_, depth, _, _) when depth > @depth + 1, do: {:error, :limit}
  defp scan_depth(<<>>, _, _, _), do: :ok

  defp scan_depth(<<_, rest::binary>>, depth, true, true),
    do: scan_depth(rest, depth, true, false)

  defp scan_depth(<<92, rest::binary>>, depth, true, false),
    do: scan_depth(rest, depth, true, true)

  defp scan_depth(<<34, rest::binary>>, depth, quoted, false),
    do: scan_depth(rest, depth, not quoted, false)

  defp scan_depth(<<c, rest::binary>>, depth, false, _) when c in [123, 91],
    do: scan_depth(rest, depth + 1, false, false)

  defp scan_depth(<<c, rest::binary>>, depth, false, _) when c in [125, 93],
    do: scan_depth(rest, depth - 1, false, false)

  defp scan_depth(<<_, rest::binary>>, depth, quoted, escaped),
    do: scan_depth(rest, depth, quoted, escaped)

  # Reject duplicate keys rather than silently accepting Jason's last value.
  defp plain_objects(%Jason.OrderedObject{values: pairs}) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with false <- Map.has_key?(acc, key), {:ok, value} <- plain_objects(value) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        _ -> {:halt, {:error, :invalid_data}}
      end
    end)
  end

  defp plain_objects(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case plain_objects(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp plain_objects(value), do: {:ok, value}

  defp canonical(value) when is_map(value) do
    pairs =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} -> [Jason.encode!(key), ":", canonical(item)] end)

    ["{", Enum.intersperse(pairs, ","), "}"]
  end

  defp canonical(value) when is_list(value),
    do: ["[", Enum.intersperse(Enum.map(value, &canonical/1), ","), "]"]

  defp canonical(value), do: Jason.encode!(value)
end
