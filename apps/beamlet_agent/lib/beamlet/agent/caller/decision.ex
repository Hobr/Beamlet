defmodule Beamlet.Agent.Caller.Decision do
  @moduledoc """
  Immutable single-success continuation record, identified by owner/computation/key.
  The consumed Outcome, rule, choice and one successor request survive restarts.
  Only the committed record may be used to register/submit the successor.
  """
  alias Beamlet.Agent.Caller.{Dependency, Round}
  alias Beamlet.{Identity, Outcome, Value}

  @enforce_keys [
    :owner,
    :collection,
    :computation,
    :key,
    :source_round,
    :source_slot,
    :rule,
    :intent_id,
    :outcome,
    :value,
    :next_round,
    :dependency
  ]
  defstruct @enforce_keys

  @doc false
  def new(caller, computation, key, round, slot, rule, proposal) do
    with %Outcome{kind: :succeeded} = outcome <- round.outcomes[slot],
         %{value: value, next_round: next, dependency: dependency} <- proposal,
         true <- map_size(proposal) == 3,
         {:ok, [^dependency]} <- Dependency.manifest([dependency], round.collection),
         true <- Identity.valid_text?(next) and next != round.key,
         true <- dependency.definition.input === outcome.value,
         true <- Enum.all?(round.dependencies, &(&1.identity !== dependency.identity)),
         :ok <- Value.validate(value) do
      {:ok,
       %__MODULE__{
         owner: caller.owner,
         collection: round.collection,
         computation: computation,
         key: key,
         source_round: round.key,
         source_slot: slot,
         rule: rule,
         intent_id: round.intents[slot],
         outcome: outcome,
         value: value,
         next_round: next,
         dependency: dependency
       }}
    else
      _invalid -> {:error, :invalid_continuation}
    end
  end

  @doc false
  def source_matches?(decision, round) do
    decision.source_round == round.key and decision.owner == round.owner and
      decision.collection == round.collection and
      round.intents[decision.source_slot] === decision.intent_id and
      round.outcomes[decision.source_slot] === decision.outcome and
      match?(%Outcome{kind: :succeeded}, decision.outcome) and
      Round.valid_outcome?(decision.outcome, decision.collection, decision.intent_id) and
      Enum.any?(round.dependencies, &(&1.slot == decision.source_slot)) and
      Enum.all?(round.dependencies, &(&1.identity !== decision.dependency.identity))
  end

  @doc false
  def pack(decision) do
    decision
    |> Map.from_struct()
    |> Map.new(fn
      {:dependency, d} -> {"dependency", Dependency.pack(d)}
      {field, value} -> {Atom.to_string(field), value}
    end)
  end

  @doc false
  def restore(caller, computation, key, payload) when is_map(payload) do
    expected = Enum.map(@enforce_keys, &Atom.to_string/1)

    with true <- Enum.sort(Map.keys(payload)) == Enum.sort(expected),
         true <-
           payload["owner"] == caller.owner and
             payload["collection"] == caller.coordinator.collection,
         true <- payload["computation"] == computation and payload["key"] == key,
         true <-
           Enum.all?(
             ["source_round", "source_slot", "rule", "intent_id", "next_round"],
             &Identity.valid_text?(payload[&1])
           ),
         {:ok, dependency} <- Dependency.unpack(payload["dependency"]),
         {:ok, [^dependency]} <- Dependency.manifest([dependency], payload["collection"]),
         %Outcome{kind: :succeeded} = outcome <- payload["outcome"],
         true <- Round.valid_outcome?(outcome, payload["collection"], payload["intent_id"]),
         true <-
           dependency.definition.input === outcome.value and
             payload["source_round"] != payload["next_round"],
         :ok <- Value.validate(payload["value"]) do
      fields = Map.new(@enforce_keys, &{&1, payload[Atom.to_string(&1)]})
      {:ok, struct!(__MODULE__, Map.put(fields, :dependency, dependency))}
    else
      _invalid -> {:error, :corrupt_caller_decision}
    end
  end

  def restore(_caller, _computation, _key, _payload), do: {:error, :corrupt_caller_decision}
end
