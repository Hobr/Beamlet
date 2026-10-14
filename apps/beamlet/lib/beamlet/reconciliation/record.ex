defmodule Beamlet.Reconciliation.Record do
  @moduledoc "Immutable original command and committed result or durable domain rejection."
  @enforce_keys [:command, :status, :result]
  defstruct @enforce_keys ++ [decision_index: nil]
  @type t :: %__MODULE__{}
end
