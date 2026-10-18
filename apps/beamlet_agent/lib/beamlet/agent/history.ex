defmodule Beamlet.Agent.History do
  @moduledoc """
  Durable history queries keyed by the persistent locator (`repo` + `agent_id`),
  never by a live Agent, coordinator or Runtime retention. Every view reads
  committed authority facts only and returns plain data.

  Three views stay separate:

    * `:facts` and `:turns` — the facts recorded at a time, with their original
      scope/sequence/`recorded_at`;
    * `:context` — the Agent's effective context at a point (`as_of_seq`), read
      from the immutable checkpoint committed at or before that event;
    * current runtime observation — deliberately not here: it stays with
      `Beamlet.Runtime.status/1` and `Beamlet.Node.observation/0` and is neither a
      fact nor a restore source.

  Records derived from another Agent keep their `source_agent_id` /
  `source_event_id` markers and are reported as `origin: "inherited"`; they are
  never counted as work this Agent performed.
  """
  alias Beamlet.Storage.{AgentRecords, History}

  @views ~w(turns facts context steps tools evidence decisions provenance)

  @doc """
  Runs one bounded history view. `filters` carries `:view` plus view-specific
  keys (`:as_of_seq`, `:turn_id`, `:operation_id`, `:origin`, `:limit`,
  `:max_bytes`); `cursor` is the `next_cursor` of the previous page.
  """
  def query(locator, filters \\ %{}, cursor \\ nil)

  def query(%{repo: repo, agent_id: agent_id}, filters, cursor)
      when is_atom(repo) and not is_nil(repo) and is_map(filters) do
    with {:ok, view} <- view(filters),
         {:ok, id} <- uuid(agent_id) do
      dispatch(view, repo, id, Map.delete(filters, :view), cursor)
    end
  end

  def query(_locator, _filters, _cursor), do: {:error, :invalid_data}

  @doc """
  Turns, in recorded order, with the continuation and step of each turn's newest
  checkpoint. A turn is a durable unit of input plus everything recorded for it.
  """
  def turns(locator, opts \\ []), do: query(locator, Map.put(Map.new(opts), :view, "turns"))

  @doc "Events of one turn only, still bounded and keyset-paginated."
  def turn_events(locator, turn_id, opts \\ []) do
    query(locator, Map.merge(Map.new(opts), %{view: "facts", turn_id: turn_id}))
  end

  defp dispatch("turns", repo, id, filters, cursor) do
    opts = [after_first_seq: cursor || filters[:after_first_seq] || 0, limit: filters[:limit]]
    opts = Enum.reject(opts, fn {_key, value} -> is_nil(value) end)

    with {:ok, page} <- History.turns(repo, id, opts) do
      {:ok, Map.put(page, "view", "turns")}
    end
  end

  defp dispatch("facts", repo, id, filters, cursor) do
    opts =
      [
        after_seq: after_seq(cursor, filters),
        through_seq: filters[:as_of_seq],
        type: filters[:type],
        types: filters[:types],
        turn_id: filters[:turn_id],
        operation_id: filters[:operation_id],
        origin: filters[:origin],
        limit: filters[:limit],
        max_bytes: filters[:max_bytes]
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    with {:ok, page} <- History.event_page(repo, id, opts) do
      {:ok, Map.put(page, "view", "facts")}
    end
  end

  defp dispatch("context", repo, id, filters, cursor) do
    seq = cursor || filters[:as_of_seq]

    with {:ok, snapshot} <- History.checkpoint_at(repo, id, seq),
         data = snapshot["checkpoint"]["data"] do
      {:ok,
       %{
         "view" => "context",
         "agent_id" => id,
         "as_of_seq" => snapshot["as_of_seq"],
         "derived_by" => snapshot["derived_by"],
         "checkpoint_id" => snapshot["checkpoint"]["id"],
         "turn_id" => snapshot["checkpoint"]["turn_id"],
         "continuation" => snapshot["checkpoint"]["continuation"],
         "safe_to_fork" => snapshot["checkpoint"]["safe_to_fork"],
         "schema_version" => snapshot["checkpoint"]["schema_version"],
         "digest" => snapshot["checkpoint"]["digest"],
         "messages" => data["messages"],
         "step" => data["step"],
         "pending" => Map.get(data, "pending", []),
         "blocked" => data["blocked"],
         "source_markers" => source_markers(data["messages"])
       }}
    end
  end

  defp dispatch("steps", repo, id, filters, cursor) do
    opts = [
      after_seq: after_seq(cursor, filters),
      through_seq: filters[:as_of_seq],
      type: "model.reply_recorded",
      limit: filters[:limit]
    ]

    opts = Enum.reject(opts, fn {_key, value} -> is_nil(value) end)

    with {:ok, page} <- History.event_page(repo, id, opts),
         {:ok, steps} <- steps(repo, id, page["events"]) do
      {:ok,
       page
       |> Map.put("view", "steps")
       |> Map.put("steps", steps)
       |> Map.put("step_operations", "external")}
    end
  end

  defp dispatch("tools", repo, id, filters, cursor) do
    opts = [
      after_history_seq: cursor || filters[:after_history_seq] || 0,
      limit: filters[:limit]
    ]

    opts = Enum.reject(opts, fn {_key, value} -> is_nil(value) end)

    with {:ok, page} <- History.operations(repo, id, opts) do
      {:ok, Map.put(page, "view", "tools")}
    end
  end

  defp dispatch("evidence", repo, id, filters, _cursor) do
    case filters[:operation_id] do
      nil ->
        {:error, :invalid_data}

      operation_id ->
        with {:ok, fetched} <- History.operation(repo, operation_id),
             :ok <- owned(fetched["operation"], id) do
          {:ok,
           %{
             "view" => "evidence",
             "agent_id" => id,
             "operation_id" => operation_id,
             "attempt" => fetched["attempt"],
             "evidence" => fetched["evidence"],
             "accepted_result" => fetched["operation"]["accepted_result"]
           }}
        end
    end
  end

  defp dispatch("decisions", repo, id, filters, cursor) do
    opts = [
      after_seq: after_seq(cursor, filters),
      types: ["agent.decision", "agent.blocked", "agent.restored", "operation.result_accepted"],
      turn_id: filters[:turn_id],
      origin: filters[:origin],
      limit: filters[:limit]
    ]

    opts = Enum.reject(opts, fn {_key, value} -> is_nil(value) end)

    with {:ok, page} <- History.event_page(repo, id, opts) do
      decisions =
        Enum.map(page["events"], fn event ->
          Map.merge(event, %{
            "kind" => decision_kind(event["type"]),
            "outcome" => event["payload"]["status"] || event["payload"]["reason"]
          })
        end)

      {:ok, page |> Map.put("view", "decisions") |> Map.put("decisions", decisions)}
    end
  end

  defp dispatch("provenance", repo, id, _filters, _cursor) do
    with {:ok, fetched} <- AgentRecords.fetch(repo, id),
         agent = fetched["agent"],
         {:ok, inherited} <- History.event_page(repo, id, origin: "inherited", limit: 50) do
      sources =
        inherited["events"]
        |> Enum.map(& &1["source_agent_id"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      {:ok,
       %{
         "view" => "provenance",
         "agent_id" => id,
         "authority_id" => agent["authority_id"],
         "forked_from_agent_id" => agent["forked_from_agent_id"],
         "forked_from_checkpoint_id" => agent["forked_from_checkpoint_id"],
         "inherited" => %{
           "events" => length(inherited["events"]),
           "source_agent_ids" => sources,
           "counted_as_execution" => false,
           # The inherited view is a bounded page, not a total.
           "truncated" => length(inherited["events"]) == 50
         },
         "external" => external(agent, sources)
       }}
    end
  end

  defp dispatch(_view, _repo, _id, _filters, _cursor), do: {:error, :invalid_data}

  ## Steps

  defp steps(repo, agent_id, events) do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      case History.checkpoint_at(repo, agent_id, event["seq"]) do
        {:ok, snapshot} ->
          data = snapshot["checkpoint"]["data"]

          step = %{
            "turn_id" => event["turn_id"],
            "seq" => event["seq"],
            "recorded_at" => event["recorded_at"],
            "origin" => event["origin"],
            "request_digest" => event["payload"]["request_digest"],
            "kind" => event["payload"]["kind"],
            "step" => data["step"],
            "reply" => data["assistant"],
            "checkpoint_id" => snapshot["checkpoint"]["id"]
          }

          {:cont, {:ok, [step | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, steps} -> {:ok, Enum.reverse(steps)}
      error -> error
    end
  end

  ## Origin and provenance

  defp source_markers(nil), do: []

  defp source_markers(messages) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.flat_map(fn {message, index} ->
      case Map.take(message, ["source_agent_id", "source_event_id"]) do
        # One marker is enough to show provenance; dropping it would make an
        # inherited message read as this Agent's own context.
        markers when map_size(markers) >= 1 -> [Map.put(markers, "index", index)]
        _ -> []
      end
    end)
  end

  defp source_markers(_), do: []

  defp external(agent, sources) do
    case agent["forked_from_agent_id"] do
      nil ->
        []

      source ->
        [
          %{
            "relation" => "fork_source",
            "agent_id" => source,
            "checkpoint_id" => agent["forked_from_checkpoint_id"],
            "history_included?" => source in sources,
            "note" => "source history is provenance only and is not assembled recursively"
          }
        ]
    end
  end

  defp decision_kind("agent.decision"), do: "decision"
  defp decision_kind("agent.blocked"), do: "blocked"
  defp decision_kind("agent.restored"), do: "restore"
  defp decision_kind("operation.result_accepted"), do: "execution_result"

  defp owned(operation, agent_id) do
    if operation["owner_agent_id"] == agent_id, do: :ok, else: {:error, :conflict}
  end

  ## Bounds

  defp view(filters) do
    case Map.get(filters, :view) do
      view when is_atom(view) and not is_nil(view) ->
        if Atom.to_string(view) in @views,
          do: {:ok, Atom.to_string(view)},
          else: {:error, :invalid_data}

      view when is_binary(view) ->
        if view in @views, do: {:ok, view}, else: {:error, :invalid_data}

      _ ->
        {:error, :invalid_data}
    end
  end

  defp after_seq(cursor, filters) do
    case cursor do
      nil -> filters[:after_seq]
      cursor when is_integer(cursor) and cursor >= 0 -> cursor
      _ -> nil
    end
  end

  defp uuid(value), do: Beamlet.Storage.Records.uuid(value)
end
