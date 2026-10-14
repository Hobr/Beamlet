defmodule BeamletRuntime.Coordinator do
  @moduledoc """
  Trusted local Runtime facade, scoped to one configured authority collection.

  This capability is application configuration, not a client message or network
  authentication protocol. Only trusted local application code receives it. Remote
  authentication, ACLs and wire messages require a separate Transport Adapter.
  No ephemeral Coordinator process owns facts; multiple facades may share a Repo.
  Handler registration and resource validation are rechecked inside SQL for new
  authorizations; external invoke/query/verification never run inside SQL.
  """
  alias Beamlet.{Domain, Identity, Recovery, Report, Token}
  alias BeamletRuntime.{Grant, Registry}
  alias BeamletRuntime.Storage.{Commit, SQLite}

  @enforce_keys [:repo, :collection, :actor, :handlers]
  defstruct [:repo, :collection, :actor, :handlers, ttl: 30_000, storage_options: []]

  def new(opts) do
    coordinator = struct!(__MODULE__, Map.new(opts))

    unless Identity.valid_text?(coordinator.collection) and
             Identity.valid_text?(coordinator.actor) and is_integer(coordinator.ttl) and
             coordinator.ttl > 0,
           do: raise(ArgumentError, "invalid Runtime scope, actor or lease TTL")

    %{coordinator | handlers: Registry.new(coordinator.handlers)}
  end

  def submit(c, identity, definition) do
    if identity.collection == c.collection do
      opts =
        Keyword.put(c.storage_options, :definition_validator, fn original ->
          Registry.validate_input(c.handlers, original)
        end)

      SQLite.submit(c.repo, identity, definition, c.actor, opts)
    else
      {:error, :collection_mismatch}
    end
  end

  def read(c, id), do: SQLite.read(c.repo, c.collection, id)

  def discover(c, cursor \\ "", limit \\ 100),
    do: SQLite.discover(c.repo, c.collection, cursor, limit)

  def cancel(c, id, reason), do: command(c, id, {:cancel, reason})

  def prepare(c, id) do
    checked(c, id, fn intent, _context ->
      {:ok, {:create_execution, intent.current_execution_id || Ecto.UUID.generate()}}
    end)
  end

  def claim(c, id, execution_id, worker, incarnation, generation),
    do: command(c, id, {:claim, execution_id, worker, incarnation, generation, c.ttl})

  def authorize(c, %Token{collection: collection} = token, environment)
      when collection == c.collection do
    checked(c, token.intent_id, fn intent, context ->
      authorization_command(c, intent, token, environment, context)
    end)
  end

  def authorize(_c, _token, _environment), do: {:error, :collection_mismatch}

  defp authorization_command(c, intent, token, environment, context) do
    case intent.executions[token.execution_id] do
      nil ->
        {:error, :execution_not_found}

      %{authorization: authorization, binding: binding} when authorization === token ->
        {:ok, {:authorize, token, binding}}

      execution ->
        qualify = fn binding -> authorization_qualified(intent, token, binding, context) end

        with {:ok, binding} <- Registry.bind(c.handlers, intent, execution, environment, qualify),
             do: {:ok, {:authorize, token, binding}}
    end
  end

  defp authorization_qualified(intent, token, binding, context) do
    case Domain.transition(intent, {:authorize, token, binding}, context) do
      {:ok, _transition} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def grant(%Commit{reply: {:authorized, token, binding}, facts: facts}),
    do: {:ok, %Grant{token: token, binding: binding, intent: facts.intent}}

  def grant(%Commit{reply: {:rejected, reason}}), do: {:error, reason}
  def grant(_commit), do: {:error, :authorization_required}

  def renew(c, token), do: command(c, token.intent_id, {:renew, token, c.ttl})
  def expire(c, id, execution_id), do: command(c, id, {:expire, execution_id})

  @doc "Evaluate one recovery action under protection; unsafe uncertainty remains Open."
  def recover(c, id) do
    checked(c, id, fn intent, context ->
      execution = intent.executions[intent.current_execution_id]
      recovery_command(intent, execution, context)
    end)
  end

  def worker_report(c, %Report{source: nil} = report), do: store_report(c, report)
  def worker_report(_c, _report), do: {:error, :worker_report_required}

  def query(c, id, execution_id), do: evidence(c, id, execution_id, :query, nil, nil)

  def callback(c, id, execution_id, raw, transport_context),
    do: evidence(c, id, execution_id, :callback, raw, transport_context)

  def invocation_context(c) do
    context = %{now: System.system_time(:millisecond), actor: c.actor}

    case Keyword.get(c.storage_options, :contract_clock) do
      nil -> context
      clock -> Map.put(context, :contract_time, clock.())
    end
  end

  defp recovery_command(_intent, nil, _context), do: {:error, :execution_not_found}

  defp recovery_command(intent, execution, context) do
    cond do
      execution.lease && not execution.lease.invalidated &&
          context.now >= execution.lease.expires_at ->
        {:ok, {:expire, execution.id}}

      match?(%Report{kind: :failure}, execution.result) and
          Recovery.stop_required?(intent, execution, context) ->
        {:ok, {:stop_known_failure, execution.id}}

      execution.phase in [:unknown, :resolved] ->
        {:ok, {:replace_execution, execution.id, Ecto.UUID.generate(), "runtime_recovery"}}

      true ->
        {:error, :no_recovery_reason}
    end
  end

  defp evidence(c, id, execution_id, kind, raw, transport_context) do
    with {:ok, facts} <- read(c, id),
         execution when not is_nil(execution) <- facts.intent.executions[execution_id],
         true <- is_map(execution.binding),
         :ok <- evidence_supported(execution, kind),
         {:ok, {module, config}} <- Registry.resolve(c.handlers, execution.binding),
         {:ok, report} <-
           adapter_evidence(module, config, facts.intent, execution, kind, raw, transport_context),
         :ok <- Report.validate(report),
         true <-
           Report.source_kind(report) == kind and
             Report.scope(report) == {c.collection, id, execution_id} do
      store_report(c, report)
    else
      nil -> {:error, :execution_not_found}
      false -> {:error, :invalid_evidence_source}
      error -> error
    end
  end

  defp evidence_supported(execution, kind) do
    key = if kind == :query, do: "query", else: "completion"

    cond do
      is_nil(execution.authorization) -> {:error, :authorization_required}
      is_map(execution.binding[key]) -> :ok
      kind == :query -> {:error, :query_not_supported}
      true -> {:error, :callback_not_supported}
    end
  end

  defp adapter_evidence(module, config, intent, execution, :query, _raw, _context) do
    safe_evidence(fn ->
      if function_exported?(module, :query, 3),
        do: module.query(intent, execution, config),
        else: {:error, :query_not_supported}
    end)
  end

  defp adapter_evidence(module, config, intent, execution, :callback, raw, context) do
    safe_evidence(fn ->
      if function_exported?(module, :verify_callback, 4),
        do: module.verify_callback(intent, execution, {raw, context}, config),
        else: {:error, :callback_not_supported}
    end)
  end

  defp safe_evidence(fun) do
    case fun.() do
      {:ok, %Report{}} = evidence -> evidence
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_adapter_reply}
    end
  rescue
    _error -> {:error, :adapter_unavailable}
  catch
    _kind, _reason -> {:error, :adapter_unavailable}
  end

  defp store_report(c, report) do
    with :ok <- Report.validate(report),
         {collection, id, _execution_id} <- Report.scope(report),
         true <- collection == c.collection do
      checked(c, id, fn intent, _context -> report_command(c, intent, report) end)
    else
      false -> {:error, :collection_mismatch}
      error -> error
    end
  end

  defp report_command(c, intent, report) do
    with :ok <- Registry.validate_report(c.handlers, intent, report),
         do: {:ok, {:record_report, report}}
  end

  defp checked(c, id, prepare),
    do: SQLite.checked_command(c.repo, c.collection, id, c.actor, prepare, c.storage_options)

  defp command(c, id, command),
    do: SQLite.command(c.repo, c.collection, id, command, c.actor, c.storage_options)
end
