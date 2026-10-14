defmodule BeamletRuntime.Storage.SQLite do
  @moduledoc """
  Real SQLite ledger with BEGIN IMMEDIATE writes and FULL/WAL durability settings.

  This is an internal trusted Adapter API. Runtime authenticates principals,
  authorizes each operation, and verifies Handler/report inputs before calling it.
  Authority time is sampled in SQL after acquiring transaction protection. An
  optional contract_clock is a trusted, bounded local resource-clock reader, never
  a client assertion or network request. All external effects remain outside SQL.

  Busy BEGIN failures receive bounded retries. A failure after transaction entry
  is conservatively Indeterminate; callers recover by stable identities, never by
  repeating an external call. A durable expiry rejection returns a Commit.
  """
  alias Beamlet.{Definition, Domain, Identity, Intent, Transition}
  alias BeamletRuntime.Storage.{Codec, Commit, Error, Facts}
  alias BeamletRuntime.Storage.SQLite.{Repo, Schema}
  alias Ecto.Adapters.SQL

  @clock "CAST(strftime('%s','now') AS INTEGER)*1000 + CAST(substr(strftime('%f','now'),4,3) AS INTEGER)"
  @max_revision 9_223_372_036_854_775_807
  @max_snapshot_bytes 16_777_216

  def start_link(opts) do
    database = Keyword.fetch!(opts, :database)

    if not is_binary(database) or database in ["", ":memory:"],
      do: raise(ArgumentError, "persistent database path required")

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
    with_repo(repo, fn -> Ecto.Migrator.run(Repo, [{1, Schema}], :up, all: true, log: false) end)
    :ok
  end

  @doc "Trusted optional definition_validator runs only for new identities under protection; replays compare the original definition. It must be a bounded local schema check."
  def submit(repo, %Identity{} = identity, %Definition{} = definition, actor, opts \\ []) do
    opts = Keyword.delete(opts, :mode)

    with {:ok, ^identity} <- Identity.new(identity.collection, identity.namespace, identity.key),
         {:ok, ^definition} <- Definition.new(Map.from_struct(definition)),
         :ok <- validate_scope(identity.collection, actor) do
      id = Ecto.UUID.generate()

      transaction(repo, fn -> submit_intent(id, identity, definition, actor, opts) end, opts)
    end
  end

  def command(repo, collection, id, command, actor, opts \\ []) do
    opts = Keyword.delete(opts, :mode)

    with :ok <- validate_scope(collection, id), true <- Identity.valid_text?(actor) do
      transaction(
        repo,
        fn -> apply_command(fetch_facts(collection, id), command, actor, opts) end,
        opts
      )
    else
      false -> {:error, :invalid_actor}
      error -> error
    end
  end

  @doc "Trusted Runtime hook: bounded local validation and command selection under the write lock. Never perform external effects here."
  def checked_command(repo, collection, id, actor, prepare, opts \\ [])
      when is_function(prepare, 2) do
    opts = Keyword.delete(opts, :mode)

    with :ok <- validate_scope(collection, id), true <- Identity.valid_text?(actor) do
      transaction(
        repo,
        fn ->
          prepare_command(fetch_facts(collection, id), context(actor, opts), prepare)
        end,
        opts
      )
    else
      false -> {:error, :invalid_actor}
      error -> error
    end
  end

  defp prepare_command(facts, context, prepare) do
    case prepare.(facts.intent, context) do
      {:ok, command} -> decide(facts, command, context)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def read(repo, collection, id) do
    with :ok <- validate_scope(collection, id) do
      transaction(repo, fn -> fetch_facts(collection, id) end, mode: :deferred)
    end
  end

  @doc "Immutable History page bounded by the revision returned from read/3. Cursor is {revision, position}."
  def history(repo, collection, id, revision, cursor \\ {0, 0}, limit \\ 100) do
    with :ok <- validate_scope(collection, id),
         true <- is_integer(revision) and revision > 0 and valid_page?(cursor, limit) do
      transaction(repo, fn -> history_page(collection, id, revision, cursor, limit) end,
        mode: :deferred
      )
    else
      false -> {:error, :invalid_page}
      error -> error
    end
  end

  @doc "Candidates convey no permission. Restart scans from the beginning periodically; mutable work can move behind a cursor."
  def discover(repo, collection, after_id \\ "", limit \\ 100) do
    if Identity.valid_text?(collection) and (after_id == "" or Identity.valid_text?(after_id)) and
         valid_limit?(limit) do
      transaction(repo, fn -> discover_page(collection, after_id, limit) end, mode: :deferred)
    else
      {:error, :invalid_page}
    end
  end

  defp submit_intent(id, identity, definition, actor, opts) do
    case keyed_facts(identity) do
      nil ->
        create_intent(id, identity, definition, actor, opts)

      facts ->
        case Domain.resubmit(facts.intent, identity, definition) do
          {:ok, _intent} -> %Commit{facts: facts, reply: {:existing, facts.intent.id}, events: []}
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp create_intent(id, identity, definition, actor, opts) do
    with :ok <- validate_definition(definition, opts),
         {:ok, transition} <- Domain.new_intent(id, identity, definition, context(actor, opts)) do
      persist(nil, transition)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp validate_definition(definition, opts) do
    case Keyword.get(opts, :definition_validator) do
      nil ->
        :ok

      validator when is_function(validator, 1) ->
        validate_definition_reply(validator.(definition))

      _invalid ->
        {:error, :invalid_definition_validator}
    end
  end

  defp validate_definition_reply(:ok), do: :ok
  defp validate_definition_reply({:error, _reason} = error), do: error
  defp validate_definition_reply(_invalid), do: {:error, :invalid_definition_validator_reply}

  defp apply_command(facts, command, actor, opts),
    do: decide(facts, command, context(actor, opts))

  defp decide(facts, command, context) do
    case Domain.transition(facts.intent, command, context) do
      {:ok, transition} -> persist(facts, transition)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp history_page(collection, id, revision, {group, position}, limit) do
    rows =
      query(
        """
        SELECT revision, position, event FROM beamlet_history
        WHERE collection=? AND intent_id=? AND revision<=? AND (revision>? OR (revision=? AND position>?))
        ORDER BY revision, position LIMIT ?
        """,
        [collection, id, revision, group, group, position, limit + 1]
      ).rows

    entries =
      rows
      |> Enum.take(limit)
      |> Enum.map(fn [r, p, bytes] ->
        %{revision: r, position: p, event: decode!(bytes)}
      end)

    next = if length(rows) > limit, do: {List.last(entries).revision, List.last(entries).position}
    %{entries: entries, next: next}
  end

  defp discover_page(collection, after_id, limit) do
    rows =
      query(
        """
        SELECT id, current_id, current_phase FROM beamlet_intents
        WHERE collection=? AND id>? AND phase='open' AND
          (current_id IS NULL OR current_phase IN ('prepared','start_authorized','waiting','unknown','resolved'))
        ORDER BY id LIMIT ?
        """,
        [collection, after_id, limit]
      ).rows

    Enum.map(rows, fn [id, execution_id, phase] ->
      %{intent_id: id, execution_id: execution_id, phase: phase}
    end)
  end

  defp keyed_facts(%Identity{key: nil}), do: nil

  defp keyed_facts(identity) do
    case query(
           "SELECT snapshot,revision FROM beamlet_intents WHERE collection=? AND namespace=? AND submission_key=?",
           [identity.collection, identity.namespace, identity.key]
         ).rows do
      [] -> nil
      [[bytes, revision]] -> facts(bytes, revision)
    end
  end

  defp fetch_facts(collection, id) do
    case query("SELECT snapshot,revision FROM beamlet_intents WHERE collection=? AND id=?", [
           collection,
           id
         ]).rows do
      [[bytes, revision]] ->
        facts = facts(bytes, revision)

        if facts.intent.id != id or facts.intent.identity.collection != collection,
          do: Repo.rollback(:corrupt_snapshot)

        facts

      [] ->
        Repo.rollback(:intent_not_found)
    end
  end

  defp facts(bytes, revision) do
    case decode!(bytes) do
      %Intent{} = intent -> %Facts{intent: intent, revision: revision}
      _ -> Repo.rollback(:corrupt_snapshot)
    end
  end

  defp persist(
         %Facts{intent: intent} = facts,
         %Transition{intent: intent, events: []} = transition
       ),
       do: %Commit{facts: facts, reply: transition.reply, events: []}

  defp persist(previous, transition) do
    old_revision = if previous, do: previous.revision, else: 0
    if old_revision >= @max_revision, do: Repo.rollback(:storage_revision_exhausted)
    revision = old_revision + 1
    intent = transition.intent
    bytes = Codec.encode(intent)
    if byte_size(bytes) > @max_snapshot_bytes, do: Repo.rollback(:snapshot_capacity_exceeded)
    write_snapshot(previous, intent, bytes, revision)

    if intent.outcome && (is_nil(previous) or is_nil(previous.intent.outcome)) do
      query(
        "INSERT INTO beamlet_outcomes(collection,intent_id,outcome) VALUES(?,?,?)",
        [intent.identity.collection, intent.id, Codec.encode(intent.outcome)]
      )
    end

    Enum.with_index(transition.events, 1)
    |> Enum.each(fn {event, position} ->
      query(
        "INSERT INTO beamlet_history(collection,intent_id,revision,position,event) VALUES(?,?,?,?,?)",
        [intent.identity.collection, intent.id, revision, position, Codec.encode(event)]
      )
    end)

    %Commit{
      facts: %Facts{intent: intent, revision: revision},
      reply: transition.reply,
      events: transition.events
    }
  end

  defp write_snapshot(previous, intent, bytes, revision) do
    execution = intent.executions[intent.current_execution_id]

    values = [
      bytes,
      Atom.to_string(intent.phase),
      intent.current_execution_id,
      if(execution, do: Atom.to_string(execution.phase)),
      if(execution && execution.lease, do: execution.lease.expires_at),
      revision
    ]

    if previous do
      result =
        query(
          "UPDATE beamlet_intents SET snapshot=?,phase=?,current_id=?,current_phase=?,lease_expires_at=?,revision=? WHERE collection=? AND id=? AND revision=?",
          values ++ [intent.identity.collection, intent.id, previous.revision]
        )

      if result.num_rows != 1, do: Repo.rollback(:stale_facts)
    else
      query(
        "INSERT INTO beamlet_intents(collection,id,namespace,submission_key,snapshot,phase,current_id,current_phase,lease_expires_at,revision) VALUES(?,?,?,?,?,?,?,?,?,?)",
        [intent.identity.collection, intent.id, intent.identity.namespace, intent.identity.key] ++
          values
      )
    end
  end

  defp context(actor, opts) do
    [[now]] = query("SELECT #{@clock}", []).rows
    context = %{now: now, actor: actor}

    case Keyword.get(opts, :contract_clock) do
      nil -> context
      clock when is_function(clock, 0) -> Map.put(context, :contract_time, clock.())
    end
  end

  defp decode!(bytes) when byte_size(bytes) <= @max_snapshot_bytes do
    case Codec.decode(bytes) do
      {:ok, value} -> value
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp decode!(_bytes), do: Repo.rollback(:snapshot_capacity_exceeded)

  defp transaction(repo, fun, opts, attempt \\ 0) do
    with_repo(repo, fn ->
      marker = make_ref()
      Process.put(marker, false)

      try do
        Repo.transaction(
          fn ->
            Process.put(marker, true)
            fun.()
          end,
          mode: Keyword.get(opts, :mode, :immediate),
          timeout: Keyword.get(opts, :timeout, 5_000),
          log: false
        )
      rescue
        error in [Exqlite.Error, DBConnection.ConnectionError] ->
          storage_failure(repo, fun, opts, attempt, Process.get(marker), error)

        error in [RuntimeError, ArgumentError] ->
          if repo_lookup_failure?(__STACKTRACE__),
            do: storage_failure(repo, fun, opts, attempt, Process.get(marker), error),
            else: reraise(error, __STACKTRACE__)
      catch
        :exit, reason ->
          {:error,
           %Error{
             kind: if(Process.get(marker), do: :indeterminate, else: :unavailable),
             cause: reason
           }}
      after
        Process.delete(marker)
      end
    end)
  end

  defp repo_lookup_failure?(trace) do
    Enum.any?(trace, fn
      {Ecto.Repo.Registry, :lookup, _arity, _location} -> true
      _frame -> false
    end)
  end

  defp storage_failure(repo, fun, opts, attempt, entered, error) do
    busy =
      match?(
        %Exqlite.Error{message: message}
        when message in ["Database busy", "database is locked", "database is busy"],
        error
      )

    cond do
      busy and not entered and attempt < Keyword.get(opts, :retries, 2) ->
        transaction(repo, fun, opts, attempt + 1)

      busy and not entered ->
        {:error, %Error{kind: :busy_exhausted, cause: error}}

      entered ->
        {:error, %Error{kind: :indeterminate, cause: error}}

      true ->
        {:error, %Error{kind: :unavailable, cause: error}}
    end
  end

  defp with_repo(repo, fun) do
    previous = Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp query(sql, params),
    do: SQL.query!(Repo.get_dynamic_repo(), sql, params, log: false)

  defp validate_scope(collection, id) do
    if Identity.valid_text?(collection) and Identity.valid_text?(id),
      do: :ok,
      else: {:error, :invalid_scope}
  end

  defp valid_page?({group, position}, limit),
    do:
      is_integer(group) and group >= 0 and is_integer(position) and position >= 0 and
        valid_limit?(limit)

  defp valid_page?(_cursor, _limit), do: false
  defp valid_limit?(limit), do: is_integer(limit) and limit in 1..1000
end
