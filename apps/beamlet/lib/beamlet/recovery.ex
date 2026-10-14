defmodule Beamlet.Recovery do
  @moduledoc """
  Pure safety and stopping rules shared by replacement, authorization and invocation.

  Recovery uses saved authorization, verified exclusion, the original idempotency
  contract, or an explicit immutable acceptance of repeat risk. The latter allows
  repeated effects and does not establish non-execution. Neither an error nor
  NotFound proves no side effects.
  The two-attempt budget counts creation, including attempts never invoked.
  """

  alias Beamlet.{Binding, Execution, Intent, Judgment, Report}

  @type basis :: :unstarted | :not_executed | :idempotency | :repeat_accepted

  @doc "Recovery basis requires the Intent's current evidence interpretation."
  @spec basis(Intent.t(), Execution.t(), map()) :: {:ok, basis()} | {:error, :unsafe_retry}
  def basis(intent, execution, context) do
    cond do
      is_nil(execution.authorization) -> {:ok, :unstarted}
      Judgment.knowledge(intent, execution.id) == :not_executed -> {:ok, :not_executed}
      intent.definition.repeat_accepted -> {:ok, :repeat_accepted}
      Binding.idempotency_valid?(execution.binding, context) -> {:ok, :idempotency}
      true -> {:error, :unsafe_retry}
    end
  end

  @spec replacement_allowed(Intent.t(), Execution.t(), String.t(), map()) ::
          {:ok, basis()} | {:error, atom()}
  def replacement_allowed(intent, execution, new_id, context) do
    cond do
      intent.definition.policy != :retry_once -> {:error, :retry_disabled}
      map_size(intent.executions) >= 2 -> {:error, :retry_budget_exhausted}
      Map.has_key?(intent.executions, new_id) -> {:error, :execution_id_reused}
      not recovery_reason?(intent, execution) -> {:error, :no_recovery_reason}
      true -> basis(intent, execution, context)
    end
  end

  @spec authorize_retry(Intent.t(), Execution.t(), map(), map()) :: :ok | {:error, atom()}
  def authorize_retry(_intent, %Execution{replacement: nil}, _binding, _context), do: :ok

  def authorize_retry(intent, execution, binding, context) do
    previous = intent.executions[execution.replacement.from_execution_id]

    if same_resource?(previous.binding, binding),
      do: validate_basis(intent, previous, execution.replacement.basis, binding, context),
      else: {:error, :retry_resource_mismatch}
  end

  @spec stop_required?(Intent.t(), Execution.t(), map()) :: boolean()
  def stop_required?(intent, execution, context) do
    intent.definition.policy == :stop_on_failure or map_size(intent.executions) >= 2 or
      match?({:error, _}, basis(intent, execution, context))
  end

  @spec failure_qualified?(Intent.t(), Report.t()) :: boolean()
  def failure_qualified?(intent, report) do
    current_id = Report.execution_id(report)

    report.kind == :failure and intent.current_execution_id == current_id and
      Judgment.knowledge(intent, current_id) == :failure and Judgment.evidence?(intent, report) and
      no_conflicts?(intent) and
      Judgment.no_unresolved_risk?(intent) and not Judgment.old_success?(intent, current_id)
  end

  @spec no_conflicts?(Intent.t()) :: boolean()
  def no_conflicts?(intent), do: Judgment.no_conflicts?(intent)

  defp recovery_reason?(intent, execution) do
    is_nil(execution.authorization) or execution.phase == :unknown or
      Judgment.knowledge(intent, execution.id) in [:failure, :not_executed]
  end

  defp same_resource?(nil, _binding), do: true
  defp same_resource?(original, binding), do: original["resource"] === binding["resource"]

  defp validate_basis(intent, _previous, :repeat_accepted, _binding, _context) do
    if intent.definition.repeat_accepted, do: :ok, else: {:error, :unsafe_retry}
  end

  defp validate_basis(_intent, previous, :unstarted, _binding, _context) do
    if is_nil(previous.authorization), do: :ok, else: {:error, :unsafe_retry}
  end

  defp validate_basis(intent, previous, :not_executed, _binding, _context) do
    if Judgment.knowledge(intent, previous.id) == :not_executed,
      do: :ok,
      else: {:error, :unsafe_retry}
  end

  defp validate_basis(_intent, previous, :idempotency, binding, context) do
    valid =
      Binding.same_retry_protocol?(previous.binding, binding) and
        Binding.idempotency_valid?(previous.binding, context) and
        Binding.idempotency_valid?(binding, context)

    if valid, do: :ok, else: {:error, :idempotency_contract_unavailable}
  end
end
