defmodule Beamlet.Recovery do
  @moduledoc """
  Pure safety and stopping rules shared by replacement, authorization and invocation.

  Safety is derived from saved authorization, verified exclusion or the original
  idempotency contract. Neither a known error nor NotFound proves no side effects.
  The two-attempt budget counts creation, including attempts never invoked.
  """

  alias Beamlet.{Binding, Execution, Intent, Report}

  @type basis :: :unstarted | :not_executed | :idempotency

  @spec basis(Execution.t(), map()) :: {:ok, basis()} | {:error, :unsafe_retry}
  def basis(execution, context) do
    cond do
      is_nil(execution.authorization) -> {:ok, :unstarted}
      not is_nil(execution.exclusion) -> {:ok, :not_executed}
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
      not no_conflicts?(intent) -> {:error, :unreconciled_conflict}
      not recovery_reason?(execution) -> {:error, :no_recovery_reason}
      true -> basis(execution, context)
    end
  end

  @spec authorize_retry(Intent.t(), Execution.t(), map(), map()) :: :ok | {:error, atom()}
  def authorize_retry(_intent, %Execution{replacement: nil}, _binding, _context), do: :ok

  def authorize_retry(intent, execution, binding, context) do
    previous = intent.executions[execution.replacement.from_execution_id]

    cond do
      not no_conflicts?(intent) -> {:error, :unreconciled_conflict}
      not same_resource?(previous.binding, binding) -> {:error, :retry_resource_mismatch}
      true -> validate_basis(previous, execution.replacement.basis, binding, context)
    end
  end

  @spec stop_required?(Intent.t(), Execution.t(), map()) :: boolean()
  def stop_required?(intent, execution, context) do
    intent.definition.policy == :stop_on_failure or map_size(intent.executions) >= 2 or
      match?({:error, _}, basis(execution, context))
  end

  @spec failure_qualified?(Intent.t(), Report.t()) :: boolean()
  def failure_qualified?(intent, report) do
    current_id = Report.execution_id(report)

    intent.current_execution_id == current_id and no_conflicts?(intent) and
      no_unresolved_risk?(intent) and not old_success?(intent, current_id)
  end

  @spec no_conflicts?(Intent.t()) :: boolean()
  def no_conflicts?(intent),
    do: Enum.all?(intent.executions, fn {_id, execution} -> not execution.conflict end)

  defp no_unresolved_risk?(intent) do
    Enum.all?(intent.executions, fn {_id, execution} ->
      is_nil(execution.authorization) or not is_nil(execution.result)
    end)
  end

  defp old_success?(intent, current_id) do
    Enum.any?(intent.executions, fn {id, execution} ->
      id != current_id and Enum.any?(execution.reports, &(&1.kind == :success))
    end)
  end

  defp recovery_reason?(execution) do
    is_nil(execution.authorization) or execution.phase == :unknown or
      not is_nil(execution.exclusion) or match?(%Report{kind: :failure}, execution.result)
  end

  defp same_resource?(nil, _binding), do: true
  defp same_resource?(original, binding), do: original["resource"] === binding["resource"]

  defp validate_basis(previous, :unstarted, _binding, _context) do
    if is_nil(previous.authorization), do: :ok, else: {:error, :unsafe_retry}
  end

  defp validate_basis(previous, :not_executed, _binding, _context) do
    if previous.exclusion, do: :ok, else: {:error, :unsafe_retry}
  end

  defp validate_basis(previous, :idempotency, binding, context) do
    valid =
      Binding.same_retry_protocol?(previous.binding, binding) and
        Binding.idempotency_valid?(previous.binding, context) and
        Binding.idempotency_valid?(binding, context)

    if valid, do: :ok, else: {:error, :idempotency_contract_unavailable}
  end
end
