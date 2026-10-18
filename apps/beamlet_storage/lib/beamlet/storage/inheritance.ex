defmodule Beamlet.Storage.Inheritance do
  @moduledoc "Direct immutable content manifests. No parent history is read when verifying a manifest."
  import Ecto.Query
  alias Beamlet.Storage.{Artifacts, Codec, History, OperationRecords, References}
  alias Beamlet.Storage.Schema.{Artifact, Event}

  @max_refs 1024

  def source_position(repo, agent, attrs) do
    events =
      repo.all(
        from(e in Event,
          where:
            e.scope_id == ^agent and e.seq <= ^attrs.through_seq and
              e.type in ~w(input.accepted operation.result_consumed context.inherited),
          order_by: e.seq,
          limit: 130
        ),
        log: false
      )

    timeline = Enum.flat_map(events, &timeline_entry/1)
    inherited = Enum.find(events, &(&1.type == "context.inherited"))
    previous = if inherited, do: inherited.payload, else: %{"sources" => [], "closure" => []}

    if timeline == attrs.timeline and previous == attrs.inheritance and length(timeline) <= 128,
      do: verify_resolutions(repo, agent, attrs),
      else: {:error, :conflict}
  end

  defp timeline_entry(%Event{type: "input.accepted"} = e) do
    {:ok, digest} = Codec.digest(e.payload, :event)
    [%{"type" => "input", "seq" => e.seq, "event_id" => e.id, "digest" => digest}]
  end

  defp timeline_entry(%Event{type: "operation.result_consumed", payload: p}),
    do: [
      %{
        "type" => "accepted_result",
        "reference" => Map.take(p, ~w(operation_id accepted_digest consumption_kind))
      }
    ]

  defp timeline_entry(%Event{type: "context.inherited", payload: p}), do: p["sources"]

  defp verify_resolutions(repo, agent, attrs) do
    Enum.reduce_while(attrs.resolutions, :ok, fn {id, resolution}, :ok ->
      case repo.get(Event, resolution["decision_event_id"], log: false) do
        %Event{scope_id: ^agent, type: "agent.continue_decided", payload: p, seq: seq}
        when seq <= attrs.through_seq ->
          decisions = p["decision"]["resolutions"] || [p["decision"]]

          resolution_outcome(decisions, id, resolution)

        _ ->
          {:halt, {:error, :conflict}}
      end
    end)
  end

  defp resolution_outcome(decisions, id, resolution) do
    if Enum.any?(
         decisions,
         &(&1["operation_id"] == id and &1["resolution"] == resolution["resolution"])
       ), do: {:cont, :ok}, else: {:halt, {:error, :conflict}}
  end

  def build(repo, agent_id, timeline, previous, resolutions) do
    initial = %{
      sources: [],
      closure: previous["closure"] || [],
      resolutions: resolutions,
      visiting: [],
      deadline: System.monotonic_time(:millisecond) + 5000
    }

    with {:ok, state} <- collect(repo, agent_id, timeline, initial),
         manifest = %{"sources" => state.sources, "closure" => state.closure},
         :ok <- verify(repo, manifest) do
      {:ok, manifest}
    end
  end

  defp collect(repo, agent, sources, state) do
    Enum.reduce_while(sources, {:ok, state}, fn source, {:ok, acc} ->
      case bounded_capture(repo, agent, source, acc) do
        {:ok, direct, next} -> {:cont, {:ok, %{next | sources: next.sources ++ [direct]}}}
        error -> {:halt, error}
      end
    end)
  end

  defp bounded_capture(repo, agent, source, state) do
    existing =
      Enum.find(state.closure, &same_source?(&1, source))

    cond do
      System.monotonic_time(:millisecond) >= state.deadline -> {:error, :limit}
      existing -> {:ok, existing, state}
      true -> capture(repo, agent, source, state)
    end
  end

  defp same_source?(ref, %{"type" => "accepted_result", "reference" => r}),
    do: ref["type"] == "inherited_result" and ref["reference"] == r

  defp same_source?(ref, %{"type" => "input", "event_id" => id} = source),
    do:
      ref["type"] == "inherited_input" and ref["event_id"] == id and
        ref["digest"] == source["digest"]

  defp same_source?(ref, source), do: ref == source

  defp capture(repo, agent, %{"type" => "input"} = source, state) do
    with {:ok, event} <- History.event(repo, agent, source["seq"]),
         true <- event["id"] == source["event_id"] and event["type"] == "input.accepted",
         {:ok, bytes} <- Codec.encode(event["payload"], :event),
         true <- Codec.hash(bytes) == source["digest"],
         {:ok, artifact} <- input_artifact(repo, bytes) do
      direct =
        Map.merge(source, %{
          "type" => "inherited_input",
          "source_agent_id" => agent,
          "artifact_id" => artifact.id
        })

      add(direct, state)
    else
      false -> {:error, :invalid_reference}
      error -> error
    end
  end

  defp capture(repo, agent, %{"type" => "accepted_result", "reference" => ref}, state) do
    with {:ok, %{"operation" => op}} <- OperationRecords.fetch(repo, ref["operation_id"]),
         true <- op["owner_agent_id"] == agent,
         true <- op["id"] not in state.visiting,
         %Event{payload: payload} <-
           repo.one(
             from(e in Event,
               where:
                 e.scope_id == ^agent and
                   e.type == "operation.result_consumed" and e.operation_id == ^op["id"]
             ),
             log: false
           ),
         true <- Map.take(payload, ~w(operation_id accepted_digest consumption_kind)) == ref,
         {:ok, nested} <-
           collect(repo, agent, op["sources"], %{
             state
             | sources: [],
               visiting: [op["id"] | state.visiting]
           }) do
      direct = %{
        "type" => "inherited_result",
        "reference" => ref,
        "source_agent_id" => agent,
        "description_digest" => op["description_digest"],
        "resolution" => state.resolutions[op["id"]]
      }

      add(direct, %{nested | sources: state.sources, visiting: state.visiting})
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp capture(_repo, _agent, %{"type" => type} = source, state)
       when type in ~w(inherited_input inherited_result), do: add(source, state)

  defp capture(_, _, _, _), do: {:error, :invalid_reference}

  defp add(direct, state) do
    closure = Enum.uniq(state.closure ++ [direct])

    if length(closure) <= @max_refs,
      do: {:ok, direct, %{state | closure: closure}},
      else: {:error, :limit}
  end

  defp input_artifact(repo, bytes) do
    digest = Codec.hash(bytes)

    case repo.one(from(a in Artifact, where: a.digest == ^digest), log: false) do
      nil ->
        Artifacts.put(repo, %{
          id: Ecto.UUID.generate(),
          content: bytes,
          digest: digest,
          size: byte_size(bytes),
          media_type: "application/json",
          recorded_at: DateTime.utc_now()
        })

      artifact ->
        Artifacts.fetch(repo, artifact.id)
    end
  end

  def verify(repo, %{"sources" => sources, "closure" => closure} = manifest)
      when map_size(manifest) == 2 and is_list(sources) and is_list(closure) and
             length(sources) <= 128 and length(closure) <= @max_refs do
    deadline = System.monotonic_time(:millisecond) + 5000

    if Enum.all?(sources, &(&1 in closure)),
      do: verify_closure(repo, closure, deadline),
      else: {:error, :invalid_reference}
  end

  def verify(_, _), do: {:error, :invalid_reference}

  defp verify_closure(repo, closure, deadline) do
    Enum.reduce_while(closure, :ok, fn ref, :ok ->
      result =
        if System.monotonic_time(:millisecond) < deadline,
          do: verify_entry(repo, ref, closure),
          else: {:error, :limit}

      case result do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def input(repo, ref) do
    with {:ok, artifact} <- Artifacts.fetch(repo, ref["artifact_id"]),
         true <- artifact.digest == ref["digest"],
         {:ok, %{"text" => text} = payload} <- Codec.decode(artifact.content, :event),
         true <-
           map_size(payload) == 1 and is_binary(text) and String.valid?(text) and
             byte_size(text) <= 65_536 do
      {:ok, payload}
    else
      false -> {:error, :invalid_reference}
      error -> error
    end
  end

  defp verify_entry(repo, %{"type" => "inherited_input"} = ref, _closure) do
    with true <-
           Enum.sort(Map.keys(ref)) == ~w(artifact_id digest event_id seq source_agent_id type),
         true <- Codec.uuid?(ref["source_agent_id"]) and Codec.uuid?(ref["event_id"]),
         true <- is_integer(ref["seq"]) and ref["seq"] > 0,
         {:ok, _} <- input(repo, ref),
         do: :ok,
         else: (_ -> {:error, :invalid_reference})
  end

  defp verify_entry(repo, %{"type" => "inherited_result"} = ref, closure) do
    with true <-
           Enum.sort(Map.keys(ref)) ==
             ~w(description_digest reference resolution source_agent_id type),
         reference when is_map(reference) <- ref["reference"],
         true <-
           Enum.sort(Map.keys(reference)) == ~w(accepted_digest consumption_kind operation_id),
         {:ok, %{"operation" => op}} <- OperationRecords.fetch(repo, reference["operation_id"]),
         true <- op["owner_agent_id"] == ref["source_agent_id"],
         true <- op["description_digest"] == ref["description_digest"],
         :ok <- operation(repo, op, ref["reference"]),
         true <- Enum.all?(op["sources"], &covered?(&1, closure)),
         true <- valid_resolution?(op, ref["resolution"]) do
      :ok
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp verify_entry(_, _, _), do: {:error, :invalid_reference}

  def operation(repo, op, ref) do
    with {:ok, digest} <- Codec.digest(op["description"], :operation),
         true <- digest == op["description_digest"],
         {:ok, prepared} <- History.event(repo, op["id"], 1),
         true <- prepared["type"] == "operation.prepared" and prepared["schema_version"] == 1,
         true <- prepared["payload"]["description_digest"] == digest,
         {:ok, accepted} <- History.event(repo, op["id"], 2),
         true <-
           accepted["type"] == "operation.result_accepted" and accepted["schema_version"] == 1,
         {:ok, digest} <- Codec.digest(op["accepted_result"], :result),
         true <-
           digest == ref["accepted_digest"] and digest == accepted["payload"]["accepted_digest"],
         :ok <- References.verify_read(repo, op["description"]),
         :ok <- References.verify_read(repo, op["accepted_result"]) do
      :ok
    else
      false -> {:error, :invalid_reference}
      error -> error
    end
  end

  defp valid_resolution?(%{"accepted_result" => %{"status" => status}}, resolution) do
    if status in ~w(uncertain cancelled deadline unknown),
      do:
        is_map(resolution) and resolution["resolution"] in ~w(confirmed_failed confirmed_executed),
      else: is_nil(resolution)
  end

  defp covered?(%{"type" => "input"} = source, closure),
    do:
      Enum.any?(
        closure,
        &(Map.take(&1, ~w(event_id seq digest)) == Map.take(source, ~w(event_id seq digest)))
      )

  defp covered?(%{"type" => "accepted_result", "reference" => ref}, closure),
    do: Enum.any?(closure, &(&1["type"] == "inherited_result" and &1["reference"] == ref))

  defp covered?(%{"type" => type} = source, closure)
       when type in ~w(inherited_input inherited_result),
       do: source in closure

  defp covered?(_, _), do: false

  def authorized?(repo, agent_id, source, through) do
    case repo.one(
           from(e in Event,
             where:
               e.scope_id == ^agent_id and
                 e.type == "context.inherited" and e.seq <= ^through
           ),
           log: false
         ) do
      %Event{payload: manifest} -> source in manifest["sources"] and verify(repo, manifest) == :ok
      _ -> false
    end
  end
end
