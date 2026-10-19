defmodule Beamlet.Harness do
  @moduledoc """
  独立的中立 Model/Tool 契约库，不依赖 Actions、Runtime 或 Agent，也不自动启动进程。调用数据显式传入，工具设置与钩子保留在本地。

  Independent neutral model and Tool contracts. Invocation data is explicit; hooks and Tool settings are local.
  """
end

defmodule Beamlet.Harness.Tool do
  @moduledoc """
  原生工具行为：descriptor/0 只返回便携数据，invoke/3 才使用受信的本地设置。注册与整批校验不调用工具。

  Native Tool declaration and local invocation.
  """
  @typedoc """
  工具特有的本地设置，不应放入便携目录或模型历史。

  Tool-specific local settings and output fields stay extensible; descriptors and arguments use neutral JSON.
  """
  @type settings :: %{optional(atom() | String.t()) => term()}
  @typedoc """
  工具返回字段；集成层另行施加结果大小与安全限制。
  """
  @type output :: %{optional(atom() | String.t()) => term()}
  @doc "返回 name/description/parameters 字符串键描述，不访问网络或工作区。"
  @callback descriptor() :: Beamlet.Harness.Catalogue.descriptor()
  @doc "使用已解码的参数、本地设置和 Context 调用一次工具；返回结果 map 或安全原子错误。"
  @callback invoke(Beamlet.Harness.Model.json_object(), settings(), Beamlet.Harness.Context.t()) ::
              {:ok, output()} | {:error, atom()}
end

defmodule Beamlet.Harness.Environment do
  @moduledoc """
  便携的不透明环境标签，不能承载宿主根目录或凭据；本地组合层负责解析。

  Portable opaque environment label, containing no host root or credentials.
  """
  @enforce_keys [:id]
  defstruct [:id]

  @typedoc """
  只有 id 的环境标签；创建结构体不验证本地环境是否存在。

  Portable label resolved by the trusted local adapter; contains no host path.
  """
  @type t :: %__MODULE__{id: String.t()}
end
