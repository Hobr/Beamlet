defmodule Beamlet.Harness.Arguments do
  @moduledoc "Explicit shallow object schema subset; unsupported keywords fail registration."
  @primitive ~w(string integer number boolean)
  @typedoc "Native Tool schema object; supported string-key fields and constraint relations are runtime validated."
  @type schema :: Beamlet.Harness.Model.json_object()
  @spec schema?(term()) :: boolean()
  def schema?(%{"type" => "object", "properties" => properties} = schema)
      when is_map(properties) do
    Map.keys(schema) -- ~w(type properties required additionalProperties) == [] and
      proper_list?(Map.get(schema, "required", [])) and
      Enum.all?(Map.get(schema, "required", []), &Map.has_key?(properties, &1)) and
      is_boolean(Map.get(schema, "additionalProperties", false)) and
      Enum.all?(properties, fn {key, value} ->
        is_binary(key) and String.valid?(key) and primitive?(value)
      end)
  end

  def schema?(_), do: false

  @spec proper_list?(term()) :: boolean()
  defp proper_list?([]), do: true
  defp proper_list?([_ | tail]), do: proper_list?(tail)
  defp proper_list?(_), do: false

  @spec primitive?(term()) :: boolean()
  defp primitive?(%{"type" => type} = s) do
    allowed =
      case type do
        "string" -> ~w(type enum minLength maxLength)
        t when t in ["integer", "number"] -> ~w(type enum minimum maximum)
        "boolean" -> ~w(type enum)
        _ -> []
      end

    type in @primitive and Map.keys(s) -- allowed == [] and
      Enum.all?(s, &constraint_schema?(&1, type))
  end

  defp primitive?(_), do: false

  @spec constraint_schema?({term(), term()}, term()) :: boolean()
  defp constraint_schema?({"enum", values}, type),
    do: proper_list?(values) and values != [] and Enum.all?(values, &typed?(&1, type))

  defp constraint_schema?({k, v}, _) when k in ["minLength", "maxLength"],
    do: is_integer(v) and v >= 0 and v <= 16_384

  defp constraint_schema?({k, v}, _) when k in ["minimum", "maximum"], do: is_number(v)
  defp constraint_schema?(_, _), do: true

  @spec validate(term(), term()) :: :ok | {:error, :invalid_arguments}
  def validate(value, schema) do
    if schema?(schema) and is_map(value) and
         Enum.all?(schema["required"] || [], &Map.has_key?(value, &1)) and
         Enum.all?(value, &property_valid?(&1, schema)),
       do: :ok,
       else: {:error, :invalid_arguments}
  end

  @spec property_valid?({term(), term()}, schema()) :: boolean()
  defp property_valid?({key, value}, schema) do
    is_binary(key) and String.valid?(key) and property_value_valid?(key, value, schema)
  end

  @spec property_value_valid?(String.t(), term(), schema()) :: boolean()
  defp property_value_valid?(key, value, schema) do
    case Map.fetch(schema["properties"], key) do
      {:ok, spec} -> valid?(value, spec)
      :error -> Map.get(schema, "additionalProperties", false) and primitive_value?(value)
    end
  end

  @spec primitive_value?(term()) :: boolean()
  defp primitive_value?(v) when is_binary(v), do: String.valid?(v)
  defp primitive_value?(v), do: is_number(v) or is_boolean(v) or is_nil(v)

  @spec valid?(term(), schema()) :: boolean()
  defp valid?(v, s) do
    typed?(v, s["type"]) and (not Map.has_key?(s, "enum") or v in s["enum"]) and
      constraints?(v, s)
  end

  @spec constraints?(term(), schema()) :: boolean()
  defp constraints?(v, s) when is_binary(v) do
    count = v |> String.codepoints() |> length()

    String.valid?(v) and count >= Map.get(s, "minLength", 0) and
      count <= Map.get(s, "maxLength", 16_384)
  end

  defp constraints?(v, s) when is_number(v),
    do: v >= Map.get(s, "minimum", v) and v <= Map.get(s, "maximum", v)

  defp constraints?(_, _), do: true
  @spec typed?(term(), String.t()) :: boolean()
  defp typed?(v, "string"), do: is_binary(v) and String.valid?(v)
  defp typed?(v, "integer"), do: is_integer(v)
  defp typed?(v, "number"), do: is_number(v)
  defp typed?(v, "boolean"), do: is_boolean(v)
end
