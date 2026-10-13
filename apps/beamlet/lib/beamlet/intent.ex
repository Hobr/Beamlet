defmodule Beamlet.Intent do
  @moduledoc """
  A complete domain snapshot of one Intent and its execution facts.

  Storage loads this snapshot under its transaction protection. History is
  returned as a transition delta, not replayed to reconstruct this snapshot.
  """

  alias Beamlet.{Definition, Execution, Identity, Outcome}

  @enforce_keys [:id, :identity, :definition, :idempotency_context]
  defstruct [
    :id,
    :identity,
    :definition,
    :idempotency_context,
    :current_execution_id,
    :outcome,
    phase: :open,
    executions: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          identity: Identity.t(),
          definition: Definition.t(),
          idempotency_context: %{String.t() => String.t()},
          current_execution_id: String.t() | nil,
          outcome: Outcome.t() | nil,
          phase: :open | :closed,
          executions: %{String.t() => Execution.t()}
        }
end
