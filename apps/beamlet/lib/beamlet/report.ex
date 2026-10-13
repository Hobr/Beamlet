defmodule Beamlet.Report do
  @moduledoc """
  Worker evidence associated with the original full authorization token.

  Runtime must authenticate the sender and validate the Operation's body schema
  before calling the Domain. This initial implementation accepts Worker reports;
  callback and query adapters will supply separate authenticated source bindings.
  """

  alias Beamlet.{Identity, Token, Value}

  @enforce_keys [:id, :token, :operation, :kind, :body]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          token: Token.t(),
          operation: String.t(),
          kind: :pending | :success | :failure,
          body: Value.t()
        }

  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = report) do
    cond do
      not Identity.valid_text?(report.id) -> {:error, :invalid_report_id}
      not Identity.valid_text?(report.operation) -> {:error, :invalid_operation}
      report.kind not in [:pending, :success, :failure] -> {:error, :unsupported_report_kind}
      not is_struct(report.token, Token) -> {:error, :invalid_token}
      true -> Value.validate(report.body)
    end
  end

  @spec identity(t()) :: {Token.t(), String.t()}
  def identity(%__MODULE__{} = report), do: {report.token, report.id}
end
