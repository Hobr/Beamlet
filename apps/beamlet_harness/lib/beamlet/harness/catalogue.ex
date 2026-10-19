defmodule Beamlet.Harness.Catalogue do
  @moduledoc "Data-only catalogue and atomic whole-batch validation. No invocation occurs here."
  alias Beamlet.Harness.Arguments

  @typedoc "Descriptors keyed by validated Tool name; descriptor string keys and schema relations are runtime checked."
  @type descriptor :: Beamlet.Harness.Model.json_object()
  @type t :: %{optional(String.t()) => descriptor()}
  @typep batch_result :: {:ok, [Beamlet.Harness.Model.call()]} | {:error, :invalid_tool_batch}

  @spec new(term()) :: {:ok, t()} | {:error, :invalid_catalogue}
  def new(descriptors) when is_list(descriptors) and length(descriptors) <= 64 do
    if Enum.all?(descriptors, &descriptor?/1) and
         length(Enum.uniq_by(descriptors, & &1["name"])) == length(descriptors),
       do: {:ok, Map.new(descriptors, &{&1["name"], &1})},
       else: {:error, :invalid_catalogue}
  end

  def new(_), do: {:error, :invalid_catalogue}

  @spec validate(term()) :: :ok | {:error, :invalid_catalogue}
  def validate(catalogue) when is_map(catalogue) do
    case new(Map.values(catalogue)) do
      {:ok, ^catalogue} -> :ok
      _ -> {:error, :invalid_catalogue}
    end
  end

  def validate(_), do: {:error, :invalid_catalogue}

  @spec descriptor?(term()) :: boolean()
  defp descriptor?(%{"name" => n, "description" => d, "parameters" => s} = descriptor) do
    Map.keys(descriptor) -- ~w(name description parameters) == [] and name?(n) and
      is_binary(d) and String.valid?(d) and byte_size(d) <= 4096 and Arguments.schema?(s) and
      byte_size(Jason.encode!(descriptor)) <= 16_384
  end

  defp descriptor?(_), do: false
  @spec name?(term()) :: boolean()
  def name?(n), do: is_binary(n) and Regex.match?(~r/\A[a-zA-Z0-9_-]{1,64}\z/, n)

  @spec batch(term(), term()) :: batch_result()
  def batch(calls, catalogue) when is_list(calls) and length(calls) in 1..8 do
    case validate(catalogue) do
      :ok -> validate_batch(calls, catalogue)
      _ -> {:error, :invalid_tool_batch}
    end
  end

  def batch(_, _), do: {:error, :invalid_tool_batch}

  @spec validate_batch([term()], t()) :: batch_result()
  defp validate_batch(calls, catalogue) do
    Enum.reduce_while(calls, {:ok, [], MapSet.new()}, fn call, {:ok, acc, ids} ->
      with %{"id" => id, "name" => name, "arguments" => args} <- call,
           true <- Map.keys(call) -- ~w(id name arguments) == [],
           true <- is_binary(id) and byte_size(id) in 1..128 and String.valid?(id),
           false <- MapSet.member?(ids, id),
           {:ok, descriptor} <- Map.fetch(catalogue, name),
           :ok <- Arguments.validate(args, descriptor["parameters"]),
           {:ok, encoded} <- Jason.encode(args),
           true <- byte_size(encoded) <= 16_384 do
        {:cont, {:ok, [%{id: id, name: name, arguments: args} | acc], MapSet.put(ids, id)}}
      else
        _ -> {:halt, {:error, :invalid_tool_batch}}
      end
    end)
    |> case do
      {:ok, acc, _} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end
end
