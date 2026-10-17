defmodule Beamlet.Actions do
  @moduledoc "Data validation shared by operation producers and executors."
  @forbidden ~w(password secret token credential credentials api_key authorization root workspace_root)a
  def bounded?(term, bytes) do
    data?(term, 0) and :erlang.external_size(term) <= bytes
  rescue
    _ -> false
  end

  @doc "Validates a dedicated credential JSON object, including its complete JSON byte size."
  def credentials?(value) do
    is_map(value) and not is_struct(value) and map_size(value) <= 32 and
      Enum.all?(value, fn {key, _} ->
        is_binary(key) and byte_size(key) in 1..128 and String.valid?(key)
      end) and credential_data?(value, 0) and
      IO.iodata_length(:json.encode(value)) <= 16_384
  rescue
    _ -> false
  end

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
  defp credential_list?([], _), do: true

  defp credential_list?([head | tail], depth),
    do: credential_data?(head, depth + 1) and credential_list?(tail, depth)

  defp credential_list?(_, _), do: false

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
