defmodule Beamlet.Agent.Integration.Handler do
  alias Beamlet.Agent.ModelBinding
  @moduledoc "Executor adapter resolving only locally installed trusted providers and Tools."
  @behaviour Beamlet.Actions.Handler
  alias Beamlet.Harness.Model

  @impl true
  def run(
        %{"type" => "model", "provider" => provider, "config" => config, "request" => request} =
          payload,
        context
      )
      when map_size(payload) == 4 do
    invocation = %{config: config, credentials: context.credentials}

    with :ok <- Model.validate_registry(context.settings.model_providers),
         {:ok, module} <- Map.fetch(context.settings.model_providers, provider),
         true <- is_map(request) and Enum.sort(Map.keys(request)) == ["catalogue", "messages"],
         native_request = %{messages: request["messages"], catalogue: request["catalogue"]},
         :ok <- Model.validate_request(native_request),
         :ok <- ModelBinding.validate(module, invocation) do
      module.complete(native_request, invocation, native(context))
    else
      _ -> {:error, :invalid_request}
    end
  rescue
    _ -> {:error, :provider_failure}
  catch
    _, _ -> {:error, :provider_failure}
  end

  def run(%{"profile" => profile, "request" => request} = payload, context)
      when map_size(payload) == 2 and is_binary(profile) and is_map(request) do
    case Map.fetch(context.settings.profiles, profile) do
      {:ok, %{type: :tool, module: module, settings: settings}} when context.credentials == %{} ->
        module.invoke(request, settings, native(context))

      _ ->
        {:error, :invalid_profile}
    end
  end

  def run(_, _), do: {:error, :invalid_request}

  defp native(context),
    do: %Beamlet.Harness.Context{progress: context.progress, cancelled?: context.cancelled?}
end
