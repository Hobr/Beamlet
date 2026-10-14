defmodule Beamlet.Agent.Caller.Store do
  @moduledoc false
  alias Beamlet.Agent.Caller.{Dependency, Repo, Round, Schema}
  alias BeamletRuntime.Storage.Codec
  alias Ecto.Adapters.SQL

  @max_bytes 16 * 1024 * 1024

  def start_link(opts) do
    database = Keyword.fetch!(opts, :database)

    if not is_binary(database) or database in ["", ":memory:"],
      do: raise(ArgumentError, "persistent caller database required")

    File.mkdir_p!(Path.dirname(Path.expand(database)))

    opts =
      Keyword.merge(opts,
        journal_mode: :wal,
        synchronous: :full,
        foreign_keys: :on,
        default_transaction_mode: :immediate,
        log: false
      )

    Repo.start_link(Keyword.put_new(opts, :name, nil))
  end

  def child_spec(opts),
    do: %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }

  def migrate(repo) do
    with_repo(repo, fn ->
      Ecto.Migrator.run(Repo, [{1, Schema}], :up, all: true, log: false)
      :ok
    end)
  end

  def open(caller, key, dependencies) do
    round = %Round{
      owner: caller.owner,
      key: key,
      collection: caller.coordinator.collection,
      dependencies: dependencies
    }

    transaction(caller.repo, fn -> create_or_get(caller, round) end)
  end

  defp create_or_get(caller, round) do
    case lookup(caller, round.key) do
      nil ->
        sql(
          "INSERT INTO caller_rounds(owner,round_key,collection,manifest,progress) VALUES(?,?,?,?,?)",
          [
            round.owner,
            round.key,
            round.collection,
            encode(Enum.map(round.dependencies, &Dependency.pack/1)),
            encode(Round.progress(round))
          ]
        )

        round

      saved ->
        if saved.dependencies !== round.dependencies,
          do: Repo.rollback(:round_definition_conflict)

        saved
    end
  end

  def read(caller, key), do: transaction(caller.repo, fn -> fetch(caller, key) end, :deferred)

  def discover(caller, cursor, limit) do
    transaction(
      caller.repo,
      fn ->
        sql(
          "SELECT round_key FROM caller_rounds WHERE owner=? AND collection=? AND round_key>? ORDER BY round_key COLLATE BINARY LIMIT ?",
          [caller.owner, caller.coordinator.collection, cursor, limit]
        ).rows
        |> Enum.map(fn [key] -> key end)
      end,
      :deferred
    )
  end

  def bind(caller, key, slot, id) do
    update(caller, key, fn round ->
      dependency!(round, slot)

      case Map.get(round.intents, slot) do
        nil -> %{round | intents: Map.put(round.intents, slot, id)}
        ^id -> round
        _different -> Repo.rollback(:intent_binding_conflict)
      end
    end)
  end

  def observe(caller, key, slot, id, outcome) do
    update(caller, key, fn round ->
      dependency!(round, slot)
      if round.intents[slot] !== id, do: Repo.rollback(:intent_binding_conflict)

      if not Round.valid_outcome?(outcome, round.collection, id),
        do: Repo.rollback(:invalid_outcome)

      case Map.get(round.outcomes, slot) do
        nil -> %{round | outcomes: Map.put(round.outcomes, slot, outcome)}
        ^outcome -> round
        _different -> Repo.rollback(:outcome_conflict)
      end
    end)
  end

  def complete(caller, key) do
    update(caller, key, fn round ->
      if is_nil(round.aggregate) and Round.ready?(round),
        do: %{round | aggregate: Round.summary(round)},
        else: round
    end)
  end

  defp update(caller, key, apply) do
    transaction(caller.repo, fn ->
      saved = fetch(caller, key)
      changed = apply.(saved)

      if changed !== saved do
        sql(
          "UPDATE caller_rounds SET progress=? WHERE owner=? AND round_key=?",
          [encode(Round.progress(changed)), caller.owner, key]
        )
      end

      changed
    end)
  end

  defp dependency!(round, slot) do
    unless Enum.any?(round.dependencies, &(&1.slot == slot)), do: Repo.rollback(:unknown_slot)
  end

  defp fetch(caller, key), do: lookup(caller, key) || Repo.rollback(:round_not_found)

  defp lookup(caller, key) do
    case sql(
           "SELECT collection,manifest,progress FROM caller_rounds WHERE owner=? AND round_key=?",
           [caller.owner, key]
         ).rows do
      [] ->
        nil

      [[collection, manifest, progress]] ->
        if collection !== caller.coordinator.collection,
          do: Repo.rollback(:round_collection_mismatch)

        case Round.restore(caller.owner, key, collection, decode(manifest), decode(progress)) do
          {:ok, round} -> round
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp encode(value) do
    encoded = Codec.encode(value)
    if byte_size(encoded) > @max_bytes, do: Repo.rollback(:caller_capacity_exceeded)
    encoded
  end

  defp decode(bytes) when byte_size(bytes) <= @max_bytes do
    case Codec.decode(bytes) do
      {:ok, value} -> value
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp decode(_bytes), do: Repo.rollback(:caller_capacity_exceeded)

  defp transaction(repo, fun, mode \\ :immediate) do
    with_repo(repo, fn -> Repo.transaction(fun, mode: mode, log: false) end)
  rescue
    _error in [Exqlite.Error, DBConnection.ConnectionError] ->
      {:error, :caller_commit_indeterminate}

    error in [RuntimeError, ArgumentError] ->
      if repo_lookup_failure?(__STACKTRACE__),
        do: {:error, :caller_store_unavailable},
        else: reraise(error, __STACKTRACE__)
  catch
    :exit, _reason -> {:error, :caller_commit_indeterminate}
  end

  defp repo_lookup_failure?(trace) do
    Enum.any?(trace, fn
      {Ecto.Repo.Registry, :lookup, _, _} -> true
      _frame -> false
    end)
  end

  defp with_repo(repo, fun) do
    previous = Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp sql(statement, params),
    do: SQL.query!(Repo.get_dynamic_repo(), statement, params, log: false)
end
