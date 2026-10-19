defmodule Beamlet.Actions.Storage.Codec do
  @moduledoc "Actions 持久化的规范 JSON 字节策略：Operation 1 MiB、事件与 Result 各 4 MiB、日志附件 24 MiB。底层编码、摘要和安全校验复用 foundation；kind 必须为受支持标签。

Actions persistence bounds over the canonical foundation encoder."
  alias Beamlet.Storage.Codec, as: Canonical

  @limits %{
    operation: 1_048_576,
    event: 4_194_304,
    result: 4_194_304,
    journal_artifacts: 25_165_824
  }
  @typedoc "领域编码预算标签；结构、字节限制及身份关系仍在运行时验证。

Owning Actions byte policy over foundation JSON; bounds remain runtime checks."
  @type kind :: :operation | :event | :result | :journal_artifacts
  @spec limit(kind()) :: pos_integer()
  @doc "返回指定 kind 的最大规范编码字节数；不支持的标签会由 Map.fetch! 拒绝。"
  def limit(kind), do: Map.fetch!(@limits, kind)
  @spec encode(term(), kind()) :: {:ok, binary()} | {:error, Canonical.error()}
  @doc "按领域 kind 的字节预算校验并返回规范 JSON；非法数据返回 invalid_data，超限返回 limit。"
  def encode(value, kind \\ :event), do: Canonical.encode(value, limit(kind))
  @spec decode(term(), kind()) :: {:ok, Canonical.value()} | {:error, Canonical.error()}
  @doc "严格解码规范 JSON 并应用领域预算；拒绝非法或超限内容。"
  def decode(value, kind \\ :event), do: Canonical.decode(value, limit(kind))
  @spec digest(term(), kind()) :: {:ok, String.t()} | {:error, Canonical.error()}
  @doc "按领域预算校验并计算规范 JSON 的 SHA-256 小写十六进制摘要。"
  def digest(value, kind \\ :event), do: Canonical.digest(value, limit(kind))
  @spec uuid?(term()) :: boolean()
  @doc "判断是否为规范小写 UUID 字符串。"
  defdelegate uuid?(value), to: Canonical
  @spec hash(iodata()) :: String.t()
  @doc "对原始 iodata 字节计算 SHA-256；不进行 JSON 校验。"
  defdelegate hash(value), to: Canonical
end
