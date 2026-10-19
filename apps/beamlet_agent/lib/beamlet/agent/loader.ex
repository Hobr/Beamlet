defmodule Beamlet.Agent.Loader do
  @typedoc "Fixed-high-water reconstruction. String-key record fields and reference relationships are runtime validated."
  @type loaded :: %{
          agent: Beamlet.Agent.Core.Data.object(),
          control: Beamlet.Agent.Core.Reducer.state()
        }
  @typep object :: Beamlet.Agent.Core.Data.object()
  @typep result(value) :: Beamlet.Agent.result(value)
  @typep check :: :ok | Beamlet.Agent.error()
  @spec load(module(), term(), keyword()) :: result(loaded())
  @spec base(module(), binary(), pos_integer(), keyword()) ::
          {object(), non_neg_integer(), non_neg_integer()}
  @spec cached_base(module(), binary(), pos_integer()) ::
          {object(), non_neg_integer(), non_neg_integer()}
  @spec pages(module(), object(), pos_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, object(), non_neg_integer(), non_neg_integer()} | Beamlet.Agent.error()
  @spec references(module(), object()) :: check()
  @spec owned_references(module(), object()) :: check()
  @spec resolutions(module(), object()) :: check()
  @spec bounded_operation(module(), binary(), object(), integer()) :: result(object())
  @spec operation(module(), binary(), term()) :: result(object())
  @spec prepared_reference(module(), binary(), object()) :: check()
  @spec sources(module(), binary(), object()) :: check()
  @spec source(module(), binary(), pos_integer(), term()) :: check() | false
  @spec accepted_digest(module(), object(), object()) :: check()
  @moduledoc "Bounded fixed-high-water history reconstruction. Reads never activate or dispatch."
  alias Beamlet.Agent.Reducer
  alias Beamlet.Agent.Storage.AgentRecords
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Agent.Storage.History
  alias Beamlet.Agent.Storage.Inheritance
  alias Beamlet.Agent.Storage.OperationRecords
  alias Beamlet.Storage.References
  @max_events 100_000
  @max_bytes 33_554_432

  def load(repo, id, opts \\ []) do
    with {:ok, %{"agent" => agent}} <- AgentRecords.fetch(repo, id),
         :ok <- References.verify_read(repo, agent["definition"]),
         through = Keyword.get(opts, :through_seq, agent["history_seq"]),
         true <- is_integer(through) and through >= 1 and through <= agent["history_seq"],
         {base, count, bytes} = base(repo, id, through, opts),
         {:ok, state, _, _} <- pages(repo, base, through, count, bytes),
         :ok <- references(repo, state),
         :ok <- resolutions(repo, state) do
      {:ok, %{agent: agent, control: state}}
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  defp base(repo, id, through, opts) do
    if Keyword.get(opts, :cache, true) do
      cached_base(repo, id, through)
    else
      {Reducer.new(id), 0, 0}
    end
  end

  defp cached_base(repo, id, through) do
    with {:ok, %{"checkpoint" => cp}} when is_map(cp) <- History.checkpoint_at(repo, id, through),
         true <- cp["schema_version"] == 1 and cp["reducer_version"] == Reducer.version(),
         data when is_map(data) <- cp["data"],
         true <- Enum.sort(Map.keys(data)) == Enum.sort(Map.keys(Reducer.new(id))),
         true <- data["agent_id"] == id and data["through_seq"] == cp["through_seq"],
         true <-
           is_list(data["pending"]) and is_list(data["consumed"]) and is_list(data["timeline"]),
         {:ok, prefix, count, bytes} <- pages(repo, Reducer.new(id), cp["through_seq"], 0, 0),
         true <- prefix == data do
      {data, count, bytes}
    else
      _ -> {Reducer.new(id), 0, 0}
    end
  end

  defp pages(_repo, %{"through_seq" => seq} = state, seq, count, bytes),
    do: {:ok, state, count, bytes}

  defp pages(repo, state, through, count, bytes) do
    with {:ok, page} <-
           History.event_page(repo, state["agent_id"],
             after_seq: state["through_seq"],
             through_seq: through,
             limit: 100
           ),
         events = page["events"],
         true <- events != [],
         count = count + length(events),
         bytes = bytes + :erlang.external_size(events),
         true <- count <= @max_events and bytes <= @max_bytes,
         {:ok, next} <- Reducer.replay(state, events) do
      pages(repo, next, through, count, bytes)
    else
      false -> {:error, :history_limit_or_gap}
      error -> error
    end
  end

  def references(repo, state) do
    with :ok <- Inheritance.verify(repo, state["inheritance"]) do
      owned_references(repo, state)
    end
  end

  defp owned_references(repo, state) do
    refs = state["pending"] ++ state["consumed"]

    deadline = System.monotonic_time(:millisecond) + 5000

    Enum.reduce_while(refs, :ok, fn ref, :ok ->
      case bounded_operation(repo, state["agent_id"], ref, deadline) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp resolutions(repo, state) do
    Enum.reduce_while(state["resolutions"], :ok, fn {id, _resolution}, :ok ->
      with {:ok, %{"operation" => %{"accepted_result" => %{"status" => status}}}} <-
             OperationRecords.fetch(repo, id),
           true <- status in ~w(uncertain cancelled deadline unknown) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :invalid_reference}}
      end
    end)
  end

  defp bounded_operation(repo, agent, ref, deadline) do
    if System.monotonic_time(:millisecond) < deadline,
      do: operation(repo, agent, ref),
      else: {:error, :limit}
  end

  def operation(repo, agent_id, ref) when is_map(ref) do
    with {:ok, %{"operation" => op} = rows} <- OperationRecords.fetch(repo, ref["operation_id"]),
         true <- op["owner_agent_id"] == agent_id,
         true <- is_list(op["sources"]) and length(op["sources"]) <= 128,
         true <- op["role"] in ~w(model tool) and is_integer(op["prepared_seq"]),
         {:ok, digest} <- Codec.digest(op["description"], :operation),
         true <- digest == op["description_digest"],
         :ok <- prepared_reference(repo, agent_id, op),
         :ok <- References.verify_read(repo, op["description"]),
         :ok <- References.verify_read(repo, op["accepted_result"]),
         :ok <- accepted_digest(repo, op, ref),
         :ok <- sources(repo, agent_id, op) do
      {:ok, rows}
    else
      false -> {:error, :invalid_reference}
      error -> error
    end
  end

  def operation(_, _, _), do: {:error, :invalid_reference}

  defp prepared_reference(repo, agent, op) do
    type = if op["role"] == "tool", do: "tool.batch_prepared", else: "model.request_prepared"
    member = Map.take(op, ~w(step_id ordinal)) |> Map.put("operation_id", op["id"])

    with {:ok, event} <- History.event(repo, agent, op["prepared_seq"]),
         :ok <- Reducer.decode(event),
         true <- event["type"] == type and event["turn_id"] == op["turn_id"],
         true <- Map.take(event["payload"], ~w(operation_id step_id ordinal)) == member,
         {:ok, prepared} <- History.operation_event(repo, op["id"], 1),
         true <- prepared["type"] == "operation.prepared" and prepared["schema_version"] == 1,
         true <- prepared["payload"]["description_digest"] == op["description_digest"] do
      :ok
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp sources(repo, agent, op) do
    deadline = System.monotonic_time(:millisecond) + 5000

    Enum.reduce_while(op["sources"], :ok, fn ref, :ok ->
      with true <- System.monotonic_time(:millisecond) < deadline,
           :ok <- source(repo, agent, op["prepared_seq"], ref) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :invalid_reference}}
      end
    end)
  end

  defp source(repo, agent, through, %{"type" => "input", "seq" => seq} = ref) do
    with true <- seq < through,
         {:ok, e} <- History.event(repo, agent, seq),
         true <- e["id"] == ref["event_id"] and e["type"] == "input.accepted",
         {:ok, digest} <- Codec.digest(e["payload"], :event),
         true <- digest == ref["digest"],
         do: :ok
  end

  defp source(repo, agent, through, %{"type" => "accepted_result", "reference" => ref})
       when is_map(ref) do
    with {:ok, %{"operation" => op}} <- OperationRecords.fetch(repo, ref["operation_id"]),
         true <- op["owner_agent_id"] == agent,
         :ok <- accepted_digest(repo, op, ref),
         {:ok, %{"events" => [event]}} <-
           History.event_page(repo, agent,
             through_seq: through - 1,
             type: "operation.result_consumed",
             operation_id: op["id"]
           ),
         true <-
           Map.take(event["payload"], ~w(operation_id accepted_digest consumption_kind)) == ref,
         do: :ok
  end

  defp source(repo, agent, through, %{"type" => type} = ref)
       when type in ~w(inherited_input inherited_result) do
    case History.event_page(repo, agent, type: "context.inherited", through_seq: through - 1) do
      {:ok, %{"events" => [%{"payload" => manifest}]}} ->
        if ref in manifest["sources"],
          do: Inheritance.verify(repo, manifest),
          else: {:error, :invalid_reference}

      _ ->
        {:error, :invalid_reference}
    end
  end

  defp source(_, _, _, _), do: {:error, :invalid_reference}

  defp accepted_digest(_repo, %{"accepted_result" => nil}, ref) do
    if Map.has_key?(ref, "accepted_digest"),
      do: {:error, :invalid_reference},
      else: :ok
  end

  defp accepted_digest(repo, op, ref) do
    with %{"status" => status} <- op["accepted_result"],
         true <- status in ~w(ok error uncertain cancelled deadline unknown),
         {:ok, digest} <- Codec.digest(op["accepted_result"], :result),
         {:ok, event} <- History.operation_event(repo, op["id"], 2),
         true <- event["type"] == "operation.result_accepted" and event["schema_version"] == 1,
         true <- digest == event["payload"]["accepted_digest"],
         true <- Map.get(ref, "accepted_digest", digest) == digest do
      :ok
    else
      _ -> {:error, :invalid_reference}
    end
  end
end
