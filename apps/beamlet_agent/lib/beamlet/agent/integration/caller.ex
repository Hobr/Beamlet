defmodule Beamlet.Agent.Integration.Caller do
  @moduledoc "Portable opaque profile routing, without executor credentials or roots."
  alias Beamlet.Actions.Operation
  alias Beamlet.Runtime.Directory

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

    case result do
      {:ok, operation} ->
        if :erlang.external_size(operation) <= limit,
          do: result,
          else: {:error, :executable_input_limit}

      error ->
        error
    end
  end

  def operation(_, _, _), do: {:error, :invalid_profile}
end
