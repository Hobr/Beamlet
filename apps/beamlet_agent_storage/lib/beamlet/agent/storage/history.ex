defmodule Beamlet.Agent.Storage.History do
  @moduledoc """
  Read-only queries over committed authority facts. Nothing here starts an Agent,
  consults a coordinator or depends on Runtime retention; the current runtime
  observation stays with Runtime/Node and is deliberately not part of this module.

  Pages are keyset-paginated as one bounded statement each, with no enclosing read transaction and bounded by
  a row count plus a byte budget. A page never splits a record: a record larger
  than the byte budget is returned alone with `over_budget: true` and stays
  bounded by its own codec limit. Checkpoints bind an explicit `through_seq`;
  `checkpoint_at/3` verifies the optional cache and returns nil for corrupt data.
  """

  import Ecto.Query
  alias Beamlet.Actions.Storage.Schema.Execution
  alias Beamlet.Actions.Storage.Schema.ExecutionEvidence
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.Events
  alias Beamlet.Agent.Storage.Read
  alias Beamlet.Agent.Storage.Records
  alias Beamlet.Agent.Storage.Schema.Checkpoint
  alias Beamlet.Agent.Storage.Schema.Event
  alias Beamlet.Agent.Storage.Schema.Operation
  @page_default 100
  @page_max 500
  @page_bytes 4_194_304
  @min_bytes 4_096
  @view_max 50

  @doc """
  Bounded event page for one scope, optionally capped at a fixed high-water
  sequence and filtered by type/turn/operation/origin. `origin` distinguishes
  records this scope performed from records inherited with a source marker.
  """
  def event_page(repo, scope_id, opts \\ []) do
    with {:ok, scope} <- Records.uuid(scope_id),
         {:ok, filters} <- event_filters(opts) do
      Read.read(fn -> read_events(repo, scope, filters) end)
    end
  end

  @doc "One recorded event by scope and sequence, `:conflict` when absent."
  def event(repo, scope_id, seq) do
    with {:ok, scope} <- Records.uuid(scope_id),
         {:ok, seq} <- Records.count(seq) do
      Read.read(fn -> read_event(repo, scope, seq) end)
    end
  end

  defp read_event(repo, scope, seq) do
    query =
      from(e in Event,
        where: e.scope_id == ^scope and e.seq == ^seq,
        select: %{event: e}
      )

    case repo.one(query, log: false) do
      nil -> {:error, :conflict}
      %{event: event} -> {:ok, Records.plain(event)}
    end
  end

  def operation_event(repo, id, seq) do
    Read.read(fn ->
      query =
        from(e in Beamlet.Actions.Storage.Schema.OperationEvent,
          where: e.operation_id == ^id and e.seq == ^seq,
          select: %{event: e}
        )

      case repo.one(query, log: false) do
        nil ->
          {:error, :conflict}

        %{event: event} ->
          {:ok, event |> Records.plain() |> Map.delete("operation_id") |> Map.put("scope_id", id)}
      end
    end)
  end

  @doc """
  The optional control cache as of `seq`, selected by explicit `through_seq`.
  Missing or corrupt caches return nil so a loader can reduce raw history.
  `nil` selects the newest cache.
  """
  def checkpoint_at(repo, agent_id, seq) do
    with {:ok, id} <- Records.uuid(agent_id),
         {:ok, seq} <- optional_seq(seq) do
      Read.read(fn -> read_checkpoint_at(repo, id, seq) end)
    end
  end

  defp read_checkpoint_at(repo, agent_id, seq) do
    query =
      from(c in Checkpoint,
        where: c.agent_id == ^agent_id,
        order_by: [desc: c.through_seq, desc: c.recorded_at, desc: c.id],
        limit: 1,
        select: %{
          id: c.id,
          agent_id: c.agent_id,
          turn_id: c.turn_id,
          through_seq: c.through_seq,
          reducer_version: c.reducer_version,
          digest: c.digest,
          continuation: c.continuation,
          safe_to_fork: c.safe_to_fork,
          schema_version: c.schema_version,
          recorded_at: c.recorded_at,
          raw: fragment("CAST(? AS TEXT)", c.data)
        }
      )

    query = if is_nil(seq), do: query, else: from(c in query, where: c.through_seq <= ^seq)
    checkpoint = repo.one(query, log: false) |> valid_checkpoint()
    {:ok, %{"as_of_seq" => seq, "checkpoint" => checkpoint, "derived_by" => "through_seq"}}
  end

  defp valid_checkpoint(nil), do: nil

  defp valid_checkpoint(checkpoint) do
    with {:ok, data} <- Codec.decode(checkpoint.raw, :checkpoint),
         :ok <- Events.control(data),
         {:ok, digest} <- Codec.digest(data, :checkpoint),
         true <- digest == checkpoint.digest do
      checkpoint |> Map.delete(:raw) |> Map.put(:data, data) |> Records.plain()
    else
      _ -> nil
    end
  end

  @doc """
  Bounded checkpoint page in commit order, optionally capped at a fixed
  high-water timestamp so a later commit cannot enter an already fixed range.
  """
  def checkpoint_page(repo, agent_id, opts \\ []) do
    with {:ok, id} <- Records.uuid(agent_id),
         {:ok, filters} <- checkpoint_filters(opts) do
      Read.read(fn -> read_checkpoints(repo, id, filters) end)
    end
  end

  @doc "Turn summaries ordered by first recorded sequence, keyset on that sequence."
  def turns(repo, agent_id, opts \\ []) do
    with {:ok, id} <- Records.uuid(agent_id),
         {:ok, through} <- optional_seq(Keyword.get(opts, :through_seq)),
         {:ok, after_seq, limit} <-
           list_bounds(Keyword.delete(opts, :through_seq), :after_first_seq) do
      Read.read(fn -> read_turns(repo, id, after_seq, limit, through) end)
    end
  end

  @doc "Owned Operation rows ordered by immutable Agent prepared_seq (cursor after_history_seq)."
  def operations(repo, agent_id, opts \\ []) do
    with {:ok, id} <- Records.uuid(agent_id),
         {:ok, after_seq, limit} <- list_bounds(opts, :after_history_seq) do
      Read.read(fn -> read_operations(repo, id, after_seq, limit) end)
    end
  end

  @doc "One Operation with its attempt and receipt evidence rows."
  def operation(repo, operation_id) do
    with {:ok, id} <- Records.uuid(operation_id) do
      Read.read(fn -> read_operation(repo, id) end)
    end
  end

  defp read_operation(repo, id) do
    case repo.get(Operation, id, log: false) do
      nil ->
        {:error, :conflict}

      operation ->
        attempt = attempt_for(repo, id)

        {:ok,
         %{
           "operation" => Records.plain(operation),
           "attempt" => Records.plain(attempt),
           "evidence" => evidence_rows(repo, id)
         }}
    end
  end

  @doc "Receipt evidence rows for one Operation, newest first, bounded."
  def evidence(repo, operation_id) do
    with {:ok, id} <- Records.uuid(operation_id) do
      Read.read(fn -> bounded_evidence(repo, id) end)
    end
  end

  defp bounded_evidence(repo, id) do
    rows = evidence_rows(repo, id, 33)
    if length(rows) <= 32, do: {:ok, %{"evidence" => rows}}, else: {:error, :limit}
  end

  ## Filters

  defp event_filters(opts) do
    allowed = [
      :after_seq,
      :through_seq,
      :limit,
      :max_bytes,
      :type,
      :types,
      :turn_id,
      :operation_id,
      :origin
    ]

    with true <- is_list(opts) and Keyword.keyword?(opts),
         true <- Enum.all?(Keyword.keys(opts), &(&1 in allowed)),
         {:ok, after_seq} <- seq(Keyword.get(opts, :after_seq, 0)),
         {:ok, through_seq} <- optional_seq(Keyword.get(opts, :through_seq)),
         {:ok, limit} <- bounded(Keyword.get(opts, :limit, @page_default), 1, @page_max),
         {:ok, max_bytes} <-
           bounded(Keyword.get(opts, :max_bytes, @page_bytes), @min_bytes, @page_bytes),
         {:ok, turn_id} <- optional_uuid(Keyword.get(opts, :turn_id)),
         {:ok, operation_id} <- optional_uuid(Keyword.get(opts, :operation_id)),
         {:ok, types} <- types(Keyword.get(opts, :types), Keyword.get(opts, :type)),
         {:ok, origin} <- origin(Keyword.get(opts, :origin)) do
      {:ok,
       %{
         after_seq: after_seq,
         through_seq: through_seq,
         limit: limit,
         max_bytes: max_bytes,
         turn_id: turn_id,
         operation_id: operation_id,
         types: types,
         origin: origin
       }}
    else
      false -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp checkpoint_filters(opts) do
    allowed = [:after, :through_recorded_at, :limit, :max_bytes]

    with true <- is_list(opts) and Keyword.keyword?(opts),
         true <- Enum.all?(Keyword.keys(opts), &(&1 in allowed)),
         {:ok, after_ckpt} <- after_checkpoint(Keyword.get(opts, :after)),
         {:ok, through} <- optional_time(Keyword.get(opts, :through_recorded_at)),
         {:ok, limit} <- bounded(Keyword.get(opts, :limit, @page_default), 1, @page_max),
         {:ok, max_bytes} <-
           bounded(Keyword.get(opts, :max_bytes, @page_bytes), @min_bytes, @page_bytes) do
      {:ok, %{after: after_ckpt, through: through, limit: limit, max_bytes: max_bytes}}
    else
      false -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp after_checkpoint(nil), do: {:ok, nil}

  defp after_checkpoint(%DateTime{} = at), do: {:ok, {at, nil}}

  defp after_checkpoint(%{} = value) do
    value = Map.new(value, fn {key, item} -> {cursor_key(key), item} end)

    with {:ok, _} <- Records.fields(value, [:recorded_at], [:id]),
         {:ok, at} <- optional_time(value[:recorded_at]),
         {:ok, id} <- optional_uuid(value[:id]) do
      case at do
        nil -> {:ok, nil}
        at -> {:ok, {at, id}}
      end
    end
  end

  defp after_checkpoint(_), do: {:error, :invalid_data}

  defp cursor_key(key) when is_atom(key), do: key
  defp cursor_key("recorded_at"), do: :recorded_at
  defp cursor_key("id"), do: :id
  defp cursor_key(_key), do: :invalid

  defp origin(nil), do: {:ok, nil}
  defp origin(value) when value in [:performed, "performed"], do: {:ok, "performed"}
  defp origin(value) when value in [:inherited, "inherited"], do: {:ok, "inherited"}
  defp origin(_), do: {:error, :invalid_data}

  defp list_bounds(opts, key) do
    with true <- is_list(opts) and Keyword.keyword?(opts),
         true <- Enum.all?(Keyword.keys(opts), &(&1 in [key, :limit])),
         {:ok, after_seq} <- seq(Keyword.get(opts, key, 0)),
         {:ok, limit} <- bounded(Keyword.get(opts, :limit, @view_max), 1, @view_max) do
      {:ok, after_seq, limit}
    else
      false -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Reads

  defp read_events(repo, scope, filters) do
    rows = repo.all(event_query(scope, filters), log: false)
    {events, more?} = take_rows(rows, filters.limit, filters.max_bytes, [], 0, & &1.event)

    {:ok,
     %{
       "scope_id" => scope,
       "events" => Enum.map(events, &plain_event(&1, scope)),
       "next_cursor" => if(more? and events != [], do: List.last(events).seq, else: nil),
       "over_budget" => oversized?(rows, filters.max_bytes),
       "through_seq" => filters.through_seq
     }}
  end

  defp event_query(scope, filters) do
    from(e in Event,
      where: e.scope_id == ^scope and e.seq > ^filters.after_seq,
      order_by: [asc: e.seq],
      limit: ^filters.limit,
      select: %{event: e, raw: fragment("CAST(? AS TEXT)", e.payload)}
    )
    |> filter_through(filters.through_seq)
    |> filter_types(filters.types)
    |> filter_turn(filters.turn_id)
    |> filter_operation(filters.operation_id)
    |> filter_origin(filters.origin, scope)
  end

  defp filter_through(query, nil), do: query
  defp filter_through(query, seq), do: from(e in query, where: e.seq <= ^seq)

  defp filter_types(query, nil), do: query
  defp filter_types(query, types), do: from(e in query, where: e.type in ^types)

  defp filter_turn(query, nil), do: query
  defp filter_turn(query, turn_id), do: from(e in query, where: e.turn_id == ^turn_id)

  defp filter_operation(query, nil), do: query

  defp filter_operation(query, operation_id),
    do: from(e in query, where: e.operation_id == ^operation_id)

  defp filter_origin(query, nil, _scope), do: query

  defp filter_origin(query, "performed", scope) do
    from(e in query, where: is_nil(e.source_agent_id) or e.source_agent_id == ^scope)
  end

  defp filter_origin(query, "inherited", scope) do
    from(e in query,
      where: not is_nil(e.source_agent_id) and e.source_agent_id != ^scope
    )
  end

  # An entry derived from another Agent is marked as inherited, so a reader never
  # counts it as work this scope performed.
  defp plain_event(event, scope) do
    origin =
      if is_nil(event.source_agent_id) or event.source_agent_id == scope,
        do: "performed",
        else: "inherited"

    event |> Records.plain() |> Map.put("origin", origin)
  end

  defp oversized?([], _budget), do: false
  defp oversized?([row | _], budget), do: byte_size(row.raw) > budget

  # A page never splits a record: a single record over the byte budget is kept
  # whole and flagged, and stays bounded by the record's own codec limit.
  defp take_rows([], _limit, _budget, acc, _bytes, _get), do: {Enum.reverse(acc), false}

  defp take_rows([row | rest], limit, budget, acc, bytes, get) do
    size = byte_size(row.raw)

    if acc != [] and bytes + size > budget do
      {Enum.reverse(acc), true}
    else
      acc = [get.(row) | acc]
      bytes = bytes + size

      # A full page always reports a cursor: only the next (possibly empty)
      # page can prove the range ended.
      if length(acc) >= limit,
        do: {Enum.reverse(acc), true},
        else: take_rows(rest, limit, budget, acc, bytes, get)
    end
  end

  defp read_checkpoints(repo, agent_id, filters) do
    query =
      from(c in Checkpoint,
        where: c.agent_id == ^agent_id,
        order_by: [asc: c.recorded_at, asc: c.id],
        limit: ^filters.limit,
        select: %{checkpoint: c, raw: fragment("CAST(? AS TEXT)", c.data)}
      )

    query = after_clause(query, filters.after)

    query =
      if filters.through,
        do: from(c in query, where: c.recorded_at <= ^filters.through),
        else: query

    rows = repo.all(query, log: false)

    {checkpoints, more?} =
      take_rows(rows, filters.limit, filters.max_bytes, [], 0, & &1.checkpoint)

    next =
      case List.last(checkpoints) do
        nil ->
          nil

        checkpoint when more? ->
          %{"recorded_at" => DateTime.to_iso8601(checkpoint.recorded_at), "id" => checkpoint.id}

        _ ->
          nil
      end

    {:ok,
     %{
       "checkpoints" => Enum.map(checkpoints, &Records.plain/1),
       "next_cursor" => next,
       "over_budget" => oversized?(rows, filters.max_bytes)
     }}
  end

  defp after_clause(query, nil), do: query

  defp after_clause(query, {at, nil}), do: from(c in query, where: c.recorded_at > ^at)

  defp after_clause(query, {at, id}) do
    from(c in query, where: c.recorded_at > ^at or (c.recorded_at == ^at and c.id > ^id))
  end

  defp read_turns(repo, agent_id, after_seq, limit, through) do
    query =
      from(e in Event,
        where: e.scope_id == ^agent_id and not is_nil(e.turn_id),
        group_by: e.turn_id,
        having: min(e.seq) > ^after_seq,
        order_by: [asc: min(e.seq)],
        limit: ^limit,
        select: %{
          turn_id: e.turn_id,
          first_seq: min(e.seq),
          last_seq: max(e.seq),
          events: count(e.id)
        }
      )

    query = filter_through(query, through)

    turns =
      Enum.map(repo.all(query, log: false), fn turn ->
        checkpoint =
          from(c in Checkpoint,
            where: c.agent_id == ^agent_id and c.turn_id == ^turn.turn_id,
            order_by: [desc: c.recorded_at, desc: c.id],
            limit: 1
          )
          |> repo.one(log: false)

        %{
          "turn_id" => turn.turn_id,
          "first_seq" => turn.first_seq,
          "last_seq" => turn.last_seq,
          "events" => turn.events,
          "checkpoint_id" => checkpoint && checkpoint.id,
          "continuation" => checkpoint && checkpoint.continuation,
          "step" => checkpoint && get_in(checkpoint.data, ["step"])
        }
      end)

    next = if length(turns) == limit, do: List.last(turns)["first_seq"], else: nil
    {:ok, %{"turns" => turns, "next_cursor" => next}}
  end

  # Preparation allocates a distinct committed Agent event per member. Acceptance
  # changes only Operation history_seq, never this immutable pagination position.
  defp read_operations(repo, agent_id, after_seq, limit) do
    query =
      from(o in Operation,
        where: o.owner_agent_id == ^agent_id and o.prepared_seq > ^after_seq,
        order_by: [asc: o.prepared_seq, asc: o.id],
        limit: ^limit
      )

    operations =
      Enum.map(repo.all(query, log: false), fn operation ->
        %{
          "operation_id" => operation.id,
          "history_seq" => operation.prepared_seq,
          "turn_id" => operation.turn_id,
          "tool_call_id" => operation.tool_call_id,
          "ordinal" => operation.ordinal,
          "description" => operation.description,
          "description_digest" => operation.description_digest,
          "accepted_result" => operation.accepted_result,
          "accepted_evidence_id" => operation.accepted_evidence_id,
          "attempt" => Records.plain(attempt_for(repo, operation.id)),
          "evidence_digests" => Enum.map(evidence_rows(repo, operation.id), & &1["digest"])
        }
      end)

    next = if length(operations) == limit, do: List.last(operations)["history_seq"], else: nil
    {:ok, %{"operations" => operations, "next_cursor" => next}}
  end

  defp attempt_for(repo, operation_id) do
    from(e in Execution, where: e.operation_id == ^operation_id)
    |> repo.one(log: false)
  end

  defp evidence_rows(repo, operation_id, limit \\ 32) do
    from(e in ExecutionEvidence,
      where: e.operation_id == ^operation_id,
      order_by: [desc: e.recorded_at, asc: e.id],
      limit: ^limit
    )
    |> repo.all(log: false)
    |> Enum.map(&Records.plain/1)
  end

  ## Bounds

  defp seq(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp seq(_), do: {:error, :invalid_data}

  defp optional_seq(nil), do: {:ok, nil}
  defp optional_seq(value), do: seq(value)

  defp bounded(value, min, max) when is_integer(value) and value >= min and value <= max,
    do: {:ok, value}

  defp bounded(value, _min, max) when is_integer(value) and value > max, do: {:error, :limit}

  defp bounded(_, _, _), do: {:error, :invalid_data}

  defp optional_uuid(nil), do: {:ok, nil}
  defp optional_uuid(value), do: Records.uuid(value)

  defp types(nil, nil), do: {:ok, nil}

  defp types(nil, type) do
    case Records.text(type, 255) do
      {:ok, type} -> {:ok, [type]}
      error -> error
    end
  end

  defp types(types, _type) when is_list(types) and length(types) in 1..8 do
    Enum.reduce_while(types, {:ok, []}, fn type, {:ok, acc} ->
      case Records.text(type, 255) do
        {:ok, type} -> {:cont, {:ok, [type | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp types(_, _), do: {:error, :invalid_data}

  defp optional_time(nil), do: {:ok, nil}

  defp optional_time(%DateTime{} = value), do: {:ok, value}

  defp optional_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _ -> {:error, :invalid_data}
    end
  end

  defp optional_time(_), do: {:error, :invalid_data}
end
