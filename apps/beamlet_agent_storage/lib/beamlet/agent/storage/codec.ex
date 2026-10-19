defmodule Beamlet.Agent.Storage.Codec do
  @moduledoc "Agent 持久化的规范 JSON 字节策略：Operation/命令 1 MiB，事件/Result/检查点 4 MiB。复用 foundation 编解码，类型标签与 JSON 安全限制在运行时校验。

Agent encoding bounds over canonical foundation bytes."
  alias Beamlet.Storage.Codec

  @limits %{
    operation: 1_048_576,
    event: 4_194_304,
    result: 4_194_304,
    checkpoint: 4_194_304,
    command: 1_048_576
  }
  @typedoc "领域编码预算标签；结构、字节限制及身份关系仍在运行时验证。

Owning Agent byte policy; JSON structure, identity and size checks remain at runtime."
  @type kind :: :operation | :event | :result | :checkpoint | :command
  @spec limit(kind()) :: pos_integer()
  @doc "返回指定 kind 的最大规范编码字节数；不支持的标签会由 Map.fetch! 拒绝。"
  def limit(kind), do: Map.fetch!(@limits, kind)
  @spec encode(term(), kind()) :: {:ok, binary()} | {:error, Codec.error()}
  @doc "按领域 kind 的字节预算校验并返回规范 JSON；非法数据返回 invalid_data，超限返回 limit。"
  def encode(value, kind), do: Codec.encode(value, Map.fetch!(@limits, kind))
  @spec decode(term(), kind()) :: {:ok, Codec.value()} | {:error, Codec.error()}
  @doc "严格解码规范 JSON 并应用领域预算；拒绝非法或超限内容。"
  def decode(value, kind), do: Codec.decode(value, Map.fetch!(@limits, kind))
  @spec digest(term(), kind()) :: {:ok, String.t()} | {:error, Codec.error()}
  @doc "按领域预算校验并计算规范 JSON 的 SHA-256 小写十六进制摘要。"
  def digest(value, kind), do: Codec.digest(value, Map.fetch!(@limits, kind))
  @spec hash(iodata()) :: String.t()
  @doc "对原始 iodata 字节计算 SHA-256；不进行 JSON 校验。"
  defdelegate hash(value), to: Codec
  @spec uuid?(term()) :: boolean()
  @doc "判断是否为规范小写 UUID 字符串。"
  defdelegate uuid?(value), to: Codec
end
