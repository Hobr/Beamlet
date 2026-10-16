defmodule Beamlet.Agent.Integration.Handler do
  @moduledoc "Executor-only native adapter. Executable modules and settings are local registration data."
  @behaviour Beamlet.Actions.Handler
  alias Beamlet.Harness.Models.OpenAICompatible
  @impl true
  def run(%{"profile" => profile, "request" => request} = payload, context)
      when map_size(payload) == 2 and is_binary(profile) and is_map(request) do
    native = %Beamlet.Harness.Context{progress: context.progress, cancelled?: context.cancelled?}

    case Map.fetch(context.settings, profile) do
      {:ok, %{type: :model, module: module, settings: settings}} ->
        complete(module, request, settings, native)

      {:ok, %{type: :tool, module: module, settings: settings}} ->
        module.invoke(request, settings, native)

      _ ->
        {:error, :invalid_profile}
    end
  end

  def run(_, _), do: {:error, :invalid_request}

  defp complete(module, request, settings, native) do
    if Enum.sort(Map.keys(request)) == ["catalogue", "messages"] do
      native_request = %{messages: request["messages"], catalogue: request["catalogue"]}

      with :ok <- OpenAICompatible.validate_request(native_request) do
        module.complete(native_request, settings, native)
      end
    else
      {:error, :invalid_request}
    end
  end
end
