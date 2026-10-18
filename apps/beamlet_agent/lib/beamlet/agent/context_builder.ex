defmodule Beamlet.Agent.ContextBuilder do
  @moduledoc "Ordinary conversation policy over committed inputs and consumed accepted Results."
  alias Beamlet.Agent.Loader
  alias Beamlet.Harness.{Context, Model}
  alias Beamlet.Storage.{Codec, History, Inheritance, OperationRecords}

  def build(repo, control, catalogue) do
    with true <- length(control["timeline"]) <= 128,
         {:ok, messages} <- materialize(repo, control),
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
    else
      false -> {:error, :context_limit}
      error -> error
    end
  end

  def materialize(repo, control) do
    Enum.reduce_while(control["timeline"], {:ok, []}, fn source, {:ok, messages} ->
      with {:ok, message} <- message(repo, control, source),
           {:ok, next} <- Context.append(messages, [message]) do
        {:cont, {:ok, next}}
      else
        error -> {:halt, error}
      end
    end)
  end

  @doc "Check complete call pairing without revalidating old arguments against a newer catalogue."
  def complete_boundary(messages) do
    case Enum.reduce_while(messages, {:ok, []}, &pair/2) do
      {:ok, []} -> :ok
      _ -> {:error, :unsafe_position}
    end
  end

  defp pair(%{"role" => "assistant", "calls" => calls}, {:ok, []}) when is_list(calls),
    do: {:cont, {:ok, Enum.map(calls, & &1["id"])}}

  defp pair(%{"role" => "tool", "call_id" => id}, {:ok, [id | rest]}),
    do: {:cont, {:ok, rest}}

  defp pair(%{"role" => role}, {:ok, []}) when role in ~w(user assistant), do: {:cont, {:ok, []}}
  defp pair(_, _), do: {:halt, {:error, :unsafe_position}}

  defp message(repo, _control, %{"type" => "inherited_input"} = ref) do
    with {:ok, payload} <- Inheritance.input(repo, ref),
         do: {:ok, %{"role" => "user", "content" => payload["text"]}}
  end

  defp message(repo, _control, %{"type" => "inherited_result"} = ref) do
    with {:ok, %{"operation" => op}} <-
           OperationRecords.fetch(repo, ref["reference"]["operation_id"]),
         :ok <- Inheritance.operation(repo, op, ref["reference"]) do
      case ref["resolution"] do
        nil -> result_message(op)
        resolution -> resolved_message(op, resolution)
      end
    end
  end

  defp message(repo, control, %{"type" => "input"} = ref) do
    with {:ok, e} <- History.event(repo, control["agent_id"], ref["seq"]),
         true <- e["id"] == ref["event_id"] and e["type"] == "input.accepted",
         {:ok, digest} <- Codec.digest(e["payload"], :event),
         true <- digest == ref["digest"] do
      {:ok, %{"role" => "user", "content" => e["payload"]["text"]}}
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp message(repo, control, %{"type" => "accepted_result", "reference" => ref}) do
    with {:ok, %{"operation" => op}} <- Loader.operation(repo, control["agent_id"], ref) do
      case control["resolutions"][op["id"]] do
        nil -> result_message(op)
        resolution -> resolved_message(op, resolution)
      end
    end
  end

  def observation(result, nil) do
    if result["status"] in ~w(uncertain cancelled deadline unknown),
      do: {:error, :unresolved_execution},
      else: Jason.encode(Map.take(result, ~w(status value reason)))
  end

  def observation(result, resolution),
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
    do: model_message(result, op["description"]["payload"]["request"]["catalogue"])

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
    if Enum.all?(calls, &(is_map(&1) and Enum.sort(Map.keys(&1)) == ~w(arguments id name))) do
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
