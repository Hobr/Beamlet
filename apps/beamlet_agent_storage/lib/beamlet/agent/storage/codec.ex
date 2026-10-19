defmodule Beamlet.Agent.Storage.Codec do
  @moduledoc "Agent encoding bounds over canonical foundation bytes."
  alias Beamlet.Storage.Codec

  @limits %{
    operation: 1_048_576,
    event: 4_194_304,
    result: 4_194_304,
    checkpoint: 4_194_304,
    command: 1_048_576
  }
  @typedoc "Owning Agent byte policy; JSON structure, identity and size checks remain at runtime."
  @type kind :: :operation | :event | :result | :checkpoint | :command
  @spec limit(kind()) :: pos_integer()
  def limit(kind), do: Map.fetch!(@limits, kind)
  @spec encode(term(), kind()) :: {:ok, binary()} | {:error, Codec.error()}
  def encode(value, kind), do: Codec.encode(value, Map.fetch!(@limits, kind))
  @spec decode(term(), kind()) :: {:ok, Codec.value()} | {:error, Codec.error()}
  def decode(value, kind), do: Codec.decode(value, Map.fetch!(@limits, kind))
  @spec digest(term(), kind()) :: {:ok, String.t()} | {:error, Codec.error()}
  def digest(value, kind), do: Codec.digest(value, Map.fetch!(@limits, kind))
  @spec hash(iodata()) :: String.t()
  defdelegate hash(value), to: Codec
  @spec uuid?(term()) :: boolean()
  defdelegate uuid?(value), to: Codec
end
