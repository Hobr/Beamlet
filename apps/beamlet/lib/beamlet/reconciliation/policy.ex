defmodule Beamlet.Reconciliation.Policy do
  @moduledoc """
  Authority-checked facts, never supplied by an untrusted command.
  Lists represent finite sets. A resolution is an exact list of evidence items;
  a withdrawal is an exact list of supersession references. Rule versions denote
  checked semantic definitions, not Handler releases or Caller planner versions.
  """
  defstruct operators: [], registered_rules: [], excludable: [], resolutions: [], withdrawals: []
  @type t :: %__MODULE__{}
end
