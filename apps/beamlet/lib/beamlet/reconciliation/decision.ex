defmodule Beamlet.Reconciliation.Decision do
  @moduledoc "Immutable proposal over exact stored reports and a reviewed judgment revision."
  @enforce_keys [:kind, :report, :actor, :basis, :reviewed_revision]
  defstruct @enforce_keys ++ [evidence: [], supersedes: []]
  @type t :: %__MODULE__{}
end
