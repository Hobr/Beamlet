defmodule Beamlet.Report.Source do
  @moduledoc """
  Trusted callback/query source scope, independent of a Worker lease.

  The Adapter authenticates provider/account or query identity before constructing
  this value. The binding must exactly match the original authorization snapshot;
  correlation and opaque IDs are not credentials.
  """

  alias Beamlet.{Identity, Value}

  @enforce_keys [:kind, :collection, :intent_id, :execution_id, :binding]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          kind: :callback | :query,
          collection: String.t(),
          intent_id: String.t(),
          execution_id: String.t(),
          binding: %{String.t() => Value.t()}
        }

  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = source) do
    valid =
      source.kind in [:callback, :query] and Identity.valid_text?(source.collection) and
        Identity.valid_text?(source.intent_id) and Identity.valid_text?(source.execution_id) and
        is_map(source.binding) and map_size(source.binding) > 0

    if valid, do: Value.validate(source.binding), else: {:error, :invalid_report_source}
  end
end
