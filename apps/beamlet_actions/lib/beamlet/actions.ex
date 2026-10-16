defmodule Beamlet.Actions do
  @moduledoc "Data validation shared by operation producers and executors."
  @forbidden ~w(password secret token credential credentials api_key authorization root workspace_root)a
  def bounded?(term, bytes) do
    data?(term, 0) and :erlang.external_size(term) <= bytes
  rescue
    _ -> false
  end

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
