defmodule Beamlet.Agent.ModelBinding do
  @typedoc """
  固定 provider/config 与可选瞬态 credentials、placement；适配器解析由创建 authority 拥有。

  Portable immutable provider configuration; adapter resolution belongs to the authority.
  """
  @type t :: %{
          required(:provider) => binary(),
          required(:config) => Beamlet.Harness.Model.json_object(),
          optional(:credentials) => Beamlet.Harness.Model.json_object(),
          optional(:placement) => placement()
        }
  @typedoc "模型执行所需环境、允许节点与池 claims；Runtime 最终重新校验。"
  @type placement :: %{
          optional(:environment) => binary() | nil,
          optional(:allowed_nodes) => [node()] | nil,
          optional(:claims) => %{optional(binary()) => pos_integer()}
        }
  @spec registry() :: Beamlet.Harness.Model.registry()
  @spec portable?(term()) :: boolean()
  @spec valid?(term()) :: boolean()
  @spec invocation(map()) :: %{config: term(), credentials: term()}
  @spec validate(module(), term()) :: :ok | {:error, :invalid_invocation}
  @spec validate_adapter(module(), Beamlet.Harness.Model.invocation()) ::
          :ok | {:error, :invalid_invocation}
  @moduledoc """
  验证 Agent 固定的模型绑定。父级委派只验证可移植数据；实际创建 authority 解析自身 provider 注册表并验证适配器。credentials 只在运行中传递。

  Validation of the immutable authority-owned model binding.
  """
  alias Beamlet.Actions.Operation
  alias Beamlet.Harness.Model

  @doc "读取 authority Registry 元数据中的可信模型注册表，缺失时使用内建默认表。"
  def registry do
    case Registry.meta(Beamlet.Agent.Registry, :model_providers) do
      {:ok, registry} -> registry
      _ -> Model.default_providers()
    end
  catch
    :exit, _ -> Model.default_providers()
  end

  # Delegation validates portable data here; only the creating authority resolves adapters.
  @doc "只验证可移植绑定形状、通用 invocation 和 placement，不解析适配器。"
  def portable?(binding) when is_map(binding) do
    with true <- Map.keys(binding) -- [:provider, :config, :credentials, :placement] == [],
         true <- Model.provider_id?(binding[:provider]),
         :ok <- Model.validate_invocation(invocation(binding)),
         placement <- Map.get(binding, :placement, %{}),
         true <-
           is_map(placement) and
             Map.keys(placement) -- [:environment, :allowed_nodes, :claims] == [],
         {:ok, _} <- Operation.new(Map.merge(%{kind: "agent.native"}, placement)) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  def portable?(_), do: false

  @doc "在 portable? 之后通过当前 authority 注册表解析并验证适配器。"
  def valid?(binding) do
    with true <- portable?(binding),
         {:ok, module} <- Map.fetch(registry(), binding.provider),
         :ok <- validate_adapter(module, invocation(binding)) do
      true
    else
      _ -> false
    end
  end

  defp invocation(binding),
    do: %{config: binding[:config], credentials: Map.get(binding, :credentials, %{})}

  @doc "先做通用 invocation 校验，再调用本地适配器验证，失败统一 invalid_invocation。"
  def validate(module, invocation) do
    with :ok <- Model.validate_invocation(invocation),
         :ok <- validate_adapter(module, invocation) do
      :ok
    else
      _ -> {:error, :invalid_invocation}
    end
  end

  defp validate_adapter(module, invocation) do
    case module.validate_invocation(invocation) do
      :ok -> :ok
      _ -> {:error, :invalid_invocation}
    end
  rescue
    _ -> {:error, :invalid_invocation}
  catch
    _, _ -> {:error, :invalid_invocation}
  end
end
