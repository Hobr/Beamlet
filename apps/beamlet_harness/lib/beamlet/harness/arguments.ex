defmodule Beamlet.Harness.Arguments do
  @moduledoc "Explicit shallow object schema subset; unsupported keywords fail registration."
  @primitive ~w(string integer number boolean)
  def schema?(%{"type" => "object", "properties" => properties} = schema)
      when is_map(properties) do
    Map.keys(schema) -- ~w(type properties required additionalProperties) == [] and
      is_list(Map.get(schema, "required", [])) and
      Enum.all?(Map.get(schema, "required", []), &Map.has_key?(properties, &1)) and
      is_boolean(Map.get(schema, "additionalProperties", false)) and
      Enum.all?(properties, fn {key, value} ->
        is_binary(key) and String.valid?(key) and primitive?(value)
      end)
  end

  def schema?(_), do: false

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

  defp constraint_schema?({"enum", values}, type),
    do: is_list(values) and values != [] and Enum.all?(values, &typed?(&1, type))

  defp constraint_schema?({k, v}, _) when k in ["minLength", "maxLength"],
    do: is_integer(v) and v >= 0 and v <= 16_384

  defp constraint_schema?({k, v}, _) when k in ["minimum", "maximum"], do: is_number(v)
  defp constraint_schema?(_, _), do: true

  def validate(value, schema) do
    if schema?(schema) and is_map(value) and
         Enum.all?(schema["required"] || [], &Map.has_key?(value, &1)) and
         Enum.all?(value, &property_valid?(&1, schema)),
       do: :ok,
       else: {:error, :invalid_arguments}
  end

  defp property_valid?({key, value}, schema) do
    is_binary(key) and String.valid?(key) and property_value_valid?(key, value, schema)
  end

  defp property_value_valid?(key, value, schema) do
    case Map.fetch(schema["properties"], key) do
      {:ok, spec} -> valid?(value, spec)
      :error -> Map.get(schema, "additionalProperties", false) and primitive_value?(value)
    end
  end

  defp primitive_value?(v) when is_binary(v), do: String.valid?(v)
  defp primitive_value?(v), do: is_number(v) or is_boolean(v) or is_nil(v)

  defp valid?(v, s) do
    typed?(v, s["type"]) and (not Map.has_key?(s, "enum") or v in s["enum"]) and
      constraints?(v, s)
  end

  defp constraints?(v, s) when is_binary(v) do
    count = v |> String.codepoints() |> length()

    String.valid?(v) and count >= Map.get(s, "minLength", 0) and
      count <= Map.get(s, "maxLength", 16_384)
  end

  defp constraints?(v, s) when is_number(v),
    do: v >= Map.get(s, "minimum", v) and v <= Map.get(s, "maximum", v)

  defp constraints?(_, _), do: true
  defp typed?(v, "string"), do: is_binary(v) and String.valid?(v)
  defp typed?(v, "integer"), do: is_integer(v)
  defp typed?(v, "number"), do: is_number(v)
  defp typed?(v, "boolean"), do: is_boolean(v)
end
