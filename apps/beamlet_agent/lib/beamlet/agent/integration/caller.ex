defmodule Beamlet.Agent.Integration.Caller do
  @moduledoc "Construct bounded model invocations and opaque Tool Operations."
  alias Beamlet.Actions.Operation
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Runtime.Directory
  alias Beamlet.Runtime.Persistence

  def profile?(p) when is_map(p) do
    Map.keys(p) -- [:id, :capability, :environment, :claims, :allowed_nodes] == [] and
      is_binary(p[:id]) and byte_size(p.id) in 1..128 and String.valid?(p.id) and
      match?({:ok, _}, operation(p, %{}, 262_144))
  end

  def profile?(_), do: false

  def operation(profile, request) do
    limit = if Process.whereis(Directory), do: Directory.limits().operation_bytes, else: 262_144
    operation(profile, request, limit)
  catch
    :exit, _ -> {:error, :runtime_unavailable}
  end

  def operation(%{provider: provider, config: config} = binding, request, limit) do
    placement = Map.get(binding, :placement, %{})

    attrs =
      Map.merge(placement, %{
        kind: "agent.native",
        payload: %{
          "type" => "model",
          "provider" => provider,
          "config" => config,
          "request" => request
        },
        credentials: Map.get(binding, :credentials, %{}),
        capabilities: ["model.provider:" <> provider]
      })

    bounded(Operation.new(attrs), limit)
  end

  def operation(%{id: id, capability: capability} = profile, request, limit) do
    result =
      Operation.new(
        kind: "agent.native",
        payload: %{"profile" => id, "request" => request},
        capabilities: [capability],
        environment: Map.get(profile, :environment),
        claims: Map.get(profile, :claims, %{}),
        allowed_nodes: Map.get(profile, :allowed_nodes)
      )

    bounded(result, limit)
  end

  def operation(_, _, _), do: {:error, :invalid_profile}

  # Version the complete effective nonsecret execution configuration, not the
  # conversation/arguments or transient credentials. Never resolve an adapter here.
  defp bounded({:ok, operation}, limit) do
    description = Persistence.description(operation)
    request = operation.payload["request"]

    catalogue =
      if operation.payload["type"] == "model" and is_map(request),
        do: Map.take(request, ["catalogue"]),
        else: %{}

    payload = Map.put(description["payload"], "request", catalogue)

    with {:ok, version} <- Codec.digest(%{description | "payload" => payload}, :operation) do
      operation = %{
        operation
        | metadata: Map.put(operation.metadata, "configuration_version", version)
      }

      if :erlang.external_size(operation) <= limit,
        do: {:ok, operation},
        else: {:error, :executable_input_limit}
    end
  end

  defp bounded(error, _), do: error
end
