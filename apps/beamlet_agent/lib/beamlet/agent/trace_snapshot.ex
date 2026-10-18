defmodule Beamlet.Agent.TraceSnapshot do
  @moduledoc false
  alias Beamlet.Agent.Reducer
  alias Beamlet.Storage.{AgentRecords, Artifacts, Codec, History, OperationRecords, References}

  @max_bytes 33_554_432
  @max_records 100_000

  def capture(repo, id) do
    with {:ok, %{"agent" => agent}} <- AgentRecords.fetch(repo, id),
         {:ok, events} <- pages(repo, id, agent["history_seq"], 0, [], 0),
         {:ok, control} <- Reducer.replay(Reducer.new(id), events),
         state = %{
           operations: %{},
           inputs: %{},
           artifacts: %{},
           missing: [],
           inherited: control["inheritance"]["closure"],
           bytes: :erlang.external_size(events),
           deadline: System.monotonic_time(:millisecond) + 5000
         },
         refs =
           control["pending"] ++
             control["consumed"] ++
             Enum.filter(state.inherited, &(&1["type"] == "inherited_result")),
         {:ok, state} <- operations(repo, refs, state),
         {:ok, state} <-
           artifacts(repo, [agent, events, Map.values(state.operations), state.inherited], state),
         {:ok, state} <- inherited_inputs(repo, state) do
      {:ok,
       %{
         agent: agent,
         events: events,
         control: control,
         operations: Map.values(state.operations) |> Enum.sort_by(& &1["operation"]["id"]),
         inputs: Map.values(state.inputs) |> Enum.sort_by(& &1["id"]),
         artifacts: Map.values(state.artifacts) |> Enum.sort_by(& &1.id),
         missing: Enum.uniq(state.missing)
       }}
    end
  end

  defp pages(_repo, _id, through, through, acc, _bytes), do: {:ok, Enum.reverse(acc)}

  defp pages(repo, id, through, after_seq, acc, bytes) do
    with {:ok, %{"events" => events}} <-
           History.event_page(repo, id, after_seq: after_seq, through_seq: through, limit: 100),
         true <- events != [],
         bytes = bytes + :erlang.external_size(events),
         true <- bytes <= @max_bytes and length(acc) + length(events) <= @max_records do
      pages(repo, id, through, List.last(events)["seq"], Enum.reverse(events, acc), bytes)
    else
      false -> {:error, :history_limit_or_gap}
      error -> error
    end
  end

  defp operations(repo, refs, state) do
    Enum.reduce_while(refs, {:ok, state}, fn ref, {:ok, acc} ->
      case operation(repo, ref["reference"] || ref, acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp operation(repo, ref, state) do
    id = ref["operation_id"]

    cond do
      Map.has_key?(state.operations, id) ->
        {:ok, state}

      map_size(state.operations) >= 1024 or System.monotonic_time(:millisecond) >= state.deadline ->
        {:error, :limit}

      true ->
        capture_operation(repo, ref, state)
    end
  end

  defp capture_operation(repo, ref, state) do
    id = ref["operation_id"]

    with {:ok, rows} <- OperationRecords.fetch(repo, id),
         {:ok, %{"evidence" => evidence}} <- History.evidence(repo, id),
         rows = Map.put(rows, "evidence", evidence),
         :ok <- valid_evidence(rows),
         {:ok, prepared} <- History.event(repo, id, 1) do
      op = rows["operation"]
      accepted = if op["accepted_result"], do: History.event(repo, id, 2), else: {:ok, nil}

      with {:ok, accepted} <- accepted,
           :ok <- valid_operation(op, prepared, accepted),
           true <-
             not Map.has_key?(ref, "accepted_digest") or
               (is_map(accepted) and
                  ref["accepted_digest"] == accepted["payload"]["accepted_digest"]),
           record = Map.merge(rows, %{"prepared_event" => prepared, "accepted_event" => accepted}),
           {:ok, next} <- charge(state, record),
           next = %{next | operations: Map.put(next.operations, id, record)},
           {:ok, next} <- sources(repo, op["owner_agent_id"], op["sources"], next) do
        {:ok, next}
      else
        {:error, :limit} = error -> error
        false -> {:ok, missing(state, "operation", id, :invalid_reference)}
        {:error, reason} -> {:ok, missing(state, "operation", id, reason)}
      end
    else
      {:error, :limit} = error -> error
      {:error, reason} -> {:ok, missing(state, "operation", id, reason)}
    end
  end

  def valid_evidence(%{"operation" => op, "attempt" => attempt, "evidence" => evidence})
      when is_map(attempt) and is_list(evidence) and length(evidence) <= 32 do
    valid =
      Enum.all?(evidence, fn
        %{
          "operation_id" => id,
          "attempt_id" => attempt_id,
          "executor_id" => executor,
          "content" => content,
          "digest" => digest
        } ->
          id == op["id"] and attempt_id == attempt["attempt_id"] and
            executor == attempt["executor_id"] and Codec.digest(content, :event) == {:ok, digest}

        _ ->
          false
      end)

    accepted = op["accepted_evidence_id"]

    if valid and (is_nil(accepted) or Enum.any?(evidence, &(&1["id"] == accepted))),
      do: :ok,
      else: {:error, :invalid_reference}
  end

  def valid_evidence(_), do: {:error, :invalid_reference}

  def valid_operation(op, %{"payload" => %{"description_digest" => _}} = prepared, accepted)
      when is_map(op) do
    with true <- Codec.uuid?(op["id"]) and op["history_seq"] in [1, 2],
         {:ok, digest} <- Codec.digest(op["description"], :operation),
         true <-
           digest == op["description_digest"] and
             prepared["payload"]["description_digest"] == digest,
         true <- prepared["type"] == "operation.prepared" and prepared["schema_version"] == 1,
         true <- prepared["scope_id"] == op["id"] and prepared["seq"] == 1,
         true <- is_list(op["sources"]) and length(op["sources"]) <= 128,
         :ok <- valid_accepted(op["accepted_result"], accepted),
         true <- is_nil(accepted) or (accepted["scope_id"] == op["id"] and accepted["seq"] == 2) do
      :ok
    else
      _ -> {:error, :invalid_reference}
    end
  end

  def valid_operation(_, _, _), do: {:error, :invalid_reference}

  defp valid_accepted(nil, nil), do: :ok

  defp valid_accepted(result, %{"payload" => %{"accepted_digest" => _}} = event)
       when is_map(result) do
    if event["type"] == "operation.result_accepted" and event["schema_version"] == 1 and
         Codec.digest(result, :result) == {:ok, event["payload"]["accepted_digest"]},
       do: :ok,
       else: {:error, :invalid_reference}
  end

  defp valid_accepted(_, _), do: {:error, :invalid_reference}

  defp sources(repo, owner, sources, state) do
    Enum.reduce_while(sources, {:ok, state}, fn source, {:ok, acc} ->
      case source(repo, owner, source, acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp source(repo, owner, %{"type" => "input"} = ref, state) do
    # A fork stores direct immutable input artifacts, so even Operation source
    # closure can be exported after the parent event log is retired.
    inherited =
      Enum.find(
        state.inherited,
        &(&1["type"] == "inherited_input" and &1["event_id"] == ref["event_id"])
      )

    if inherited do
      {:ok, state}
    else
      with {:ok, event} <- History.event(repo, owner, ref["seq"]),
           true <-
             event["id"] == ref["event_id"] and
               Codec.digest(event["payload"], :event) == {:ok, ref["digest"]},
           {:ok, next} <- charge(state, event) do
        {:ok, %{next | inputs: Map.put(next.inputs, event["id"], event)}}
      else
        _ -> {:ok, missing(state, "input", ref["event_id"], :invalid_reference)}
      end
    end
  end

  defp source(repo, _owner, %{"type" => "accepted_result", "reference" => ref}, state),
    do: operation(repo, ref, state)

  defp source(_repo, _owner, %{"type" => type}, state)
       when type in ~w(inherited_input inherited_result), do: {:ok, state}

  defp source(_, _, _, state), do: {:ok, missing(state, "source", nil, :invalid_reference)}

  defp inherited_inputs(repo, state), do: artifacts(repo, state.inherited, state)

  defp artifacts(repo, values, state) do
    with {:ok, ids} <- References.ids(values) do
      Enum.reduce_while(Enum.uniq(ids), {:ok, state}, &artifact_outcome(repo, &1, &2))
    end
  end

  defp artifact_outcome(repo, id, {:ok, acc}) do
    case artifact(repo, id, acc) do
      {:ok, next} -> {:cont, {:ok, next}}
      error -> {:halt, error}
    end
  end

  defp artifact(repo, id, state) do
    if Map.has_key?(state.artifacts, id) do
      {:ok, state}
    else
      with {:ok, artifact} <- Artifacts.fetch(repo, id),
           {:ok, next} <- charge(state, artifact.content) do
        {:ok, %{next | artifacts: Map.put(next.artifacts, id, artifact)}}
      else
        {:error, :limit} = error -> error
        {:error, reason} -> {:ok, missing(state, "artifact", id, reason)}
      end
    end
  end

  defp charge(state, value) do
    bytes = state.bytes + :erlang.external_size(value)
    if bytes <= @max_bytes, do: {:ok, %{state | bytes: bytes}}, else: {:error, :limit}
  end

  defp missing(state, kind, id, reason),
    do: %{
      state
      | missing: [%{"kind" => kind, "id" => id, "reason" => to_string(reason)} | state.missing]
    }
end
