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
  def limit(kind), do: Map.fetch!(@limits, kind)
  def encode(value, kind), do: Codec.encode(value, Map.fetch!(@limits, kind))
  def decode(value, kind), do: Codec.decode(value, Map.fetch!(@limits, kind))
  def digest(value, kind), do: Codec.digest(value, Map.fetch!(@limits, kind))
  defdelegate hash(value), to: Codec
  defdelegate uuid?(value), to: Codec
end
