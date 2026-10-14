defmodule BeamletRuntime.Registry do
  @moduledoc "Static trusted Handler releases. Persisted bindings select an exact release, never an arbitrary module."
  alias Beamlet.{Binding, Report}

  def new(entries) do
    ids = Enum.map(entries, fn {module, config} -> module.identity(config) end)

    if Enum.all?(ids, &Beamlet.Identity.valid_text?/1) and length(Enum.uniq(ids)) == length(ids),
      do: entries,
      else: raise(ArgumentError, "Handler identities must be valid and unique")
  end

  def validate_input(entries, definition), do: check(fn -> input_check(entries, definition) end)

  def bind(entries, intent, execution, environment, qualify \\ fn _binding -> :ok end) do
    case guarded(fn -> select_binding(entries, intent, execution, environment, qualify) end) do
      {:ok, binding} when is_map(binding) -> {:ok, binding}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_handler_reply}
    end
  end

  def resolve(entries, binding), do: guarded(fn -> resolve_binding(entries, binding) end)

  def validate_report(entries, intent, report),
    do: check(fn -> report_check(entries, intent, report) end)

  def validate_invocation(entries, intent, binding, environment) do
    guarded(fn -> invocation_check(entries, intent, binding, environment) end)
  end

  defp invocation_check(entries, intent, binding, environment) do
    with {:ok, {module, config} = entry} <- resolve(entries, binding),
         :ok <- check(fn -> module.validate_input(intent.definition, config) end),
         :ok <- check(fn -> module.validate_binding(intent, binding, environment, config) end),
         do: {:ok, entry}
  end

  defp input_check(entries, definition) do
    case Enum.filter(entries, fn {module, config} ->
           definition.operation in module.operations(config)
         end) do
      [] ->
        {:error, :operation_unavailable}

      compatible ->
        first(compatible, fn entry -> entry_input(entry, definition) end)
    end
  end

  defp select_binding(entries, intent, execution, environment, qualify) do
    candidates =
      Enum.filter(entries, fn {module, config} ->
        intent.definition.operation in module.operations(config)
      end)

    first(candidates, fn entry ->
      qualified_binding(entry, intent, execution, environment, qualify)
    end)
  end

  defp qualified_binding(entry, intent, execution, environment, qualify) do
    with {:ok, binding} <- entry_binding(entry, intent, execution, environment),
         :ok <- check(fn -> qualify.(binding) end),
         do: {:ok, binding}
  end

  defp entry_input({module, config}, definition),
    do: check(fn -> module.validate_input(definition, config) end)

  defp entry_binding({module, config}, intent, execution, environment) do
    with :ok <- entry_input({module, config}, intent.definition),
         {:ok, binding} <- module.bind(intent, execution, environment, config),
         :ok <- Binding.validate(binding, intent.definition.operation),
         true <- binding["handler"] == module.identity(config),
         :ok <- check(fn -> module.validate_binding(intent, binding, environment, config) end) do
      {:ok, binding}
    else
      false -> {:error, :handler_binding_mismatch}
      error -> error
    end
  end

  defp resolve_binding(entries, binding) do
    case Enum.find(entries, fn {module, config} ->
           module.identity(config) == binding["handler"] and
             binding["operation"] in module.operations(config)
         end) do
      nil -> {:error, :handler_unavailable}
      entry -> {:ok, entry}
    end
  end

  defp report_check(entries, intent, report) do
    with :ok <- Report.validate(report),
         {collection, id, execution_id} <- Report.scope(report),
         true <- collection == intent.identity.collection and id == intent.id,
         execution when not is_nil(execution) <- intent.executions[execution_id],
         true <- is_map(execution.binding),
         {:ok, {module, config}} <- resolve(entries, execution.binding),
         true <- report.operation == intent.definition.operation,
         :ok <-
           check(fn ->
             module.validate_result(report.operation, report.kind, report.body, config)
           end) do
      :ok
    else
      false -> {:error, :report_scope_mismatch}
      nil -> {:error, :execution_not_found}
      error -> error
    end
  end

  defp check(fun) do
    case guarded(fun) do
      :ok -> :ok
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_handler_reply}
    end
  end

  defp guarded(fun) do
    fun.()
  rescue
    _error -> {:error, :handler_unavailable}
  catch
    _kind, _reason -> {:error, :handler_unavailable}
  end

  defp first([], _fun), do: {:error, :handler_unavailable}

  defp first([entry | rest], fun) do
    case fun.(entry) do
      {:error, _reason} = error -> if rest == [], do: error, else: first(rest, fun)
      result -> result
    end
  end
end
