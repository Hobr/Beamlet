defmodule BeamletRuntime.Grant do
  @moduledoc "A local delivery of a committed authorization snapshot, never accepted from an untrusted caller."
  @enforce_keys [:token, :binding, :intent]
  defstruct @enforce_keys
  @type t :: %__MODULE__{token: Beamlet.Token.t(), binding: map(), intent: Beamlet.Intent.t()}
end
