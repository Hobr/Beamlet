defmodule Beamlet.Agent.TraceVerifier do
  @typep object :: Beamlet.Agent.Core.Data.object()
  @typep state :: %{
           agent_id: binary(),
           operations: %{optional(binary()) => object()},
           inputs: %{optional(binary()) => object()},
           inherited: [object()],
           artifacts: %{optional(binary()) => binary()},
           missing: [object()]
         }
  @spec closure(object(), %{binary() => [object()]}, %{optional(binary()) => binary()}, [object()]) ::
          :ok | {:error, :invalid_reference}
  @spec owned_result_ref?(term(), binary(), state()) :: boolean()
  @spec result_ref?(term(), state()) :: boolean()
  @spec inherited?(term(), state()) :: boolean()
  @spec sources?(term(), state()) :: boolean()
  @spec source?(term(), object(), state()) :: boolean()
  @spec input_source?(object(), object(), object()) :: boolean()
  @spec omitted?(state(), binary(), binary()) :: boolean()
  @moduledoc false
  # 离线校验同时检查归属、来源与内容摘要；重新计算文件哈希本身不足以证明引用一致。
  alias Beamlet.Agent.Storage.Codec

  def closure(control, files, artifacts, missing) do
    state = %{
      agent_id: control["agent_id"],
      operations: Map.new(files["operations"], &{&1["operation"]["id"], &1}),
      inputs: Map.new(files["events"] ++ files["inputs"], &{&1["id"], &1}),
      inherited: control["inheritance"]["closure"],
      artifacts: artifacts,
      missing: missing
    }

    refs = control["pending"] ++ control["consumed"]

    with true <- Enum.all?(refs, &owned_result_ref?(&1, state.agent_id, state)),
         true <- Enum.all?(state.inherited, &inherited?(&1, state)),
         true <- Enum.all?(files["operations"], &sources?(&1["operation"], state)) do
      :ok
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp owned_result_ref?(%{"operation_id" => id} = ref, owner, state) do
    case state.operations[id] do
      nil -> omitted?(state, "operation", id)
      %{"operation" => op} -> op["owner_agent_id"] == owner and result_ref?(ref, state)
    end
  end

  defp owned_result_ref?(_, _, _), do: false

  defp result_ref?(%{"operation_id" => id} = ref, state) do
    case state.operations[id] do
      nil ->
        omitted?(state, "operation", id)

      %{"operation" => op, "accepted_event" => accepted} ->
        not Map.has_key?(ref, "accepted_digest") or
          (is_map(accepted) and ref["accepted_digest"] == accepted["payload"]["accepted_digest"] and
             Codec.digest(op["accepted_result"], :result) == {:ok, ref["accepted_digest"]})
    end
  end

  defp result_ref?(_, _), do: false

  defp inherited?(%{"type" => "inherited_input"} = ref, state) do
    case state.artifacts[ref["artifact_id"]] do
      nil ->
        omitted?(state, "artifact", ref["artifact_id"])

      bytes ->
        Codec.hash(bytes) == ref["digest"] and
          match?({:ok, %{"text" => _}}, Codec.decode(bytes, :event))
    end
  end

  defp inherited?(%{"type" => "inherited_result", "reference" => ref} = source, state)
       when is_map(ref) do
    case state.operations[ref["operation_id"]] do
      nil ->
        omitted?(state, "operation", ref["operation_id"])

      %{"operation" => op} ->
        op["owner_agent_id"] == source["source_agent_id"] and
          op["description_digest"] == source["description_digest"] and result_ref?(ref, state)
    end
  end

  defp inherited?(_, _), do: false

  defp sources?(%{"sources" => sources} = op, state) when is_list(sources),
    do: Enum.all?(sources, &source?(&1, op, state))

  defp sources?(_, _), do: false

  defp source?(%{"type" => "input", "event_id" => id} = ref, op, state) do
    case state.inputs[id] do
      nil ->
        Enum.any?(
          state.inherited,
          &(&1["source_agent_id"] == op["owner_agent_id"] and
              Map.take(&1, ~w(event_id seq digest)) == Map.take(ref, ~w(event_id seq digest)))
        ) or omitted?(state, "input", id)

      event ->
        input_source?(event, op, ref)
    end
  end

  defp source?(%{"type" => "accepted_result", "reference" => ref}, op, state),
    do: owned_result_ref?(ref, op["owner_agent_id"], state)

  defp source?(%{"type" => type} = ref, _op, state)
       when type in ~w(inherited_input inherited_result),
       do: ref in state.inherited and inherited?(ref, state)

  defp source?(_, _, _), do: false

  defp input_source?(event, op, ref),
    do:
      event["scope_id"] == op["owner_agent_id"] and
        event["type"] == "input.accepted" and event["seq"] == ref["seq"] and
        is_integer(op["prepared_seq"]) and event["seq"] < op["prepared_seq"] and
        Codec.digest(event["payload"], :event) == {:ok, ref["digest"]}

  defp omitted?(state, kind, id),
    do: Enum.any?(state.missing, &(&1["kind"] == kind and &1["id"] == id))
end
