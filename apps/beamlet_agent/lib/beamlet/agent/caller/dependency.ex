defmodule Beamlet.Agent.Caller.Dependency do
  @moduledoc """
  One durable caller slot: an explicit stable submission identity and immutable definition.
  Multiple slots may deliberately reference the same identity, but not different definitions.
  """
  alias Beamlet.{Definition, Identity}

  @enforce_keys [:slot, :identity, :definition]
  defstruct @enforce_keys

  def new(slot, %Identity{} = identity, %Definition{} = definition) do
    with true <- Identity.valid_text?(slot) and not is_nil(identity.key),
         {:ok, ^identity} <- Identity.new(identity.collection, identity.namespace, identity.key),
         {:ok, ^definition} <- Definition.new(Map.from_struct(definition)) do
      {:ok, %__MODULE__{slot: slot, identity: identity, definition: definition}}
    else
      _invalid -> {:error, :invalid_dependency}
    end
  end

  def new(_slot, _identity, _definition), do: {:error, :invalid_dependency}

  @doc false
  def manifest(dependencies, collection) when is_list(dependencies) do
    cond do
      length(dependencies) not in 1..256 ->
        {:error, :invalid_dependency_count}

      not Enum.all?(dependencies, &valid?(&1, collection)) ->
        {:error, :invalid_dependency}

      length(Enum.uniq_by(dependencies, & &1.slot)) != length(dependencies) ->
        {:error, :duplicate_slot}

      not consistent_definitions?(dependencies) ->
        {:error, :conflicting_dependency_definition}

      true ->
        {:ok, Enum.sort_by(dependencies, & &1.slot)}
    end
  end

  def manifest(_dependencies, _collection), do: {:error, :invalid_dependencies}

  defp valid?(%__MODULE__{identity: %Identity{}, definition: %Definition{}} = d, collection),
    do:
      d.identity.collection == collection and
        match?({:ok, ^d}, new(d.slot, d.identity, d.definition))

  defp valid?(_dependency, _collection), do: false

  defp consistent_definitions?(dependencies) do
    dependencies
    |> Enum.group_by(& &1.identity)
    |> Enum.all?(fn {_identity, slots} -> length(Enum.uniq_by(slots, & &1.definition)) == 1 end)
  end

  @doc false
  def pack(%__MODULE__{} = d),
    do: %{"slot" => d.slot, "identity" => d.identity, "definition" => d.definition}

  @doc false
  def unpack(%{"slot" => slot, "identity" => identity, "definition" => definition} = value)
      when map_size(value) == 3, do: new(slot, identity, definition)

  def unpack(_value), do: {:error, :invalid_dependency}
end
