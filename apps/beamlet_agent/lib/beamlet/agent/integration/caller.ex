defmodule Beamlet.Agent.Integration.Caller do
  @typedoc """
  不带本地 settings 或工作区根的可移植工具路由，placement 仍由 Operation 校验。

  Portable Tool placement, without local settings or workspace roots.
  """
  @type profile :: %{
          required(:id) => binary(),
          required(:capability) => binary(),
          # Operation validates placement as bounded data, not only text labels.
          optional(:environment) => term(),
          optional(:claims) => %{optional(binary()) => pos_integer()},
          optional(:allowed_nodes) => [node()] | nil
        }
  @typep result :: {:ok, Beamlet.Actions.Operation.t()} | {:error, atom()}
  @spec profile?(term()) :: boolean()
  @spec operation(term(), term()) :: result()
  @spec operation(term(), term(), pos_integer()) :: result()
  @spec bounded(result(), pos_integer()) :: result()
  @moduledoc """
  把模型绑定或可移植工具路由转换为有界 Operation。配置版本摘要排除对话、参数和凭证；本地设置与工作区根不进入工具路由。

  Construct bounded model invocations and opaque Tool Operations.
  """
  alias Beamlet.Actions.Operation
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Runtime.Directory
  alias Beamlet.Runtime.Persistence

  @doc "验证可移植工具路由及默认完整 Operation 字节界限。"
  def profile?(p) when is_map(p) do
    Map.keys(p) -- [:id, :capability, :environment, :claims, :allowed_nodes] == [] and
      is_binary(p[:id]) and byte_size(p.id) in 1..128 and String.valid?(p.id) and
      match?({:ok, _}, operation(p, %{}, 262_144))
  end

  def profile?(_), do: false

  @doc "构造带配置摘要的模型或工具 Operation；显式 limit 形式不读取 Directory，默认形式使用当前上限，现存但不可用的 Directory 返回 runtime_unavailable。"
  def operation(profile, request) do
    limit = if Process.whereis(Directory), do: Directory.limits().operation_bytes, else: 262_144
    operation(profile, request, limit)
  catch
    :exit, _ -> {:error, :runtime_unavailable}
  end

  @doc "显式 limit 形式：按给定完整 Operation 字节上限构造，不读取 Directory；profile 形状不符返回 invalid_profile。"
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
