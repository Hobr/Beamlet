defmodule Beamlet.Agent.Ref do
  @moduledoc "Ephemeral authority-local identity. Never reconstructed after infrastructure loss."
  @enforce_keys [:authority, :id, :incarnation, :pid]
  defstruct @enforce_keys
end
