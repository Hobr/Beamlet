defmodule Beamlet.Harness.Models.Deterministic do
  @moduledoc "Deterministic neutral reply fixtures; no external calls. Config is JSON data."
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.{Context, Model}

  @impl true
  def validate_invocation(invocation) do
    with :ok <- Model.validate_invocation(invocation),
         %{config: %{"reply" => reply} = config, credentials: credentials} <- invocation,
         true <- map_size(config) == 1 and credentials == %{},
         {:ok, _} <- fixture(reply) do
      :ok
    else
      _ -> {:error, :invalid_profile}
    end
  end

  @impl true
  def complete(request, invocation, context \\ %Context{}) do
    with false <- Context.cancelled?(context),
         :ok <- validate_invocation(invocation),
         :ok <- Model.validate_request(request),
         {:ok, reply} <- fixture(invocation.config["reply"]),
         :ok <- Model.validate_reply(reply, request.catalogue) do
      Context.emit(context, %{phase: "complete"})
      {:ok, reply}
    else
      true -> {:error, :cancelled}
      error -> error
    end
  end

  defp fixture(%{"kind" => kind, "content" => content, "calls" => calls} = reply)
       when kind in ["text", "tool_calls"] and is_list(calls) and map_size(reply) == 3 do
    converted = Enum.map(calls, &fixture_call/1)

    fixture_reply(kind, content, calls, converted)
  end

  defp fixture(_), do: {:error, :invalid_reply}

  defp fixture_reply("text", content, [], _) when is_binary(content),
    do: {:ok, %{kind: :text, content: content, calls: []}}

  defp fixture_reply("tool_calls", content, calls, converted)
       when (is_nil(content) or is_binary(content)) and length(calls) in 1..8 do
    if nil in converted,
      do: {:error, :invalid_reply},
      else: {:ok, %{kind: :tool_calls, content: content, calls: converted}}
  end

  defp fixture_reply(_, _, _, _), do: {:error, :invalid_reply}

  defp fixture_call(%{"id" => id, "name" => name, "arguments" => args} = call)
       when map_size(call) == 3,
       do: %{id: id, name: name, arguments: args}

  defp fixture_call(_), do: nil
end
