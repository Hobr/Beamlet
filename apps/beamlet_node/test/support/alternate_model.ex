defmodule Beamlet.Node.AlternateModel do
  @moduledoc false
  @behaviour Beamlet.Harness.Model
  alias Beamlet.Harness.Model

  def validate_invocation(%{config: config, credentials: credentials}) do
    case {config, credentials} do
      {%{"dialect" => dialect}, %{"session" => %{"bearer" => key}}}
      when map_size(config) == 1 and map_size(credentials) == 1 and dialect in ["alpha", "beta"] and
             is_binary(key) ->
        :ok

      _ ->
        {:error, :unsupported_invocation}
    end
  end

  def complete(request, invocation, context) do
    with :ok <- Model.validate_request(request), :ok <- validate_invocation(invocation) do
      send(Process.whereis(:alternate_test_observer), {:alternate_invocation, invocation})
      context.progress.(%{phase: "alternate"})
      # Distinct internal protocol, converted directly to the neutral reply.
      observations = Enum.filter(request.messages, &(&1["role"] == "tool"))

      internal =
        if observations == [],
          do: {:invoke, "alternate-call", "echo", %{"text" => "hello"}},
          else: {:answer, "finished"}

      case internal do
        {:invoke, id, name, args} ->
          {:ok,
           %{kind: :tool_calls, content: nil, calls: [%{id: id, name: name, arguments: args}]}}

        {:answer, text} ->
          {:ok, %{kind: :text, content: text, calls: []}}
      end
    end
  end
end

defmodule Beamlet.Node.ObservedTool do
  alias Beamlet.Harness.Tools.Deterministic
  @moduledoc false
  def descriptor, do: Deterministic.descriptor()

  def invoke(args, settings, context) do
    send(settings.observer, {:tool_context, context, settings, args})
    Deterministic.invoke(args, %{}, context)
  end
end
