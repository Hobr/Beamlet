defmodule Beamlet.Report do
  @moduledoc """
  Operation evidence from an authenticated Worker, callback or query Adapter.

  Worker reports carry the original token. Callback/query reports instead carry
  a Source with a complete Intent scope and original completion/query binding.
  Runtime authenticates sources and validates Operation-specific body schemas.
  NotExecuted additionally requires an Adapter-verified Exclusion, never merely
  an untrusted claim in the body. Report identity is distinct from its content.
  """

  alias Beamlet.{Exclusion, Identity, Token, Value}
  alias Beamlet.Report.Source

  @enforce_keys [:id, :operation, :kind, :body]
  defstruct [:id, :token, :source, :operation, :kind, :body, :exclusion]

  @type identity :: {Token.t() | Source.t(), String.t()}
  @type t :: %__MODULE__{
          id: String.t(),
          token: Token.t() | nil,
          source: Source.t() | nil,
          operation: String.t(),
          kind: :pending | :success | :failure | :not_found | :not_executed,
          body: Value.t(),
          exclusion: Exclusion.t() | nil
        }

  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = report) do
    with :ok <- validate_envelope(report),
         :ok <- validate_source(report),
         :ok <- validate_exclusion(report) do
      Value.validate(report.body)
    end
  end

  @spec source_kind(t()) :: :worker | :callback | :query
  def source_kind(%__MODULE__{source: %Source{kind: kind}}), do: kind
  def source_kind(%__MODULE__{source: nil}), do: :worker

  @spec identity(t()) :: identity()
  def identity(%__MODULE__{source: %Source{} = source, id: id}), do: {source, id}
  def identity(%__MODULE__{token: token, id: id}), do: {token, id}

  @spec scope(t()) :: {String.t(), String.t(), String.t()}
  def scope(%__MODULE__{source: %Source{} = source}),
    do: {source.collection, source.intent_id, source.execution_id}

  def scope(%__MODULE__{token: %Token{} = token}),
    do: {token.collection, token.intent_id, token.execution_id}

  @spec execution_id(t()) :: String.t()
  def execution_id(report), do: elem(scope(report), 2)

  @doc false
  @spec qualified(t(), Beamlet.Execution.t()) :: :ok | {:error, atom()}
  def qualified(%__MODULE__{source: nil, token: token} = report, execution) do
    cond do
      execution.authorization !== token ->
        {:error, :unauthorized_report}

      report.kind == :pending and not is_map(execution.binding["completion"]) ->
        {:error, :pending_not_supported}

      true ->
        :ok
    end
  end

  def qualified(%__MODULE__{source: %Source{} = source} = report, execution) do
    binding_key = if source.kind == :callback, do: "completion", else: "query"

    cond do
      is_nil(execution.authorization) ->
        {:error, :unauthorized_report}

      source.binding !== execution.binding[binding_key] ->
        {:error, :source_binding_mismatch}

      report.kind == :not_executed and report.exclusion.authorization !== execution.authorization ->
        {:error, :exclusion_mismatch}

      true ->
        :ok
    end
  end

  defp validate_envelope(report) do
    cond do
      not Identity.valid_text?(report.id) ->
        {:error, :invalid_report_id}

      not Identity.valid_text?(report.operation) ->
        {:error, :invalid_operation}

      report.kind not in [:pending, :success, :failure, :not_found, :not_executed] ->
        {:error, :unsupported_report_kind}

      true ->
        :ok
    end
  end

  defp validate_source(%__MODULE__{source: nil, token: %Token{}, kind: kind}) do
    if kind in [:pending, :success, :failure], do: :ok, else: {:error, :unsupported_report_kind}
  end

  defp validate_source(%__MODULE__{source: %Source{} = source, token: nil, kind: kind}) do
    with :ok <- Source.validate(source) do
      if (source.kind == :callback and kind in [:success, :failure]) or
           (source.kind == :query and kind != :pending),
         do: :ok,
         else: {:error, :unsupported_report_kind}
    end
  end

  defp validate_source(_report), do: {:error, :invalid_report_source}

  defp validate_exclusion(%__MODULE__{
         kind: :not_executed,
         source: source,
         exclusion: %Exclusion{} = proof
       }) do
    if is_struct(proof.authorization, Token) and proof.query_binding === source.binding and
         Identity.valid_text?(proof.evidence_ref),
       do: :ok,
       else: {:error, :invalid_exclusion}
  end

  defp validate_exclusion(%__MODULE__{kind: :not_executed}), do: {:error, :missing_exclusion}
  defp validate_exclusion(%__MODULE__{exclusion: nil}), do: :ok
  defp validate_exclusion(_report), do: {:error, :unexpected_exclusion}
end
