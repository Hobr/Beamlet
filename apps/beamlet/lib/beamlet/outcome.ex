defmodule Beamlet.Outcome do
  @moduledoc "The unique immutable authoritative result belonging to an Intent."

  alias Beamlet.{Report, Value}

  @enforce_keys [:kind, :value]
  defstruct [:kind, :value, :execution_id, :report_identity]

  @type t :: %__MODULE__{
          kind: :succeeded | :failed | :cancelled,
          value: Value.t(),
          execution_id: String.t() | nil,
          report_identity: Report.identity() | nil
        }

  @spec from_report(Report.t()) :: t()
  def from_report(%Report{kind: kind} = report) when kind in [:success, :failure] do
    %__MODULE__{
      kind: if(kind == :success, do: :succeeded, else: :failed),
      value: report.body,
      execution_id: Report.execution_id(report),
      report_identity: Report.identity(report)
    }
  end
end
