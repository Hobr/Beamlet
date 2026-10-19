defmodule Beamlet.Agent.Core.Context do
  @moduledoc """
  纯上下文策略，按 control.timeline 的已验证来源逐项转换，不读取存储、不散列或验证归属。调用者先核对摘要、所有权及继承闭包。历史模型回复按原操作目录验证，最终请求按当前目录验证。

  Pure conversation policy over ordered, source-bound verified materials.
  """
  alias Beamlet.Agent.Core.Data
  alias Beamlet.Harness.Model

  @typep object :: Data.object()
  @typep message :: Model.json_object()
  @typedoc """
  有界游标；消息逆序暂存，计数包括 JSON 列表括号与逗号。

  Ordered material cursor; messages are retained in reverse order until messages/1.
  """
  @type accumulator :: %{
          control: object(),
          remaining: [Data.value()],
          messages: [message()],
          count: non_neg_integer(),
          bytes: non_neg_integer()
        }
  @typedoc """
  完成的字符串键请求、来源列表及固定策略版本元数据。
  """
  @type built :: %{request: object(), sources: [Data.value()], policy: object()}
  @typep failure :: {:error, atom() | Jason.EncodeError.t() | Exception.t()}
  @typep accumulated :: {:ok, accumulator()} | failure()
  @typep message_result :: {:ok, message()} | failure()
  @typep pairing :: {:ok, [binary()]} | {:error, :unsafe_position}
  @typep pair_step :: {:cont, {:ok, [binary()]}} | {:halt, {:error, :unsafe_position}}
  @typedoc """
  语义验证前的已转换回复，仍允许字段值非法。

  Decoded reply before semantic Model validation; malformed field values intentionally remain representable.
  """
  @type decoded_reply :: %{
          kind: :text | :tool_calls,
          content: Data.value(),
          calls: [%{id: Data.value(), name: Data.value(), arguments: Data.value()}]
        }
  @spec start(term()) :: accumulated()
  @spec append(term(), term()) :: accumulated()
  @spec append_message(accumulator(), [Data.value()], object()) :: accumulated()
  @spec messages(term()) :: {:ok, [message()]} | failure()
  @spec finish(accumulator(), Beamlet.Harness.Catalogue.t()) :: {:ok, built()} | failure()
  @spec build(term(), Beamlet.Harness.Catalogue.t(), term()) :: {:ok, built()} | failure()
  @spec materialize(term(), term()) :: {:ok, [message()]} | failure()
  @spec accumulate(term(), term()) :: accumulated()
  @spec append_next(term(), {:ok, accumulator()}) ::
          {:cont, {:ok, accumulator()}} | {:halt, failure()}
  @spec valid_data?(object()) :: boolean()
  @spec bound_material?(object(), object()) :: boolean()
  @spec valid_material?(term()) :: boolean()
  @spec resolution_matches?(object(), object()) :: boolean()
  @spec operation_shape?(term()) :: boolean()
  @spec message(object()) :: message_result()
  @spec complete_boundary(term()) :: :ok | {:error, :unsafe_position}
  @spec pair_messages(term()) :: pairing()
  @spec pair(term(), pairing()) :: pair_step()
  @spec call_ids([term()]) :: pair_step()
  @spec observation(term(), term()) :: {:ok, binary()} | failure()
  @spec encode_observation(map(), term()) :: {:ok, binary()} | failure()
  @spec resolved_message(object(), Data.value()) :: message_result()
  @spec result_message(term()) :: message_result()
  @spec model_message(term(), Beamlet.Harness.Catalogue.t()) :: message_result()
  @spec reply(term()) :: {:ok, decoded_reply()} | {:error, :invalid_reply}
  @spec native_call(term()) :: %{id: Data.value(), name: Data.value(), arguments: Data.value()}

  @doc """
  从 control.timeline 创建空游标，不读取来源；形状非法返回 invalid_reference。
  """
  def start(control) do
    if is_map(control) and Data.plain?(control) and Data.proper_list?(control["timeline"]),
      do:
        {:ok,
         %{control: control, remaining: control["timeline"], messages: [], count: 0, bytes: 2}},
      else: {:error, :invalid_reference}
  end

  @doc """
  只接受下一次精确选中出现的材料，转换后立即检查 128 条/1 MiB 消息 JSON 限制；超限停止，不能预读后续来源。

  Convert exactly the next selected occurrence, retaining only bounded messages.
  """
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

  @doc """
  只在全部来源消费完后按原顺序返回消息；不完整游标返回 invalid_reference。
  """
  def messages(%{remaining: [], messages: messages}), do: {:ok, Enum.reverse(messages)}
  def messages(_), do: {:error, :invalid_reference}

  @doc """
  来源完成后校验当前目录和完整请求，返回 request/sources/policy；不把工具批次前缀当完整历史验证。
  """
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

  @doc """
  批量构建上下文，使用相同增量游标；timeline 超过 128 返回 context_limit，材料缺失、额外、替换或乱序返回 invalid_reference。
  """
  def build(control, catalogue, materials) do
    if is_map(control) and Data.proper_list?(control["timeline"]) and
         length(control["timeline"]) <= 128 do
      with {:ok, acc} <- accumulate(control, materials), do: finish(acc, catalogue)
    else
      {:error, :context_limit}
    end
  end

  @doc """
  按绑定顺序转换全部材料为消息；不执行 finish/2 的当前目录/请求验证。
  """
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

  @doc """
  只检查完整工具配对边界，不按新目录重验旧参数；失败为 unsafe_position。

  Check complete call pairing without revalidating old arguments against a newer catalogue.
  """
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

  @doc """
  编码接受结果的 status/value/reason；不确定、取消、期限或 unknown 状态缺少明确 resolution 时返回 unresolved_execution。显式决定与原 accepted_status 一起编码，不修改原结果。
  """
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

  @doc """
  转换精确字符串键存储回复为原生字段，不做完整语义校验；后续必须调用 Model.validate_reply/2。
  """
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
