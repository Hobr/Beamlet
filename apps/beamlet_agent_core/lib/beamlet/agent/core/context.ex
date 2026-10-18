defmodule Beamlet.Agent.Core.Context do
  @moduledoc "Pure conversation policy over ordered, source-bound verified materials."
  alias Beamlet.Agent.Core.Data
  alias Beamlet.Harness.Model

  def start(control) do
    if is_map(control) and Data.plain?(control) and Data.proper_list?(control["timeline"]),
      do:
        {:ok,
         %{control: control, remaining: control["timeline"], messages: [], count: 0, bytes: 2}},
      else: {:error, :invalid_reference}
  end

  @doc "Convert exactly the next selected occurrence, retaining only bounded messages."
  def append(%{remaining: [source | rest]} = acc, %{"source" => selected} = material) do
    if selected == source and valid_data?(material) and bound_material?(acc.control, material) do
      append_message(acc, rest, material)
    else
      {:error, :invalid_reference}
    end
  end

  def append(_, _), do: {:error, :invalid_reference}

  defp append_message(acc, rest, material) do
    with {:ok, message} <- message(material),
         {:ok, encoded} <- Jason.encode(message) do
      bytes = acc.bytes + byte_size(encoded) + min(acc.count, 1)

      case {acc.count + 1, bytes} do
        {count, size} when count <= 128 and size <= 1_048_576 ->
          {:ok,
           %{
             acc
             | remaining: rest,
               messages: [message | acc.messages],
               count: acc.count + 1,
               bytes: bytes
           }}

        _ ->
          {:error, :context_limit}
      end
    end
  end

  def messages(%{remaining: [], messages: messages}), do: {:ok, Enum.reverse(messages)}
  def messages(_), do: {:error, :invalid_reference}

  def finish(%{control: control} = acc, catalogue) do
    with {:ok, messages} <- messages(acc),
         :ok <- Model.validate_request(%{messages: messages, catalogue: catalogue}) do
      {:ok,
       %{
         request: %{"messages" => messages, "catalogue" => catalogue},
         sources: control["timeline"],
         policy: %{
           "policy_version" => 1,
           "instruction_version" => 1,
           "definition_version" => control["definition_version"],
           "through_seq" => control["through_seq"]
         }
       }}
    end
  end

  def build(control, catalogue, materials) do
    if is_map(control) and Data.proper_list?(control["timeline"]) and
         length(control["timeline"]) <= 128 do
      with {:ok, acc} <- accumulate(control, materials), do: finish(acc, catalogue)
    else
      {:error, :context_limit}
    end
  end

  def materialize(control, materials) do
    with {:ok, acc} <- accumulate(control, materials), do: messages(acc)
  end

  defp accumulate(control, materials) do
    with {:ok, acc} <- start(control),
         true <- Data.proper_list?(materials) do
      Enum.reduce_while(materials, {:ok, acc}, &append_next/2)
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp append_next(material, {:ok, acc}) do
    case append(acc, material) do
      {:ok, next} -> {:cont, {:ok, next}}
      error -> {:halt, error}
    end
  end

  defp valid_data?(material) do
    Enum.all?(material, fn
      {"operation", op} -> Data.fields?(op)
      {key, value} -> is_binary(key) and Data.plain?(value)
    end)
  end

  defp bound_material?(control, material) do
    allowed =
      if Map.has_key?(material, "operation"),
        do: ~w(source operation resolution),
        else: ~w(source input)

    Enum.all?(Map.keys(material), &(&1 in allowed)) and
      valid_material?(material) and resolution_matches?(control, material)
  end

  defp valid_material?(%{"source" => %{"type" => type}, "input" => %{"text" => text} = input})
       when type in ~w(input inherited_input),
       do: map_size(input) == 1 and is_binary(text) and byte_size(text) <= 65_536

  defp valid_material?(%{"source" => %{"type" => type, "reference" => ref}, "operation" => op})
       when type in ~w(accepted_result inherited_result) and is_map(ref) and is_map(op),
       do:
         Data.uuid?(op["id"]) and op["id"] == ref["operation_id"] and
           is_map(op["accepted_result"]) and
           operation_shape?(op)

  defp valid_material?(_), do: false

  defp resolution_matches?(_, %{"source" => %{"type" => "inherited_result"} = source} = material),
    do: material["resolution"] == source["resolution"]

  defp resolution_matches?(
         control,
         %{"source" => %{"type" => "accepted_result"}, "operation" => op} = material
       ),
       do:
         is_map(control["resolutions"]) and
           material["resolution"] == control["resolutions"][op["id"]]

  defp resolution_matches?(_, _), do: true

  defp operation_shape?(%{"role" => "tool", "tool_call_id" => id}), do: is_binary(id)

  defp operation_shape?(%{
         "role" => "model",
         "description" => %{"payload" => %{"request" => %{"catalogue" => catalogue}}}
       }),
       do: is_map(catalogue)

  defp operation_shape?(_), do: false

  defp message(%{"input" => input}), do: {:ok, %{"role" => "user", "content" => input["text"]}}

  defp message(%{"operation" => op} = material) do
    case material["resolution"] do
      nil -> result_message(op)
      resolution -> resolved_message(op, resolution)
    end
  end

  @doc "Check complete call pairing without revalidating old arguments against a newer catalogue."
  def complete_boundary(messages) do
    case pair_messages(messages) do
      {:ok, []} -> :ok
      _ -> {:error, :unsafe_position}
    end
  end

  defp pair_messages(messages) do
    if is_list(messages) and Data.plain?(messages),
      do: Enum.reduce_while(messages, {:ok, []}, &pair/2),
      else: {:error, :unsafe_position}
  end

  defp pair(%{"role" => "assistant", "calls" => calls}, {:ok, []}) when is_list(calls),
    do: call_ids(calls)

  defp pair(%{"role" => "tool", "call_id" => id}, {:ok, [id | rest]}),
    do: {:cont, {:ok, rest}}

  defp pair(%{"role" => role}, {:ok, []}) when role in ~w(user assistant), do: {:cont, {:ok, []}}
  defp pair(_, _), do: {:halt, {:error, :unsafe_position}}

  defp call_ids(calls) do
    if Enum.all?(calls, &(is_map(&1) and is_binary(&1["id"]))),
      do: {:cont, {:ok, Enum.map(calls, & &1["id"])}},
      else: {:halt, {:error, :unsafe_position}}
  end

  def observation(result, resolution) when is_map(result) and not is_struct(result) do
    encode_observation(result, resolution)
  rescue
    FunctionClauseError -> {:error, :invalid_reference}
  end

  def observation(_, _), do: {:error, :invalid_reference}

  defp encode_observation(result, nil) do
    if result["status"] in ~w(uncertain cancelled deadline unknown),
      do: {:error, :unresolved_execution},
      else: Jason.encode(Map.take(result, ~w(status value reason)))
  end

  defp encode_observation(result, resolution),
    do: Jason.encode(%{"accepted_status" => result["status"], "explicit_decision" => resolution})

  defp resolved_message(
         %{"role" => "tool", "tool_call_id" => id, "accepted_result" => r},
         resolution
       ) do
    with {:ok, content} <- observation(r, resolution),
         do: {:ok, %{"role" => "tool", "call_id" => id, "content" => content}}
  end

  defp resolved_message(op, resolution) do
    {:ok,
     %{
       "role" => "user",
       "content" =>
         Jason.encode!(%{
           "operation_id" => op["id"],
           "accepted_status" => op["accepted_result"]["status"],
           "explicit_decision" => resolution
         })
     }}
  end

  defp result_message(
         %{"role" => "model", "accepted_result" => %{"status" => "error"} = result} = op
       ) do
    {:ok,
     %{
       "role" => "user",
       "content" =>
         Jason.encode!(%{
           "model_operation_id" => op["id"],
           "status" => "error",
           "reason" => result["reason"]
         })
     }}
  end

  defp result_message(%{"role" => "model", "accepted_result" => result} = op),
    do: model_message(result, get_in(op, ["description", "payload", "request", "catalogue"]))

  defp result_message(%{"role" => "tool", "tool_call_id" => id, "accepted_result" => r}) do
    if r["status"] in ~w(uncertain cancelled deadline unknown),
      do: {:error, :unresolved_execution},
      else:
        {:ok,
         %{
           "role" => "tool",
           "call_id" => id,
           "content" => Jason.encode!(Map.take(r, ~w(status value reason)))
         }}
  end

  defp result_message(_), do: {:error, :invalid_reference}

  defp model_message(%{"status" => "ok", "value" => value}, catalogue) do
    with {:ok, reply} <- reply(value),
         :ok <- Model.validate_reply(reply, catalogue),
         do: {:ok, Model.assistant_message(reply)}
  end

  defp model_message(_, _), do: {:error, :unresolved_execution}

  def reply(%{"kind" => kind, "content" => content, "calls" => calls} = value)
      when map_size(value) == 3 and kind in ~w(text tool_calls) and is_list(calls) do
    if Data.plain?(value) and
         Enum.all?(calls, &(is_map(&1) and Enum.sort(Map.keys(&1)) == ~w(arguments id name))) do
      {:ok,
       %{
         kind: if(kind == "text", do: :text, else: :tool_calls),
         content: content,
         calls: Enum.map(calls, &native_call/1)
       }}
    else
      {:error, :invalid_reply}
    end
  end

  def reply(_), do: {:error, :invalid_reply}

  defp native_call(c) when is_map(c),
    do: %{id: c["id"], name: c["name"], arguments: c["arguments"]}

  defp native_call(_), do: %{id: nil, name: nil, arguments: nil}
end
