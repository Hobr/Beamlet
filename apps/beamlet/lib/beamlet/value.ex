defmodule Beamlet.Value do
  @moduledoc """
  Restricted logical values and canonical representation v1.

  Accepts nil, booleans, safe integers, UTF-8 strings, proper lists and maps
  with string keys. Validation consumes byte, node and container-depth budgets
  while traversing. This accepts decoded values; a wire decoder must separately
  reject duplicate object keys and unsupported numeric spellings.
  """

  @max_integer 9_007_199_254_740_991
  @defaults [max_bytes: 1_048_576, max_depth: 32, max_nodes: 10_000]

  @type t :: nil | boolean() | integer() | String.t() | [t()] | %{String.t() => t()}
  @type error ::
          :invalid_type
          | :invalid_utf8
          | :invalid_object_key
          | :integer_out_of_range
          | :max_bytes
          | :max_depth
          | :max_nodes
          | :invalid_budget

  @spec validate(term(), keyword()) :: :ok | {:error, error()}
  def validate(value, opts \\ []) do
    with {:ok, _encoded, _budget} <- encode(value, opts), do: :ok
  end

  @spec canonical(term(), keyword()) :: {:ok, binary()} | {:error, error()}
  def canonical(value, opts \\ []) do
    with {:ok, encoded, _budget} <- encode(value, opts), do: {:ok, IO.iodata_to_binary(encoded)}
  end

  @spec equal?(term(), term()) :: boolean()
  def equal?(left, right) do
    left === right and validate(left) == :ok
  end

  defp encode(value, opts) do
    with :ok <- validate_options(opts) do
      budget = @defaults |> Keyword.merge(opts) |> Map.new() |> Map.merge(%{bytes: 0, nodes: 0})
      visit(value, 0, budget)
    end
  end

  defp validate_options(opts) do
    valid =
      Keyword.keyword?(opts) and Keyword.keys(opts) -- Keyword.keys(@defaults) == [] and
        Enum.all?(opts, fn {_key, n} -> is_integer(n) and n >= 0 end)

    if valid, do: :ok, else: {:error, :invalid_budget}
  end

  defp visit(value, depth, budget) do
    with {:ok, budget} <- consume_node(budget), do: encode_value(value, depth, budget)
  end

  defp encode_value(nil, _depth, budget), do: emit("null", budget)
  defp encode_value(true, _depth, budget), do: emit("true", budget)
  defp encode_value(false, _depth, budget), do: emit("false", budget)

  defp encode_value(value, _depth, budget) when is_integer(value) do
    if value >= -@max_integer and value <= @max_integer,
      do: emit(Integer.to_string(value), budget),
      else: {:error, :integer_out_of_range}
  end

  defp encode_value(value, _depth, budget) when is_binary(value), do: string(value, budget)

  defp encode_value(value, depth, budget) when is_list(value) do
    with :ok <- depth(depth + 1, budget),
         {:ok, open, budget} <- emit("[", budget),
         {:ok, items, budget} <- array(value, depth + 1, budget, [], ""),
         {:ok, close, budget} <- emit("]", budget) do
      {:ok, [open, items, close], budget}
    end
  end

  defp encode_value(value, depth, budget) when is_map(value) and not is_struct(value) do
    with :ok <- depth(depth + 1, budget),
         :ok <- object_size(value, budget),
         :ok <- object_keys(value, budget),
         {:ok, open, budget} <- emit("{", budget),
         {:ok, items, budget} <- object(Enum.sort(value), depth + 1, budget, [], ""),
         {:ok, close, budget} <- emit("}", budget) do
      {:ok, [open, items, close], budget}
    end
  end

  defp encode_value(_value, _depth, _budget), do: {:error, :invalid_type}

  defp array([], _depth, budget, acc, _separator), do: {:ok, Enum.reverse(acc), budget}

  defp array([item | rest], depth, budget, acc, separator) do
    with {:ok, comma, budget} <- emit(separator, budget),
         {:ok, item, budget} <- visit(item, depth, budget) do
      array(rest, depth, budget, [[comma, item] | acc], ",")
    end
  end

  defp array(_improper_tail, _depth, _budget, _acc, _separator), do: {:error, :invalid_type}

  defp object([], _depth, budget, acc, _separator), do: {:ok, Enum.reverse(acc), budget}

  defp object([{key, value} | rest], depth, budget, acc, separator) do
    with {:ok, comma, budget} <- emit(separator, budget),
         {:ok, key, budget} <- string(key, budget),
         {:ok, colon, budget} <- emit(":", budget),
         {:ok, value, budget} <- visit(value, depth, budget) do
      object(rest, depth, budget, [[comma, key, colon, value] | acc], ",")
    end
  end

  defp object_size(value, budget) do
    if map_size(value) <= budget.max_nodes - budget.nodes,
      do: :ok,
      else: {:error, :max_nodes}
  end

  defp object_keys(value, budget) do
    Enum.reduce_while(value, {:ok, 0}, fn {key, _value}, {:ok, bytes} ->
      cond do
        not is_binary(key) -> {:halt, {:error, :invalid_object_key}}
        bytes + byte_size(key) > budget.max_bytes - budget.bytes -> {:halt, {:error, :max_bytes}}
        true -> {:cont, {:ok, bytes + byte_size(key)}}
      end
    end)
    |> case do
      {:ok, _bytes} -> :ok
      error -> error
    end
  end

  defp string(value, budget) do
    cond do
      byte_size(value) + 2 > budget.max_bytes - budget.bytes ->
        {:error, :max_bytes}

      not String.valid?(value) ->
        {:error, :invalid_utf8}

      true ->
        with {:ok, quote, budget} <- emit("\"", budget),
             {:ok, body, budget} <- escape(value, budget, []),
             {:ok, close, budget} <- emit("\"", budget) do
          {:ok, [quote, body, close], budget}
        end
    end
  end

  defp escape(<<>>, budget, acc), do: {:ok, Enum.reverse(acc), budget}

  defp escape(<<codepoint::utf8, rest::binary>>, budget, acc) do
    escaped =
      case codepoint do
        ?" ->
          "\\\""

        ?\\ ->
          "\\\\"

        n when n < 32 ->
          "\\u" <> String.pad_leading(Integer.to_string(n, 16) |> String.downcase(), 4, "0")

        n ->
          <<n::utf8>>
      end

    with {:ok, chunk, budget} <- emit(escaped, budget), do: escape(rest, budget, [chunk | acc])
  end

  defp consume_node(%{nodes: n, max_nodes: max}) when n >= max, do: {:error, :max_nodes}
  defp consume_node(budget), do: {:ok, %{budget | nodes: budget.nodes + 1}}

  defp depth(n, %{max_depth: max}) when n > max, do: {:error, :max_depth}
  defp depth(_n, _budget), do: :ok

  defp emit(bytes, budget) do
    size = budget.bytes + byte_size(bytes)

    if size <= budget.max_bytes,
      do: {:ok, bytes, %{budget | bytes: size}},
      else: {:error, :max_bytes}
  end
end
