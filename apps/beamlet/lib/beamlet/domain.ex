defmodule Beamlet.Domain do
  @moduledoc """
  Pure first-execution rules over an Intent snapshot.

  `new_intent/4` and `transition/3` return a proposed snapshot and History delta.
  The caller supplies trusted actor identity and Authority time. Runtime must
  authenticate and authorize commands, validate Operation-specific schemas and
  resolve trusted Handler/resource bindings before entering this module. Storage
  must load, revalidate and commit under the same Intent's transaction protection.

  Implemented commands are create, claim, renew, expire, authorize, Worker report
  and cancel. RetryOnce failures remain Open: safe replacement, query/callback
  sources and external retry proofs are not implemented yet. No command performs
  an external call or acknowledges durable storage.
  """

  alias Beamlet.{
    Definition,
    Execution,
    Identity,
    Intent,
    Lease,
    Outcome,
    Report,
    Token,
    Transition,
    Value
  }

  @type context :: %{now: integer(), actor: String.t()}
  @type command ::
          {:create_execution, String.t()}
          | {:claim, String.t(), String.t(), String.t(), non_neg_integer(), pos_integer()}
          | {:renew, Token.t(), pos_integer()}
          | {:expire, String.t()}
          | {:authorize, Token.t(), map()}
          | {:record_report, Report.t()}
          | {:cancel, Value.t()}
  @type result :: {:ok, Transition.t()} | {:error, atom()}

  @spec new_intent(String.t(), Identity.t(), Definition.t(), context()) :: result()
  def new_intent(id, %Identity{} = identity, %Definition{} = definition, context) do
    with :ok <- validate_context(context),
         true <- Identity.valid_text?(id),
         {:ok, ^identity} <- Identity.new(identity.collection, identity.namespace, identity.key),
         {:ok, ^definition} <- Definition.new(Map.from_struct(definition)) do
      idempotency_context = %{"collection" => identity.collection, "intent_id" => id}

      intent = %Intent{
        id: id,
        identity: identity,
        definition: definition,
        idempotency_context: idempotency_context
      }

      change(intent, {:created, id}, [event(:intent_created, nil, context)])
    else
      false -> {:error, :invalid_intent_id}
      error -> error
    end
  end

  @doc "Checks a keyed resubmission after Storage has located the existing identity."
  @spec resubmit(Intent.t(), Identity.t(), Definition.t()) :: {:ok, Intent.t()} | {:error, atom()}
  def resubmit(%Intent{} = intent, %Identity{} = identity, %Definition{} = definition) do
    cond do
      is_nil(identity.key) -> {:error, :unkeyed_submission}
      identity !== intent.identity -> {:error, :identity_mismatch}
      not Definition.equal?(definition, intent.definition) -> {:error, :definition_conflict}
      true -> {:ok, intent}
    end
  end

  @spec transition(Intent.t(), command(), context()) :: result()
  def transition(%Intent{} = intent, command, context) do
    with :ok <- validate_context(context), do: execute(intent, command, context)
  end

  defp execute(intent, {:create_execution, id}, context) do
    cond do
      not Identity.valid_text?(id) ->
        {:error, :invalid_execution_id}

      Map.has_key?(intent.executions, id) ->
        change(intent, {:existing_execution, id})

      intent.phase != :open ->
        {:error, :intent_closed}

      not is_nil(intent.current_execution_id) ->
        {:error, :current_execution_exists}

      true ->
        execution = %Execution{id: id}
        updated = %{put_execution(intent, execution) | current_execution_id: id}
        change(updated, {:created_execution, id}, [event(:execution_created, id, context)])
    end
  end

  defp execute(intent, {:claim, id, worker, incarnation, expected, ttl}, context) do
    with :ok <- open_current(intent, id),
         true <- Identity.valid_text?(worker) and Identity.valid_text?(incarnation),
         true <- is_integer(expected) and expected >= 0,
         {:ok, expiry} <- Lease.expiry(context.now, ttl),
         {:ok, execution} <- fetch_execution(intent, id) do
      claim(intent, execution, worker, incarnation, expected, expiry, context)
    else
      false -> {:error, :invalid_claim}
      error -> error
    end
  end

  defp execute(intent, {:renew, %Token{} = token, ttl}, context) do
    with :ok <- open_current(intent, token.execution_id),
         {:ok, execution} <- token_execution(intent, token),
         {:ok, expiry} <- Lease.expiry(context.now, ttl),
         :ok <- matching_lease(execution, token) do
      if Lease.valid?(execution.lease, token, context.now) do
        lease = %{execution.lease | expires_at: max(expiry, execution.lease.expires_at)}
        change(put_execution(intent, %{execution | lease: lease}), {:renewed, lease.expires_at})
      else
        expired_rejection(intent, execution, context)
      end
    end
  end

  defp execute(intent, {:expire, id}, context) do
    with {:ok, execution} <- fetch_execution(intent, id) do
      cond do
        is_nil(execution.lease) -> {:error, :not_claimed}
        execution.lease.invalidated -> change(intent, :already_expired)
        context.now < execution.lease.expires_at -> {:error, :lease_not_expired}
        true -> expire(intent, execution, :expired, context)
      end
    end
  end

  defp execute(intent, {:authorize, %Token{} = token, binding}, context) do
    with {:ok, execution} <- token_execution(intent, token) do
      cond do
        execution.authorization === token ->
          change(intent, {:authorized, token, execution.binding})

        not is_nil(execution.authorization) ->
          {:error, :already_authorized}

        true ->
          authorize(intent, execution, token, binding, context)
      end
    end
  end

  defp execute(intent, {:record_report, %Report{} = report}, context) do
    with :ok <- Report.validate(report),
         {:ok, execution} <- token_execution(intent, report.token),
         :ok <- report_qualified(intent, execution, report) do
      record_report(intent, execution, report, context)
    end
  end

  defp execute(intent, {:cancel, reason}, context) do
    with :ok <- Value.validate(reason) do
      if intent.phase == :closed do
        change(intent, {:existing_outcome, intent.outcome})
      else
        outcome = %Outcome{kind: :cancelled, value: reason}

        close(
          intent,
          outcome,
          [event(:outcome_accepted, nil, context, %{kind: :cancelled})],
          :cancelled
        )
      end
    end
  end

  defp execute(_intent, _command, _context), do: {:error, :unsupported_command}

  defp claim(intent, execution, worker, incarnation, expected, expiry, context) do
    generation = Lease.generation(execution.lease)

    cond do
      replay_claim?(execution.lease, worker, incarnation, expected, context.now) ->
        change(intent, {:claimed, execution.lease.token})

      expected != generation ->
        {:error, :generation_mismatch}

      execution.phase != :prepared or not is_nil(execution.authorization) ->
        {:error, :execution_not_prepared}

      active_lease?(execution.lease, context.now) ->
        {:error, :already_claimed}

      true ->
        with {:ok, next} <- Lease.next_generation(generation) do
          token = %Token{
            collection: intent.identity.collection,
            intent_id: intent.id,
            execution_id: execution.id,
            worker: worker,
            incarnation: incarnation,
            generation: next
          }

          events = expiry_events(execution, context)
          lease = %Lease{token: token, expires_at: expiry}
          updated = put_execution(intent, %{execution | lease: lease})

          change(
            updated,
            {:claimed, token},
            events ++
              [
                event(:execution_claimed, execution.id, context, %{
                  worker: worker,
                  incarnation: incarnation,
                  generation: next,
                  expires_at: expiry
                })
              ]
          )
        end
    end
  end

  defp authorize(intent, execution, token, binding, context) do
    with :ok <- open_current(intent, execution.id),
         :ok <- matching_lease(execution, token),
         :ok <- validate_binding(binding, intent.definition.operation) do
      cond do
        execution.phase != :prepared ->
          {:error, :execution_not_prepared}

        not Lease.valid?(execution.lease, token, context.now) ->
          expired_rejection(intent, execution, context)

        true ->
          updated = %{
            execution
            | phase: :start_authorized,
              authorization: token,
              binding: binding
          }

          change(put_execution(intent, updated), {:authorized, token, binding}, [
            event(:start_authorized, execution.id, context, %{
              handler: binding["handler"],
              protocol: binding["protocol"],
              generation: token.generation
            })
          ])
      end
    end
  end

  defp record_report(intent, execution, report, context) do
    if Enum.any?(execution.reports, &(&1 === report)),
      do: change(intent, :duplicate_report),
      else: record_new_report(intent, execution, report, context)
  end

  defp record_new_report(intent, execution, report, context) do
    conflict = Enum.any?(execution.reports, &conflicting?(&1, report))
    updated_intent = put_execution(intent, project_report(execution, report, conflict))

    events = [
      event(:report_recorded, execution.id, context, %{report_id: report.id, kind: report.kind})
    ]

    events =
      if conflict,
        do: events ++ [event(:report_conflict, execution.id, context, %{report_id: report.id})],
        else: events

    if terminal_report?(updated_intent, report) do
      outcome = Outcome.from_report(report)

      events =
        events ++
          [
            event(:outcome_accepted, execution.id, context, %{
              kind: outcome.kind,
              report_id: report.id
            })
          ]

      close(updated_intent, outcome, events, :report_recorded)
    else
      change(
        updated_intent,
        if(conflict, do: :conflicting_report, else: :report_recorded),
        events
      )
    end
  end

  defp project_report(execution, report, conflict) do
    updated = %{
      execution
      | reports: execution.reports ++ [report],
        conflict: execution.conflict or conflict
    }

    cond do
      updated.conflict -> updated
      report.kind == :pending and execution.phase != :resolved -> %{updated | phase: :waiting}
      report.kind in [:success, :failure] -> %{updated | phase: :resolved, result: report}
      true -> updated
    end
  end

  defp conflicting?(left, right) do
    Report.identity(left) === Report.identity(right) or
      (left.kind in [:success, :failure] and right.kind in [:success, :failure] and
         (left.kind != right.kind or left.body !== right.body))
  end

  defp terminal_report?(intent, report) do
    intent.phase == :open and intent.current_execution_id == report.token.execution_id and
      Enum.all?(intent.executions, fn {_id, execution} -> not execution.conflict end) and
      (report.kind == :success or
         (report.kind == :failure and intent.definition.policy == :stop_on_failure and
            no_unresolved_risk?(intent, report)))
  end

  defp no_unresolved_risk?(intent, report) do
    Enum.all?(intent.executions, fn {id, execution} ->
      is_nil(execution.authorization) or
        (not is_nil(execution.result) and
           (id == report.token.execution_id or execution.result.kind != :success))
    end)
  end

  defp report_qualified(intent, execution, report) do
    cond do
      report.operation != intent.definition.operation ->
        {:error, :operation_mismatch}

      execution.authorization !== report.token ->
        {:error, :unauthorized_report}

      report.kind == :pending and not is_map(execution.binding["completion"]) ->
        {:error, :pending_not_supported}

      true ->
        :ok
    end
  end

  defp validate_binding(binding, operation) when is_map(binding) and not is_struct(binding) do
    with :ok <- Value.validate(binding) do
      if binding["operation"] == operation and Identity.valid_text?(binding["handler"]) and
           Identity.valid_text?(binding["protocol"]) and is_map(binding["resource"]) and
           (is_nil(binding["completion"]) or is_map(binding["completion"])),
         do: :ok,
         else: {:error, :invalid_handler_binding}
    end
  end

  defp validate_binding(_binding, _operation), do: {:error, :invalid_handler_binding}

  defp expired_rejection(intent, execution, context) do
    if execution.lease.invalidated,
      do: {:error, :lease_expired},
      else: expire(intent, execution, {:rejected, :lease_expired}, context)
  end

  defp expire(intent, execution, reply, context) do
    phase = if execution.phase == :start_authorized, do: :unknown, else: execution.phase
    updated = %{execution | lease: %{execution.lease | invalidated: true}, phase: phase}
    change(put_execution(intent, updated), reply, expiry_events(execution, context))
  end

  defp expiry_events(%Execution{lease: %Lease{invalidated: false}} = execution, context) do
    [
      event(:lease_expired, execution.id, context, %{
        generation: execution.lease.token.generation,
        from: execution.phase,
        to: if(execution.phase == :start_authorized, do: :unknown, else: execution.phase)
      })
    ]
  end

  defp expiry_events(_execution, _context), do: []

  defp matching_lease(%Execution{lease: %Lease{token: token}}, token), do: :ok
  defp matching_lease(_execution, _token), do: {:error, :token_mismatch}

  defp active_lease?(nil, _now), do: false
  defp active_lease?(%Lease{} = lease, now), do: Lease.valid?(lease, lease.token, now)

  defp replay_claim?(%Lease{} = lease, worker, incarnation, expected, now) do
    lease.token.worker == worker and lease.token.incarnation == incarnation and
      lease.token.generation == expected + 1 and Lease.valid?(lease, lease.token, now)
  end

  defp replay_claim?(nil, _worker, _incarnation, _expected, _now), do: false

  defp token_execution(intent, token) do
    if token.collection == intent.identity.collection and token.intent_id == intent.id,
      do: fetch_execution(intent, token.execution_id),
      else: {:error, :scope_mismatch}
  end

  defp fetch_execution(intent, id) do
    case Map.fetch(intent.executions, id) do
      {:ok, execution} -> {:ok, execution}
      :error -> {:error, :execution_not_found}
    end
  end

  defp open_current(%Intent{phase: :closed}, _id), do: {:error, :intent_closed}
  defp open_current(%Intent{current_execution_id: id}, id), do: :ok
  defp open_current(_intent, _id), do: {:error, :not_current_execution}

  defp put_execution(intent, execution),
    do: %{intent | executions: Map.put(intent.executions, execution.id, execution)}

  defp close(intent, outcome, events, reply),
    do: change(%{intent | phase: :closed, outcome: outcome}, reply, events)

  defp change(intent, reply, events \\ []),
    do: {:ok, %Transition{intent: intent, reply: reply, events: events}}

  defp event(kind, execution_id, context, details \\ %{}),
    do: %{
      kind: kind,
      execution_id: execution_id,
      actor: context.actor,
      at: context.now,
      version: 1,
      details: details
    }

  defp validate_context(%{now: now, actor: actor}) when is_integer(now) do
    if now >= -9_223_372_036_854_775_808 and now <= 9_223_372_036_854_775_807 and
         Identity.valid_text?(actor),
       do: :ok,
       else: {:error, :invalid_context}
  end

  defp validate_context(_context), do: {:error, :invalid_context}
end
