defmodule Beamlet.Actions do
  @moduledoc "Data validation shared by operation producers and executors."
  @forbidden ~w(password secret token credential credentials api_key authorization root workspace_root)a
  @typedoc "Ordinary bounded data. Secret labels, UTF-8, depth and byte limits remain runtime checks."
  @type data :: atom() | number() | binary() | [data()] | %{optional(data()) => data()}
  @typedoc "JSON credential data; UTF-8, root-label, depth and size restrictions are runtime checks."
  @type json_value :: nil | boolean() | number() | String.t() | [json_value()] | json_object()
  @type json_object :: %{optional(String.t()) => json_value()}

  @spec bounded?(term(), term()) :: boolean()
  def bounded?(term, bytes) do
    data?(term, 0) and :erlang.external_size(term) <= bytes
  rescue
    _ -> false
  end

  @doc "Validates a dedicated credential JSON object, including its complete JSON byte size."
  @spec credentials?(term()) :: boolean()
  def credentials?(value) do
    is_map(value) and not is_struct(value) and map_size(value) <= 32 and
      Enum.all?(value, fn {key, _} ->
        is_binary(key) and byte_size(key) in 1..128 and String.valid?(key)
      end) and credential_data?(value, 0) and
      IO.iodata_length(:json.encode(value)) <= 16_384
  rescue
    _ -> false
  end

  @spec credential_data?(term(), non_neg_integer()) :: boolean()
  defp credential_data?(_, depth) when depth > 24, do: false
  defp credential_data?(value, _) when is_binary(value), do: String.valid?(value)

  defp credential_data?(value, _) when is_number(value) or value in [true, false, nil],
    do: true

  defp credential_data?([], _), do: true

  defp credential_data?([head | tail], depth),
    do: credential_data?(head, depth + 1) and credential_list?(tail, depth)

  defp credential_data?(value, depth) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, item} ->
      is_binary(key) and String.valid?(key) and
        String.downcase(key) not in ["root", "workspace_root"] and
        credential_data?(key, depth + 1) and credential_data?(item, depth + 1)
    end)
  end

  defp credential_data?(_, _), do: false
  @spec credential_list?(term(), non_neg_integer()) :: boolean()
  defp credential_list?([], _), do: true

  defp credential_list?([head | tail], depth),
    do: credential_data?(head, depth + 1) and credential_list?(tail, depth)

  defp credential_list?(_, _), do: false

  @spec data?(term(), non_neg_integer()) :: boolean()
  defp data?(_, depth) when depth > 24, do: false
  defp data?(x, _) when is_binary(x), do: String.valid?(x)
  defp data?(x, _) when is_number(x) or is_atom(x), do: true
  defp data?(x, depth) when is_list(x), do: Enum.all?(x, &data?(&1, depth + 1))

  defp data?(x, depth) when is_map(x) and not is_struct(x) do
    Enum.all?(x, fn {k, v} ->
      k not in @forbidden and k not in Enum.map(@forbidden, &Atom.to_string/1) and
        data?(k, depth + 1) and data?(v, depth + 1)
    end)
  end

  defp data?(_, _), do: false
end
