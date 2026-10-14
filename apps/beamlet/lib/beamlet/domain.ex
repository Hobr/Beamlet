defmodule Beamlet.Domain do
  @moduledoc """
  Pure execution and recovery rules over an Intent snapshot.

  `new_intent/4` and `transition/3` return a proposed snapshot and History delta.
  The caller supplies trusted actor identity and Authority time. Runtime must
  authenticate and authorize commands, validate Operation-specific schemas and
  resolve trusted Handler/resource bindings before entering this module. Storage
  must load, revalidate and commit under the same Intent's transaction protection.

  Recovery derives safety from original facts and Handler contracts. Finite
  idempotency additionally requires trusted resource contract_time, independent
  of lease time. Callback/query sources must be authenticated by their Adapters.
  No command performs an external call or acknowledges durable storage.
  """

  alias Beamlet.{
    Binding,
    Definition,
    Execution,
    Identity,
    Intent,
    Judgment,
    Lease,
    Outcome,
    Reconciliation,
    Recovery,
    Report,
    Token,
    Transition,
    Value
  }

  @type context :: %{
          required(:now) => integer(),
          required(:actor) => String.t(),
          optional(:contract_time) => non_neg_integer()
        }
  @type command ::
          {:create_execution, String.t()}
          | {:claim, String.t(), String.t(), String.t(), non_neg_integer(), pos_integer()}
          | {:renew, Token.t(), pos_integer()}
          | {:expire, String.t()}
          | {:authorize, Token.t(), map()}
          | {:record_report, Report.t()}
          | {:replace_execution, String.t(), String.t(), String.t()}
          | {:stop_known_failure, String.t()}
          | {:cancel, Value.t()}
          | {:reconcile, Beamlet.Reconciliation.Command.t(), Beamlet.Reconciliation.Policy.t(),
             %{may_submit: boolean(), may_read: boolean()}}
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
    with :ok <- validate_context(context),
         {:ok, transition} <- execute(intent, command, context) do
      updated =
        if transition.intent.judgment_revision == intent.judgment_revision,
          do: Judgment.advance(intent, transition.intent),
          else: transition.intent

      if updated.judgment_revision > 9_223_372_036_854_775_807,
        do: {:error, :judgment_revision_exhausted},
        else: {:ok, %{transition | intent: updated}}
    end
  end

  @doc """
  Checks the original grant and retry contract immediately before invocation.

  Worker must separately enforce its current incarnation and single invocation
  per grant. A saved grant can outlive lease expiry or logical cancellation;
  this check intentionally does not reinterpret those facts as external stopping.
  """
  @spec check_invocation(Intent.t(), Token.t(), context()) :: :ok | {:error, atom()}
  def check_invocation(%Intent{} = intent, %Token{} = token, context) do
    with :ok <- validate_context(context),
         {:ok, execution} <- token_execution(intent, token),
         true <- execution.authorization === token do
      Recovery.authorize_retry(intent, execution, execution.binding, context)
    else
      false -> {:error, :unauthorized_invocation}
      error -> error
    end
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
         {:ok, execution} <- report_execution(intent, report),
         :ok <- report_qualified(intent, execution, report) do
      record_report(intent, execution, report, context)
    end
  end

  defp execute(intent, {:replace_execution, old_id, new_id, reason}, context) do
    with true <- Identity.valid_text?(new_id) and Identity.valid_text?(reason),
         {:ok, execution} <- fetch_execution(intent, old_id) do
      replace_execution(intent, execution, new_id, reason, context)
    else
      false -> {:error, :invalid_replacement}
      error -> error
    end
  end

  defp execute(%Intent{phase: :closed} = intent, {:stop_known_failure, _id}, _context),
    do: change(intent, {:existing_outcome, intent.outcome})

  defp execute(intent, {:stop_known_failure, id}, context) do
    with :ok <- open_current(intent, id),
         {:ok, execution} <- fetch_execution(intent, id) do
      stop_known_failure(intent, execution, context)
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

  defp execute(intent, {:reconcile, command, policy, access}, context),
    do: Reconciliation.process(intent, command, policy, access, context)

  defp execute(_intent, _command, _context), do: {:error, :unsupported_command}

  defp replace_execution(intent, old, new_id, reason, context) do
    case Map.fetch(intent.executions, new_id) do
      {:ok, %Execution{replacement: %{from_execution_id: from, reason: ^reason}}}
      when from == old.id ->
        change(intent, {:existing_execution, new_id})

      {:ok, _execution} ->
        {:error, :execution_id_reused}

      :error ->
        build_replacement(intent, old, new_id, reason, context)
    end
  end

  defp build_replacement(intent, old, new_id, reason, context) do
    with :ok <- open_current(intent, old.id),
         {:ok, basis} <- Recovery.replacement_allowed(intent, old, new_id, context) do
      replacement = %{from_execution_id: old.id, basis: basis, reason: reason}
      fresh = %Execution{id: new_id, replacement: replacement}
      invalidated = if old.lease, do: %{old | lease: %{old.lease | invalidated: true}}, else: old
      updated = intent |> put_execution(invalidated) |> put_execution(fresh)
      updated = %{updated | current_execution_id: new_id}
      details = Map.put(replacement, :old_generation, Lease.generation(old.lease))

      change(updated, {:replaced, new_id, basis}, [
        event(:execution_replaced, new_id, context, details)
      ])
    end
  end

  defp stop_known_failure(intent, execution, context) do
    report =
      Enum.find(execution.reports, &(&1.kind == :failure and Judgment.evidence?(intent, &1)))

    cond do
      is_nil(report) ->
        {:error, :known_failure_required}

      not Recovery.stop_required?(intent, execution, context) ->
        {:error, :retry_available}

      not Recovery.failure_qualified?(intent, report) ->
        {:error, :unresolved_risk}

      true ->
        outcome = Outcome.from_report(report)

        details = %{
          kind: :failed,
          report_id: report.id,
          source_kind: Report.source_kind(report),
          reason: :stop_known_failure
        }

        close(
          intent,
          outcome,
          [event(:outcome_accepted, execution.id, context, details)],
          :failed
        )
    end
  end

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
         :ok <- Binding.validate(binding, intent.definition.operation) do
      cond do
        execution.phase != :prepared ->
          {:error, :execution_not_prepared}

        not Lease.valid?(execution.lease, token, context.now) ->
          expired_rejection(intent, execution, context)

        true ->
          authorize_ready(intent, execution, token, binding, context)
      end
    end
  end

  defp authorize_ready(intent, execution, token, binding, context) do
    with :ok <- Recovery.authorize_retry(intent, execution, binding, context) do
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

  defp record_report(intent, execution, report, context) do
    if Enum.any?(execution.reports, &(&1 === report)),
      do: change(intent, :duplicate_report),
      else: record_new_report(intent, execution, report, context)
  end

  defp record_new_report(intent, execution, report, context) do
    conflict = execution.conflict or Enum.any?(execution.reports, &conflicting?(&1, report))

    updated_intent =
      Judgment.advance(intent, put_execution(intent, project_report(execution, report, conflict)))

    events = [
      event(:report_recorded, execution.id, context, %{
        report_id: report.id,
        kind: report.kind,
        source_kind: Report.source_kind(report)
      })
    ]

    events =
      if conflict,
        do:
          events ++
            [
              event(:report_conflict, execution.id, context, %{
                report_id: report.id,
                source_kind: Report.source_kind(report)
              })
            ],
        else: events

    if terminal_report?(updated_intent, report, context) do
      outcome = Outcome.from_report(report)

      events =
        events ++
          [
            event(:outcome_accepted, execution.id, context, %{
              kind: outcome.kind,
              report_id: report.id,
              source_kind: Report.source_kind(report)
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

    if updated.conflict, do: updated, else: project_evidence(updated, report)
  end

  defp project_evidence(execution, %Report{kind: :pending}) when execution.phase != :resolved,
    do: %{execution | phase: :waiting}

  defp project_evidence(execution, %Report{kind: :not_executed} = report),
    do: %{
      execution
      | phase: :resolved,
        result: execution.result || report,
        exclusion: report.exclusion
    }

  defp project_evidence(execution, %Report{kind: kind} = report)
       when kind in [:success, :failure],
       do: %{execution | phase: :resolved, result: execution.result || report}

  defp project_evidence(execution, _report), do: execution

  defp conflicting?(left, right) do
    Report.identity(left) === Report.identity(right) or
      (left.kind in [:success, :failure] and right.kind in [:success, :failure] and
         (left.kind != right.kind or left.body !== right.body)) or
      (left.kind == :success and right.kind == :not_executed) or
      (left.kind == :not_executed and right.kind == :success)
  end

  defp terminal_report?(intent, report, context) do
    execution = intent.executions[Report.execution_id(report)]

    intent.phase == :open and intent.current_execution_id == execution.id and
      Recovery.no_conflicts?(intent) and
      Judgment.evidence?(intent, report) and
      ((report.kind == :success and Judgment.knowledge(intent, execution.id) == :success) or
         (report.kind == :failure and Recovery.stop_required?(intent, execution, context) and
            Recovery.failure_qualified?(intent, report)))
  end

  defp report_qualified(intent, execution, report) do
    if report.operation == intent.definition.operation,
      do: Report.qualified(report, execution),
      else: {:error, :operation_mismatch}
  end

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

  defp report_execution(intent, report) do
    case Report.scope(report) do
      {collection, id, execution_id}
      when collection == intent.identity.collection and id == intent.id ->
        fetch_execution(intent, execution_id)

      _ ->
        {:error, :scope_mismatch}
    end
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
    do:
      change(
        Judgment.advance(intent, %{intent | phase: :closed, outcome: outcome}),
        reply,
        events
      )

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

  defp validate_context(%{now: now, actor: actor} = context) when is_integer(now) do
    contract_time = Map.get(context, :contract_time, 0)

    if now >= -9_223_372_036_854_775_808 and now <= 9_223_372_036_854_775_807 and
         Identity.valid_text?(actor) and is_integer(contract_time) and contract_time >= 0,
       do: :ok,
       else: {:error, :invalid_context}
  end

  defp validate_context(_context), do: {:error, :invalid_context}
end
