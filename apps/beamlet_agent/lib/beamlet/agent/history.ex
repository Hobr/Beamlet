defmodule Beamlet.Agent.History do
  @typep object :: Beamlet.Agent.Core.Data.object()
  @typep result(value) :: Beamlet.Agent.result(value)
  @spec query(term(), term(), term()) :: result(object())
  @spec turns(term(), keyword()) :: result(object())
  @spec turn_events(term(), term(), keyword()) :: result(object())
  @spec view(term()) :: {:ok, binary()} | {:error, :invalid_data}
  @spec position(object(), map(), term(), binary()) ::
          {:ok, pos_integer(), non_neg_integer()} | {:error, :invalid_data}
  @spec dispatch(binary(), module(), binary(), pos_integer(), non_neg_integer(), map()) ::
          result(object())
  @spec known_operation?(object(), term()) :: boolean()
  @spec operations(module(), binary(), [object()], pos_integer()) :: result([object()])
  @spec operation_projection(module(), binary(), object(), pos_integer()) :: result(object())
  @moduledoc """
  独立于实时 provider 的只读历史投影。游标保留 Agent 高水位；steps/tools 仅展示该截止位已消费的输出，evidence 单独标记为 Operation 快照。

  Read-only fixed-high-water facts and reference-derived context, independent of live providers.
  """
  alias Beamlet.Agent.ContextBuilder
  alias Beamlet.Agent.Loader
  alias Beamlet.Agent.Storage.AgentRecords
  alias Beamlet.Agent.Storage.History
  alias Beamlet.Agent.Storage.OperationRecords
  alias Beamlet.Agent.Storage.Records
  @views ~w(turns facts context steps tools evidence decisions provenance)

  @doc "按 view、as_of_seq 和固定游标读取历史；支持 facts/turns/context/steps/tools/evidence/decisions/provenance，非法参数返回 invalid_data。"
  def query(locator, filters \\ %{}, cursor \\ nil)

  def query(%{repo: repo, agent_id: id}, filters, cursor)
      when is_atom(repo) and is_map(filters) do
    with {:ok, _} <- Records.uuid(id),
         {:ok, %{"agent" => agent}} <- AgentRecords.fetch(repo, id),
         {:ok, view} <- view(filters[:view]),
         {:ok, through, after_seq} <- position(agent, filters, cursor, view),
         {:ok, result} <- dispatch(view, repo, id, through, after_seq, filters) do
      next = result["next_cursor"]

      {:ok,
       result
       |> Map.put("view", view)
       |> Map.put("through_seq", through)
       |> Map.put(
         "next_cursor",
         if(next, do: %{"view" => view, "through_seq" => through, "after_seq" => next})
       )}
    end
  end

  def query(_, _, _), do: {:error, :invalid_data}

  @doc "以 turns 视图读取轮次列表。"
  def turns(locator, opts \\ []), do: query(locator, Map.put(Map.new(opts), :view, :turns))

  @doc "以 facts 视图读取指定 turn 的事件。"
  def turn_events(locator, turn, opts \\ []),
    do: query(locator, Map.merge(Map.new(opts), %{view: :facts, turn_id: turn}))

  defp view(view) when is_atom(view), do: view(Atom.to_string(view))
  defp view(view) when view in @views, do: {:ok, view}
  defp view(_), do: {:error, :invalid_data}

  defp position(agent, filters, nil, _view) do
    through = filters[:as_of_seq] || agent["history_seq"]
    after_seq = filters[:after_seq] || 0

    if is_integer(through) and through in 1..agent["history_seq"] and is_integer(after_seq) and
         after_seq >= 0, do: {:ok, through, after_seq}, else: {:error, :invalid_data}
  end

  defp position(
         agent,
         filters,
         %{"view" => view, "through_seq" => through, "after_seq" => after_seq},
         view
       ) do
    position(agent, Map.merge(filters, %{as_of_seq: through, after_seq: after_seq}), nil, view)
  end

  defp position(_, _, _, _), do: {:error, :invalid_data}

  defp dispatch("context", repo, id, through, _after, _filters) do
    with {:ok, loaded} <- Loader.load(repo, id, through_seq: through),
         {:ok, messages} <- ContextBuilder.materialize(repo, loaded.control) do
      {:ok,
       %{
         "agent_id" => id,
         "as_of_seq" => through,
         "derived_by" => "event_reduction",
         "messages" => messages,
         "sources" => loaded.control["timeline"],
         "control" => loaded.control
       }}
    end
  end

  defp dispatch(view, repo, id, through, after_seq, filters) when view in ~w(facts decisions) do
    types =
      if view == "decisions",
        do: ~w(agent.continue_decided turn.interrupted agent.activated agent.forked),
        else: filters[:types]

    opts =
      [
        after_seq: after_seq,
        through_seq: through,
        limit: filters[:limit],
        max_bytes: filters[:max_bytes],
        type: filters[:type],
        types: types,
        turn_id: filters[:turn_id],
        operation_id: filters[:operation_id],
        origin: filters[:origin]
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    with {:ok, page} <- History.event_page(repo, id, opts) do
      {:ok, if(view == "decisions", do: Map.put(page, "decisions", page["events"]), else: page)}
    end
  end

  defp dispatch("turns", repo, id, through, after_seq, filters) do
    History.turns(repo, id,
      after_first_seq: after_seq,
      through_seq: through,
      limit: filters[:limit] || 50
    )
  end

  defp dispatch(view, repo, id, through, after_seq, filters) when view in ~w(steps tools) do
    type = if view == "steps", do: "model.request_prepared", else: "tool.batch_prepared"

    with {:ok, page} <-
           History.event_page(repo, id,
             type: type,
             through_seq: through,
             after_seq: after_seq,
             limit: filters[:limit] || 50
           ),
         {:ok, operations} <- operations(repo, id, page["events"], through) do
      {:ok, Map.put(page, if(view == "steps", do: "steps", else: "operations"), operations)}
    end
  end

  defp dispatch("evidence", repo, id, through, _after, filters) do
    with {:ok, loaded} <- Loader.load(repo, id, through_seq: through),
         true <- known_operation?(loaded.control, filters[:operation_id]),
         {:ok, rows} <- OperationRecords.fetch(repo, filters[:operation_id]),
         {:ok, %{"evidence" => evidence}} <- History.evidence(repo, filters[:operation_id]) do
      {:ok,
       rows
       |> Map.put("evidence", evidence)
       |> Map.put("observation", "operation_snapshot_not_agent_sequence")}
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp dispatch("provenance", repo, id, through, _after, _filters) do
    with {:ok, loaded} <- Loader.load(repo, id, through_seq: through) do
      refs = loaded.control["inheritance"]["sources"]

      {:ok,
       %{
         "agent_id" => id,
         "fork" => loaded.control["fork"],
         "inherited" => %{
           "references" => length(refs),
           "counted_as_execution" => false,
           "source_agent_ids" => Enum.uniq(Enum.map(refs, & &1["source_agent_id"]))
         },
         "sources" => refs,
         "parent_history_required" => false
       }}
    end
  end

  defp known_operation?(control, id) do
    Enum.any?(control["pending"] ++ control["consumed"], &(&1["operation_id"] == id)) or
      Enum.any?(
        control["inheritance"]["closure"],
        &(&1["type"] == "inherited_result" and &1["reference"]["operation_id"] == id)
      )
  end

  defp operations(repo, id, events, through) do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      with {:ok, rows} <- Loader.operation(repo, id, event["payload"]),
           {:ok, projection} <- operation_projection(repo, id, rows["operation"], through) do
        {:cont, {:ok, acc ++ [projection]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp operation_projection(repo, id, op, through) do
    with {:ok, %{"events" => consumed}} <-
           History.event_page(repo, id,
             type: "operation.result_consumed",
             operation_id: op["id"],
             through_seq: through
           ) do
      immutable =
        Map.take(
          op,
          ~w(id owner_agent_id turn_id step_id role ordinal tool_call_id prepared_seq description description_digest sources)
        )

      {:ok,
       immutable
       |> Map.put("origin", "performed")
       |> Map.put("accepted_result", if(consumed != [], do: op["accepted_result"]))
       |> Map.put("accepted_at_agent_cutoff", consumed != [])}
    end
  end
end
