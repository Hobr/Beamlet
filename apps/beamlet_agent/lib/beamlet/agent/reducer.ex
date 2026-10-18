defmodule Beamlet.Agent.Reducer do
  @moduledoc "Versioned, effect-free reduction of committed Agent orchestration events."
  alias Beamlet.Storage.{Codec, Events}

  def version, do: 1

  def new(id) do
    %{
      "agent_id" => id,
      "through_seq" => 0,
      "generation" => 0,
      "resolutions" => %{},
      "inheritance" => %{"sources" => [], "closure" => []},
      "fork" => nil,
      "environment_risk" => nil,
      "definition_version" => 1,
      "turn_id" => nil,
      "step" => 0,
      "continuation" => "await_input",
      "inputs" => [],
      "pending" => [],
      "consumed" => [],
      "timeline" => [],
      "blocked" => nil,
      "paused" => false
    }
  end

  def reduce(state, event) do
    with :ok <- decode(event),
         true <- event["scope_id"] == state["agent_id"],
         true <- event["seq"] == state["through_seq"] + 1,
         true <- state["through_seq"] > 0 or event["type"] == "agent.created",
         {:ok, next} <- apply_event(state, event) do
      {:ok, Map.put(next, "through_seq", event["seq"])}
    else
      false -> {:error, :invalid_history}
      error -> error
    end
  end

  def replay(state, events) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, current} ->
      case reduce(current, event) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  def decode(%{"schema_version" => 1, "type" => type, "payload" => payload} = event) do
    with true <- type in Events.agent_types(),
         true <- is_integer(event["seq"]) and event["seq"] > 0,
         true <- Codec.uuid?(event["id"]) and Codec.uuid?(event["scope_id"]),
         {:ok, _} <- Codec.encode(payload, :event) do
      with :ok <- validate_payload(type, payload),
           true <- event["operation_id"] == payload["operation_id"] do
        :ok
      else
        _ -> {:error, :invalid_history}
      end
    else
      _ -> {:error, :invalid_history}
    end
  end

  def decode(%{"schema_version" => _}), do: {:error, :schema_unsupported}
  def decode(_), do: {:error, :invalid_history}

  defp prepare_position?(s, true),
    do:
      not s["paused"] and s["continuation"] == "await_model_result" and s["pending"] == [] and
        s["step"] < 16

  defp prepare_position?(s, false),
    do:
      not s["paused"] and s["continuation"] in ~w(reply_recorded await_tool_results) and
        length(s["pending"]) < 8

  defp valid_member?(p),
    do:
      Codec.uuid?(p["operation_id"]) and is_integer(p["ordinal"]) and p["ordinal"] >= 0 and
        is_binary(p["step_id"])

  defp unique_member?(pending, p),
    do:
      Enum.all?(
        pending,
        &(&1["operation_id"] != p["operation_id"] and &1["ordinal"] != p["ordinal"])
      )

  defp validate_payload("input.accepted", %{"text" => text} = p)
       when map_size(p) == 1 and is_binary(text) and byte_size(text) <= 65_536 do
    if String.valid?(text), do: :ok, else: {:error, :invalid_history}
  end

  defp validate_payload("input.accepted", _), do: {:error, :invalid_history}

  defp validate_payload(type, payload) do
    with :ok <- Events.control(payload),
         true <- payload_shape?(type, payload) do
      :ok
    else
      _ -> {:error, :invalid_history}
    end
  end

  defp payload_shape?("agent.created", p), do: p == %{"definition_version" => 1}

  defp payload_shape?(type, p) when type in ~w(model.request_prepared tool.batch_prepared),
    do: keys?(p, ~w(operation_id step_id ordinal join)) and valid_member?(p) and is_map(p["join"])

  defp payload_shape?("operation.result_consumed", p),
    do:
      keys?(p, ~w(operation_id accepted_digest consumption_kind join)) and
        Codec.uuid?(p["operation_id"]) and
        is_binary(p["accepted_digest"]) and
        Regex.match?(~r/\A[0-9a-f]{64}\z/, p["accepted_digest"]) and is_map(p["join"])

  defp payload_shape?("agent.activated", p),
    do:
      keys?(p, ~w(generation continuation)) and is_integer(p["generation"]) and
        p["continuation"] == "interrupted"

  defp payload_shape?("turn.interrupted", p), do: keys?(p, ["reason"]) and is_binary(p["reason"])

  defp payload_shape?("agent.continue_decided", p),
    do:
      keys?(p, ~w(position resume_operations decision)) and is_list(p["resume_operations"]) and
        decision_shape?(p["decision"])

  defp payload_shape?("agent.forked", p),
    do:
      keys?(p, ~w(source_agent_id through_seq risk)) and Codec.uuid?(p["source_agent_id"]) and
        is_integer(p["through_seq"]) and p["through_seq"] >= 1 and
        p["risk"] in [nil, "unconfirmed"]

  defp payload_shape?("context.inherited", p),
    do:
      keys?(p, ~w(sources closure)) and is_list(p["sources"]) and is_list(p["closure"]) and
        length(p["sources"]) <= 128 and length(p["closure"]) <= 1024 and
        Enum.all?(p["closure"], &inherited_source?/1) and
        Enum.all?(p["sources"], &(&1 in p["closure"]))

  defp payload_shape?("context.selected", _p), do: true
  defp payload_shape?(_, _), do: false

  defp inherited_source?(%{"type" => "inherited_input"}), do: true

  defp inherited_source?(%{"type" => "inherited_result", "reference" => ref}) when is_map(ref),
    do: true

  defp inherited_source?(_), do: false

  defp keys?(p, keys), do: Enum.sort(Map.keys(p)) == Enum.sort(keys)
  def decisions(%{"resolutions" => list}) when is_list(list), do: list
  def decisions(p) when p == %{}, do: []
  def decisions(p), do: [p]

  defp decision_shape?(%{"resolutions" => list} = p) when map_size(p) == 1 and is_list(list) do
    ids = Enum.map(list, fn item -> if is_map(item), do: item["operation_id"] end)

    length(list) in 1..8 and length(Enum.uniq(ids)) == length(ids) and
      Enum.all?(list, &resolution_shape?/1)
  end

  defp decision_shape?(%{"risk" => "accepted"} = p) when map_size(p) == 1, do: true
  defp decision_shape?(p) when p == %{}, do: true

  defp decision_shape?(p), do: resolution_shape?(p)

  defp resolution_shape?(%{"operation_id" => id, "resolution" => resolution} = p),
    do:
      map_size(p) == 2 and Codec.uuid?(id) and
        resolution in ~w(confirmed_failed confirmed_executed)

  defp resolution_shape?(_), do: false

  defp apply_event(s, %{
         "type" => "agent.created",
         "seq" => 1,
         "payload" => %{"definition_version" => 1}
       }),
       do: {:ok, s}

  defp apply_event(s, %{"type" => "agent.forked", "seq" => 2, "payload" => p}) do
    if s["timeline"] == [] and s["fork"] == nil,
      do: {:ok, %{s | "fork" => p, "paused" => true, "environment_risk" => p["risk"]}},
      else: {:error, :invalid_history}
  end

  defp apply_event(s, %{"type" => "context.inherited", "seq" => 3, "payload" => p}) do
    if s["fork"] != nil and s["timeline"] == [],
      do: {:ok, %{s | "inheritance" => p, "timeline" => p["sources"]}},
      else: {:error, :invalid_history}
  end

  defp apply_event(s, %{"type" => "input.accepted"} = e) do
    if not s["paused"] and is_nil(s["environment_risk"]) and Codec.uuid?(e["turn_id"]) and
         s["pending"] == [] and
         s["continuation"] in ~w(await_input completed) do
      {:ok, digest} = Codec.digest(e["payload"], :event)
      ref = %{"type" => "input", "event_id" => e["id"], "seq" => e["seq"], "digest" => digest}

      {:ok,
       %{
         s
         | "inputs" => s["inputs"] ++ [ref],
           "timeline" => s["timeline"] ++ [ref],
           "turn_id" => e["turn_id"],
           "step" => 0,
           "continuation" => "await_model_result",
           "blocked" => nil
       }}
    else
      {:error, :invalid_history}
    end
  end

  defp apply_event(s, %{"type" => type, "payload" => p} = e)
       when type in ~w(model.request_prepared tool.batch_prepared) do
    model? = type == "model.request_prepared"

    valid =
      e["turn_id"] == s["turn_id"] and prepare_position?(s, model?) and
        unique_member?(s["pending"], p) and new_member?(s, p, model?)

    if valid do
      member = Map.take(p, ~w(operation_id step_id ordinal))

      {:ok,
       %{
         s
         | "pending" => s["pending"] ++ [member],
           "step" => s["step"] + if(model?, do: 1, else: 0),
           "continuation" => if(model?, do: "model_prepared", else: "await_tool_results")
       }}
    else
      {:error, :invalid_history}
    end
  end

  defp apply_event(s, %{"type" => "operation.result_consumed", "payload" => p} = e) do
    {member, pending} = Enum.split_with(s["pending"], &(&1["operation_id"] == p["operation_id"]))
    first = List.first(Enum.sort_by(s["pending"], & &1["ordinal"]))

    if not s["paused"] and length(member) == 1 and first["operation_id"] == p["operation_id"] and
         e["turn_id"] == s["turn_id"] and consumption_position?(s, p) do
      ref = Map.take(p, ~w(operation_id accepted_digest consumption_kind))

      position =
        if pending == [],
          do: p["join"]["position"] || "await_model_result",
          else: s["continuation"]

      {:ok,
       %{
         s
         | "pending" => pending,
           "consumed" => s["consumed"] ++ [ref],
           "timeline" => s["timeline"] ++ [%{"type" => "accepted_result", "reference" => ref}],
           "continuation" => position
       }}
    else
      {:error, :invalid_history}
    end
  end

  defp apply_event(s, %{"type" => "agent.activated", "payload" => %{"generation" => g}})
       when is_integer(g) do
    if g == s["generation"] + 1,
      do: {:ok, %{s | "generation" => g, "paused" => true}},
      else: {:error, :invalid_history}
  end

  defp apply_event(s, %{"type" => "turn.interrupted", "payload" => p}),
    do: {:ok, %{s | "blocked" => p, "paused" => true}}

  defp apply_event(s, %{"type" => "agent.continue_decided", "payload" => p} = e) do
    ids = Enum.map(s["pending"], & &1["operation_id"])

    if s["paused"] and p["position"] == s["continuation"] and p["resume_operations"] == ids and
         valid_continue_decision?(s, p["decision"], ids) and
         e["turn_id"] == s["turn_id"] do
      continue_decided(s, e)
    else
      {:error, :invalid_history}
    end
  end

  defp apply_event(s, %{"type" => "context.selected"}), do: {:ok, s}
  defp apply_event(_, _), do: {:error, :schema_unsupported}

  defp valid_continue_decision?(s, %{"risk" => "accepted"}, _ids),
    do: s["environment_risk"] == "unconfirmed"

  defp valid_continue_decision?(s, decision, ids),
    do:
      is_nil(s["environment_risk"]) and
        Enum.all?(decisions(decision), &(&1["operation_id"] in ids))

  defp new_member?(s, p, model?) do
    p["ordinal"] == if(model?, do: 0, else: length(s["pending"])) and
      p["step_id"] == "step-#{s["step"] + if(model?, do: 1, else: 0)}" and
      not Enum.any?(s["consumed"], &(&1["operation_id"] == p["operation_id"]))
  end

  defp consumption_position?(s, p) do
    {kind, positions} =
      case s["continuation"] do
        "model_prepared" -> {"model_result", ~w(completed reply_recorded)}
        "await_tool_results" -> {"tool_result", ["await_model_result"]}
        _ -> {nil, []}
      end

    p["join"]["position"] in positions and
      (p["consumption_kind"] == kind or
         (p["consumption_kind"] == "evidence_resolution" and
            Map.has_key?(s["resolutions"], p["operation_id"])))
  end

  defp continue_decided(s, %{"payload" => p} = e) do
    resolutions =
      Enum.reduce(
        Enum.filter(decisions(p["decision"]), &Map.has_key?(&1, "operation_id")),
        s["resolutions"],
        fn decision, acc ->
          Map.put(acc, decision["operation_id"], %{
            "resolution" => decision["resolution"],
            "decision_event_id" => e["id"],
            "seq" => e["seq"]
          })
        end
      )

    {:ok,
     %{
       s
       | "resolutions" => resolutions,
         "environment_risk" => nil,
         "paused" => false,
         "blocked" => nil,
         "continuation" => p["position"] || s["continuation"]
     }}
  end
end
