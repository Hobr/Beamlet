defmodule Beamlet.Actions.Storage.Codec do
  @moduledoc "Actions persistence bounds over the canonical foundation encoder."
  alias Beamlet.Storage.Codec, as: Canonical

  @limits %{
    operation: 1_048_576,
    event: 4_194_304,
    result: 4_194_304,
    journal_artifacts: 25_165_824
  }
  def limit(kind), do: Map.fetch!(@limits, kind)
  def encode(value, kind \\ :event), do: Canonical.encode(value, limit(kind))
  def decode(value, kind \\ :event), do: Canonical.decode(value, limit(kind))
  def digest(value, kind \\ :event), do: Canonical.digest(value, limit(kind))
  defdelegate uuid?(value), to: Canonical
  defdelegate hash(value), to: Canonical
end
