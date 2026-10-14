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
  arbitrary continuation loops or exactly-once subsequent caller effects are provided.
  Single-success decisions are saved before their successor manifest and submission.
  """
  alias Beamlet.Agent.Caller.{Decision, Dependency, Error, Store}
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

  @doc """
  Save one continuation decision from a collected Success. opts must contain
  source_round, source_slot and rule. planner receives the full Outcome and returns
  {:ok, %{value: restricted_value, next_round: key, dependency: Dependency}}.
  Successor input must equal the consumed value, as in the Quint one-step profile.
  First committed decision wins: replay never calls planner or replaces that record.
  Planner runs outside SQL and should only compute a proposal, never send effects.
  """
  def decide(caller, computation, key, opts, planner) do
    with :ok <- decision_scope(computation, key) do
      case Store.decision(caller, computation, key) do
        {:ok, saved} -> {:ok, saved}
        {:error, :decision_not_found} -> propose_decision(caller, computation, key, opts, planner)
        error -> error
      end
    end
  end

  @doc "Read the immutable decision without running a planner or contacting Authority."
  def read_decision(caller, computation, key) do
    with :ok <- decision_scope(computation, key), do: Store.decision(caller, computation, key)
  end

  @doc "Create-or-get the successor manifest from a committed decision; does not send C."
  def register_next(caller, computation, key) do
    with :ok <- decision_scope(computation, key),
         do: Store.register_next(caller, computation, key)
  end

  @doc "Recover the original successor manifest, then submit/read using its saved identity."
  def advance_next(caller, computation, key) do
    with {:ok, round} <- register_next(caller, computation, key), do: advance(caller, round.key)
  end

  @doc "Find committed steps, including decisions whose successor manifest is not yet created."
  def discover_decisions(caller, computation, cursor \\ "", limit \\ 100) do
    if Identity.valid_text?(computation) and (cursor == "" or Identity.valid_text?(cursor)) and
         is_integer(limit) and limit in 1..1000,
       do: Store.discover_decisions(caller, computation, cursor, limit),
       else: {:error, :invalid_decision_page}
  end

  defp propose_decision(caller, computation, key, opts, planner) do
    with :ok <- validate_decision_options(opts, planner),
         {:ok, round} <- read(caller, opts[:source_round]),
         :ok <- source_success(round, opts[:source_slot]),
         {:ok, proposal} <- plan(planner, round.outcomes[opts[:source_slot]]),
         {:ok, decision} <-
           Decision.new(
             caller,
             computation,
             key,
             round,
             opts[:source_slot],
             opts[:rule],
             proposal
           ),
         do: Store.commit_decision(caller, decision)
  end

  defp source_success(round, slot) do
    cond do
      not Enum.any?(round.dependencies, &(&1.slot == slot)) -> {:error, :unknown_slot}
      is_nil(round.outcomes[slot]) -> {:error, :source_not_collected}
      round.outcomes[slot].kind != :succeeded -> {:error, :source_not_succeeded}
      true -> :ok
    end
  end

  defp plan(planner, outcome) do
    case planner.(outcome) do
      {:ok, proposal} -> {:ok, proposal}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_planner_reply}
    end
  rescue
    _exception -> {:error, :planner_failed}
  catch
    _kind, _reason -> {:error, :planner_failed}
  end

  defp validate_decision_options(opts, planner) when is_list(opts) do
    valid =
      Keyword.keyword?(opts) and
        Enum.sort(Keyword.keys(opts)) == [:rule, :source_round, :source_slot] and
        Enum.all?(opts, fn {_key, value} -> Identity.valid_text?(value) end) and
        is_function(planner, 1)

    if valid, do: :ok, else: {:error, :invalid_decision_options}
  end

  defp validate_decision_options(_opts, _planner), do: {:error, :invalid_decision_options}

  defp decision_scope(computation, key) do
    if Identity.valid_text?(computation) and Identity.valid_text?(key),
      do: :ok,
      else: {:error, :invalid_decision_scope}
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
