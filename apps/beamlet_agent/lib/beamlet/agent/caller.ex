defmodule Beamlet.Agent.Caller.Error do
  @moduledoc "Caller progress failed, not a Failed Outcome. Retry the original round identity."
  @enforce_keys [:stage, :reason]
  defstruct [:stage, :reason, :slot]
end

defmodule Beamlet.Agent.Caller do
  @moduledoc """
  Durable local await-all composition, outside Beamlet's effect ledger.

  open saves an immutable, nonempty manifest before any submission. advance sends
  only original stable identities, associates replies by slot, reads committed
  facts, and saves full Outcomes. Unknown/Pending leave the round incomplete.
  Completed aggregates can be read without contacting Authority. Failures preserve
  partial progress; retry the original owner/key, never generate replacement keys.

  A configured Coordinator is a trusted local capability, not remote credentials.
  Use a separate persistent caller database and retain the same authority history.
  No cross-database transaction, automatic cancellation, call-stack recovery,
  continuation decisions or exactly-once subsequent caller effects are provided.
  """
  alias Beamlet.Agent.Caller.{Dependency, Error, Store}
  alias Beamlet.{Definition, Identity}
  alias BeamletRuntime.Coordinator

  @enforce_keys [:repo, :coordinator, :owner]
  defstruct @enforce_keys

  defdelegate start_link(opts), to: Store
  defdelegate child_spec(opts), to: Store
  defdelegate migrate(repo), to: Store

  def new(repo, %Coordinator{} = coordinator, owner) do
    unless Identity.valid_text?(owner), do: raise(ArgumentError, "invalid caller owner")
    %__MODULE__{repo: repo, coordinator: coordinator, owner: owner}
  end

  @doc "Durably create-or-get a round. Entry order is irrelevant; slot identity is explicit."
  def open(caller, key, dependencies) do
    with :ok <- validate_key(key),
         {:ok, manifest} <- Dependency.manifest(dependencies, caller.coordinator.collection),
         do: Store.open(caller, key, manifest)
  end

  @doc "Read only caller-local committed progress. Does not submit or manufacture results."
  def read(caller, key) do
    with :ok <- validate_key(key), do: Store.read(caller, key)
  end

  @doc "Discover saved round keys without relying on a living caller's memory. Candidates do not imply completion."
  def discover(caller, after_key \\ "", limit \\ 100) do
    if (after_key == "" or Identity.valid_text?(after_key)) and is_integer(limit) and
         limit in 1..1000,
       do: Store.discover(caller, after_key, limit),
       else: {:error, :invalid_round_page}
  end

  @doc "One bounded recovery pass. Execution remains Runtime/Scheduler's responsibility."
  def advance(caller, key) do
    with {:ok, round} <- read(caller, key) do
      if is_nil(round.aggregate), do: advance_round(caller, round), else: {:ok, round}
    end
  end

  defp advance_round(caller, round) do
    result =
      Enum.reduce_while(round.dependencies, :ok, fn dependency, :ok ->
        advance_slot(caller, round, dependency)
      end)

    with :ok <- result, do: Store.complete(caller, round.key)
  end

  defp advance_slot(caller, round, dependency) do
    result =
      if Map.has_key?(round.outcomes, dependency.slot),
        do: :ok,
        else: advance_dependency(caller, round, dependency)

    case result do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp advance_dependency(caller, round, dependency) do
    with {:ok, id} <- resolve(caller, round, dependency),
         {:ok, facts} <- stage(Coordinator.read(caller.coordinator, id), :read, dependency.slot),
         :ok <- matching_facts(facts.intent, dependency, id),
         do: save_outcome(caller, round.key, dependency.slot, facts.intent)
  end

  defp resolve(caller, round, dependency) do
    case Map.get(round.intents, dependency.slot) do
      nil ->
        with {:ok, commit} <-
               stage(
                 Coordinator.submit(
                   caller.coordinator,
                   dependency.identity,
                   dependency.definition
                 ),
                 :submit,
                 dependency.slot
               ),
             id = commit.facts.intent.id,
             :ok <- matching_facts(commit.facts.intent, dependency, id),
             {:ok, _round} <-
               stage(
                 Store.bind(caller, round.key, dependency.slot, id),
                 :persist,
                 dependency.slot
               ),
             do: {:ok, id}

      id ->
        {:ok, id}
    end
  end

  defp matching_facts(intent, dependency, id) do
    valid =
      intent.id == id and intent.identity === dependency.identity and
        Definition.equal?(intent.definition, dependency.definition) and
        ((intent.phase == :open and is_nil(intent.outcome)) or
           (intent.phase == :closed and not is_nil(intent.outcome)))

    if valid,
      do: :ok,
      else:
        {:error, %Error{stage: :read, slot: dependency.slot, reason: :authority_facts_mismatch}}
  end

  defp save_outcome(_caller, _key, _slot, %{outcome: nil}), do: :ok

  defp save_outcome(caller, key, slot, intent) do
    with {:ok, _round} <-
           stage(Store.observe(caller, key, slot, intent.id, intent.outcome), :persist, slot),
         do: :ok
  end

  defp stage({:ok, value}, _stage, _slot), do: {:ok, value}

  defp stage({:error, reason}, stage, slot),
    do: {:error, %Error{stage: stage, slot: slot, reason: reason}}

  defp validate_key(key) do
    if Identity.valid_text?(key), do: :ok, else: {:error, :invalid_round_key}
  end
end
