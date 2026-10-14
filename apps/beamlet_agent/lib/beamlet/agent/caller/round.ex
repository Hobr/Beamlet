defmodule Beamlet.Agent.Caller.Round do
  @moduledoc """
  Committed caller progress. Outcomes are full immutable Authority results, not notifications.
  aggregate is nil until every explicit slot has an Intent and an accepted Outcome.
  """
  alias Beamlet.Agent.Caller.Dependency
  alias Beamlet.{Identity, Outcome, Value}
  alias Beamlet.Report.Source
  alias Beamlet.Token

  @enforce_keys [:owner, :key, :collection, :dependencies]
  defstruct @enforce_keys ++ [intents: %{}, outcomes: %{}, aggregate: nil]

  @doc false
  def progress(round),
    do: %{
      "intents" => round.intents,
      "outcomes" => round.outcomes,
      "aggregate" => round.aggregate
    }

  @doc false
  def restore(owner, key, collection, manifest, progress) when is_list(manifest) do
    with {:ok, dependencies} <- unpack(manifest),
         {:ok, ^dependencies} <- Dependency.manifest(dependencies, collection),
         %{"intents" => intents, "outcomes" => outcomes, "aggregate" => aggregate} <- progress,
         true <- map_size(progress) == 3 and is_map(intents) and is_map(outcomes) do
      round = %__MODULE__{
        owner: owner,
        key: key,
        collection: collection,
        dependencies: dependencies,
        intents: intents,
        outcomes: outcomes,
        aggregate: aggregate
      }

      if valid_progress?(round), do: {:ok, round}, else: {:error, :corrupt_caller_round}
    else
      _invalid -> {:error, :corrupt_caller_round}
    end
  end

  def restore(_owner, _key, _collection, _manifest, _progress),
    do: {:error, :corrupt_caller_round}

  @doc false
  def summary(round) do
    Map.new(round.dependencies, fn d ->
      {d.slot,
       %{
         "intent_id" => Map.fetch!(round.intents, d.slot),
         "outcome" => Map.fetch!(round.outcomes, d.slot)
       }}
    end)
  end

  @doc false
  def ready?(round), do: map_size(round.outcomes) == length(round.dependencies)

  defp valid_progress?(round) do
    slots = Enum.map(round.dependencies, & &1.slot)

    bindings_valid =
      Enum.all?(round.intents, fn {slot, id} ->
        slot in slots and Identity.valid_text?(id)
      end)

    results_valid =
      Enum.all?(round.outcomes, fn {slot, outcome} ->
        Map.has_key?(round.intents, slot) and
          valid_outcome?(outcome, round.collection, round.intents[slot])
      end)

    bindings_valid and results_valid and
      (is_nil(round.aggregate) or (ready?(round) and round.aggregate === summary(round)))
  end

  @doc false
  def valid_outcome?(
        %Outcome{kind: :cancelled, execution_id: nil, report_identity: nil} = o,
        _collection,
        _id
      ),
      do: Value.validate(o.value) == :ok

  def valid_outcome?(
        %Outcome{kind: kind, execution_id: execution, report_identity: {source, report_id}} = o,
        collection,
        id
      )
      when kind in [:succeeded, :failed] do
    Identity.valid_text?(execution) and Identity.valid_text?(report_id) and
      source_scope?(source, collection, id, execution) and Value.validate(o.value) == :ok
  end

  def valid_outcome?(_outcome, _collection, _id), do: false

  defp source_scope?(%Token{collection: c, intent_id: i, execution_id: e}, c, i, e), do: true
  defp source_scope?(%Source{collection: c, intent_id: i, execution_id: e}, c, i, e), do: true
  defp source_scope?(_source, _collection, _id, _execution), do: false

  defp unpack(manifest) do
    Enum.reduce_while(manifest, {:ok, []}, fn value, {:ok, dependencies} ->
      case Dependency.unpack(value) do
        {:ok, dependency} -> {:cont, {:ok, dependencies ++ [dependency]}}
        error -> {:halt, error}
      end
    end)
  end
end
