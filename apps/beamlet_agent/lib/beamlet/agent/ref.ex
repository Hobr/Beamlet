defmodule Beamlet.Agent.Ref do
  @typedoc "Live incarnation identity; fields are intentionally readable. It is not a durable locator."
  @type t :: %__MODULE__{authority: node(), id: binary(), incarnation: reference(), pid: pid()}
  @moduledoc "Ephemeral authority-local identity. Never reconstructed after infrastructure loss."
  @enforce_keys [:authority, :id, :incarnation, :pid]
  defstruct @enforce_keys
end
