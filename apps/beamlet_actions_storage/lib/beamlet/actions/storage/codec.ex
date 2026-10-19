defmodule Beamlet.Actions.Storage.Codec do
  @moduledoc "Actions persistence bounds over the canonical foundation encoder."
  alias Beamlet.Storage.Codec, as: Canonical

  @limits %{
    operation: 1_048_576,
    event: 4_194_304,
    result: 4_194_304,
    journal_artifacts: 25_165_824
  }
  @typedoc "Owning Actions byte policy over foundation JSON; bounds remain runtime checks."
  @type kind :: :operation | :event | :result | :journal_artifacts
  @spec limit(kind()) :: pos_integer()
  def limit(kind), do: Map.fetch!(@limits, kind)
  @spec encode(term(), kind()) :: {:ok, binary()} | {:error, Canonical.error()}
  def encode(value, kind \\ :event), do: Canonical.encode(value, limit(kind))
  @spec decode(term(), kind()) :: {:ok, Canonical.value()} | {:error, Canonical.error()}
  def decode(value, kind \\ :event), do: Canonical.decode(value, limit(kind))
  @spec digest(term(), kind()) :: {:ok, String.t()} | {:error, Canonical.error()}
  def digest(value, kind \\ :event), do: Canonical.digest(value, limit(kind))
  @spec uuid?(term()) :: boolean()
  defdelegate uuid?(value), to: Canonical
  @spec hash(iodata()) :: String.t()
  defdelegate hash(value), to: Canonical
end
