defmodule Beamlet.Agent.Core.Data do
  @moduledoc false
  @body_keys ~w(messages assistant request reply result output payload content text arguments prompt tools schema)

  @typedoc "String-key JSON. Literal string keys, UUID spelling, UTF-8 and depth limits remain runtime checks."
  @type value :: nil | boolean() | number() | binary() | [value()] | object()
  @type object :: %{optional(binary()) => value()}
  @spec uuid?(term()) :: boolean()
  @spec digest?(term()) :: boolean()
  @spec plain?(term()) :: boolean()
  @spec plain?(term(), non_neg_integer()) :: boolean()
  @spec list?(term(), non_neg_integer()) :: boolean()
  @spec proper_list?(term()) :: boolean()
  @spec fields?(term()) :: boolean()
  @spec control?(term()) :: boolean()
  @spec reference_only?(term()) :: boolean()

  # Canonical spelling accepted by the storage adapter's Ecto.UUID.cast equality check.
  def uuid?(
        <<a::binary-size(8), "-", b::binary-size(4), "-", c::binary-size(4), "-",
          d::binary-size(4), "-", e::binary-size(12)>>
      ) do
    match?({:ok, _}, Base.decode16(a <> b <> c <> d <> e, case: :lower))
  end

  def uuid?(_), do: false

  def digest?(value) when is_binary(value) and byte_size(value) == 64,
    do: match?({:ok, _}, Base.decode16(value, case: :lower))

  def digest?(_), do: false

  def plain?(value), do: plain?(value, 0)
  defp plain?(_, depth) when depth > 32, do: false
  defp plain?(value, _) when is_binary(value), do: String.valid?(value)
  defp plain?(value, _) when is_number(value) or is_boolean(value) or is_nil(value), do: true
  defp plain?([], _), do: true
  defp plain?([head | tail], depth), do: plain?(head, depth + 1) and list?(tail, depth)

  defp plain?(value, depth) when is_map(value) and not is_struct(value),
    do:
      Enum.all?(value, fn {key, item} ->
        is_binary(key) and String.valid?(key) and plain?(item, depth + 1)
      end)

  defp plain?(_, _), do: false
  defp list?([], _), do: true
  defp list?([head | tail], depth), do: plain?(head, depth + 1) and list?(tail, depth)
  defp list?(_, _), do: false

  # Container checks do not spend a domain payload's depth budget.
  def proper_list?([]), do: true
  def proper_list?([_ | tail]), do: proper_list?(tail)
  def proper_list?(_), do: false

  def fields?(map) when is_map(map) and not is_struct(map),
    do:
      Enum.all?(map, fn {key, value} ->
        is_binary(key) and String.valid?(key) and plain?(value)
      end)

  def fields?(_), do: false

  def control?(value), do: is_map(value) and plain?(value) and reference_only?(value)

  defp reference_only?(value) when is_map(value),
    do: Enum.all?(value, fn {key, item} -> key not in @body_keys and reference_only?(item) end)

  defp reference_only?(value) when is_list(value), do: Enum.all?(value, &reference_only?/1)
  defp reference_only?(_), do: true
end
