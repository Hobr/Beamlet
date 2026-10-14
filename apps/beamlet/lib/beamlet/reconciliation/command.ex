defmodule Beamlet.Reconciliation.Command do
  @moduledoc "Intent-local identity shared by adoption, exclusion and withdrawal commands."
  alias Beamlet.{Identity, Reconciliation}
  alias Beamlet.Reconciliation.Decision
  @enforce_keys [:id, :decision]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}

  def new(id, %Decision{} = decision) do
    with true <- Identity.valid_text?(id), :ok <- Reconciliation.validate_decision(decision) do
      {:ok, %__MODULE__{id: id, decision: decision}}
    else
      false -> {:error, :invalid_command_id}
      error -> error
    end
  end

  def new(_id, _decision), do: {:error, :invalid_reconciliation_command}
end
