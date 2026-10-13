defmodule Beamlet.Execution do
  @moduledoc """
  One execution attempt. Phase describes protocol knowledge, independently of
  current-result eligibility, lease validity and evidence conflicts.
  """

  alias Beamlet.{Exclusion, Lease, Report, Token, Value}

  @enforce_keys [:id]
  defstruct [
    :id,
    :lease,
    :authorization,
    :binding,
    :result,
    :exclusion,
    :replacement,
    phase: :prepared,
    conflict: false,
    reports: []
  ]

  @type phase :: :prepared | :start_authorized | :waiting | :unknown | :resolved
  @type t :: %__MODULE__{
          id: String.t(),
          lease: Lease.t() | nil,
          authorization: Token.t() | nil,
          binding: Value.t(),
          result: Report.t() | nil,
          exclusion: Exclusion.t() | nil,
          replacement:
            %{from_execution_id: String.t(), basis: Beamlet.Recovery.basis(), reason: String.t()}
            | nil,
          phase: phase(),
          conflict: boolean(),
          reports: [Report.t()]
        }
end
