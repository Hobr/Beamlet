defmodule Beamlet.Agent.Reducer do
  @moduledoc "Storage envelope adapter for the pure Agent reducer."
  alias Beamlet.Agent.Core.Reducer, as: Core
  alias Beamlet.Storage.{Codec, Events}

  defdelegate version(), to: Core
  defdelegate new(id), to: Core
  defdelegate decisions(payload), to: Core

  def reduce(state, event) do
    with :ok <- decode(event), do: Core.reduce(state, normalize(event))
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
    with true <- is_map(payload) and type in Events.agent_types(),
         true <- is_integer(event["seq"]) and event["seq"] > 0,
         true <- Codec.uuid?(event["id"]) and Codec.uuid?(event["scope_id"]),
         {:ok, _} <- Codec.encode(payload, :event) do
      with :ok <- validate_payload(type, payload),
           true <- event["operation_id"] == payload["operation_id"] do
        Core.decode(normalize(event))
      else
        _ -> {:error, :invalid_history}
      end
    else
      _ -> {:error, :invalid_history}
    end
  end

  def decode(%{"schema_version" => _}), do: {:error, :schema_unsupported}
  def decode(_), do: {:error, :invalid_history}

  defp validate_payload("input.accepted", _), do: :ok
  defp validate_payload(_, payload), do: Events.control(payload)

  defp normalize(%{"type" => "input.accepted", "payload" => payload} = event) do
    {:ok, digest} = Codec.digest(payload, :event)
    Map.put(event, "input_digest", digest)
  end

  defp normalize(event), do: event
end
