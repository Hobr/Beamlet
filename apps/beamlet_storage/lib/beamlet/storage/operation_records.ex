defmodule Beamlet.Storage.OperationRecords do
  @moduledoc """
  Atomic Operation transactions: immutable preparation with at most one attempt,
  dispatch claim, receipt evidence and single accepted Result. The facade never
  sends an admit, selects a target or accepts caller validation: identity,
  description schema, attempt identity, version/generation and stored references
  are checked inside the transaction. A late or conflicting receipt becomes
  evidence/resolution, never a second accepted Result.
  """
  import Ecto.Query
  alias Beamlet.Storage.{Artifacts, Codec, Records}
  alias Beamlet.Storage.Schema.{Agent, Execution, ExecutionEvidence, Operation}

  @description_keys ~w(kind protocol_version payload refs budget claims safety)
  @description_required ~w(kind protocol_version payload)
  @max_artifacts 1024

  def prepare(repo, attrs) do
    with {:ok, input} <- validate_prepare(attrs) do
      Records.transact(repo, fn -> write_prepare(repo, input) end)
    end
  end

  def claim_dispatch(repo, attrs) do
    with {:ok, input} <- validate_claim(attrs) do
      Records.transact(repo, fn -> write_claim(repo, input) end)
    end
  end

  def record_evidence(repo, attrs) do
    with {:ok, input} <- validate_evidence(attrs) do
      Records.transact(repo, fn -> write_evidence(repo, input) end)
    end
  end

  def accept_result(repo, attrs) do
    with {:ok, input} <- validate_accept(attrs) do
      Records.transact(repo, fn -> write_accept(repo, input) end)
    end
  end

  def fetch(repo, operation_id) do
    with {:ok, id} <- Records.uuid(operation_id) do
      Beamlet.Storage.Transaction.read(fn ->
        case repo.get(Operation, id, log: false) do
          nil ->
            {:error, :conflict}

          operation ->
            {:ok,
             %{
               "operation" => Records.plain(operation),
               "attempt" => Records.plain(attempt_for(repo, id))
             }}
        end
      end)
    end
  end

  ## Preparation

  defp validate_prepare(attrs) do
    with {:ok, _} <- Records.fields(attrs, [:operation, :event], [:attempt, :agent]),
         {:ok, operation} <- operation(attrs[:operation]),
         {:ok, attempt} <- attempt(attrs[:attempt]),
         {:ok, agent} <- agent(attrs[:agent]),
         {:ok, event} <- Records.event_input(attrs[:event]),
         :ok <- owner_pair(operation, agent) do
      {:ok, %{operation: operation, attempt: attempt, agent: agent, event: event}}
    end
  end

  defp operation(operation) do
    with {:ok, _} <-
           Records.fields(
             operation,
             [:id, :description],
             [:owner_agent_id, :turn_id, :tool_call_id, :ordinal]
           ),
         {:ok, id} <- Records.uuid(operation[:id]),
         {:ok, description} <- description(operation[:description]),
         {:ok, owner} <- Records.optional_uuid(operation[:owner_agent_id]),
         {:ok, turn} <- Records.optional_uuid(operation[:turn_id]),
         {:ok, tool_call_id} <- Records.optional_text(operation[:tool_call_id], 255),
         {:ok, ordinal} <- optional_count(operation[:ordinal]),
         {:ok, digest} <- digest_of(description, :operation) do
      {:ok,
       %{
         id: id,
         description: description,
         description_digest: digest,
         owner_agent_id: owner,
         turn_id: turn,
         tool_call_id: tool_call_id,
         ordinal: ordinal
       }}
    end
  end

  # Stage-A Operation envelope: explicit, versioned keys only. Credentials are
  # structurally rejected by the codec; references stay secret/profile refs.
  defp description(description) do
    cond do
      not is_map(description) or is_struct(description) or description == %{} ->
        {:error, :invalid_data}

      not Enum.all?(Map.keys(description), &(&1 in @description_keys)) ->
        {:error, :invalid_data}

      not Enum.all?(@description_required, &Map.has_key?(description, &1)) ->
        {:error, :invalid_data}

      not is_map(description["payload"]) or is_struct(description["payload"]) ->
        {:error, :invalid_data}

      not is_integer(description["protocol_version"]) or description["protocol_version"] < 1 ->
        {:error, :invalid_data}

      true ->
        with {:ok, _kind} <- Records.text(description["kind"], 255),
             {:ok, description} <- Records.json(description, :operation) do
          {:ok, description}
        end
    end
  end

  defp attempt(nil), do: {:ok, nil}

  defp attempt(attempt) do
    with {:ok, _} <-
           Records.fields(attempt, [:attempt_id, :executor_id, :executor_boot_id, :budget], []),
         {:ok, attempt_id} <- Records.uuid(attempt[:attempt_id]),
         {:ok, executor_id} <- Records.uuid(attempt[:executor_id]),
         {:ok, boot_id} <- Records.uuid(attempt[:executor_boot_id]),
         {:ok, budget} <- Records.json(attempt[:budget], :event) do
      {:ok,
       %{
         attempt_id: attempt_id,
         executor_id: executor_id,
         executor_boot_id: boot_id,
         budget: budget
       }}
    end
  end

  defp agent(nil), do: {:ok, nil}

  defp agent(agent) do
    with {:ok, _} <- Records.fields(agent, [:expected_version, :expected_generation], []),
         {:ok, version} <- Records.count(agent[:expected_version]),
         {:ok, generation} <- Records.count(agent[:expected_generation]) do
      {:ok, %{expected_version: version, expected_generation: generation}}
    end
  end

  defp owner_pair(%{owner_agent_id: nil, turn_id: nil}, nil), do: :ok
  defp owner_pair(%{owner_agent_id: nil, turn_id: nil}, %{}), do: {:error, :invalid_data}

  defp owner_pair(%{owner_agent_id: owner, turn_id: turn}, %{})
       when not is_nil(owner) and not is_nil(turn),
       do: :ok

  defp owner_pair(_, _), do: {:error, :invalid_data}

  defp validate_claim(attrs) do
    with {:ok, _} <- Records.fields(attrs, [:operation_id, :attempt_id, :expected_version], []),
         {:ok, operation_id} <- Records.uuid(attrs[:operation_id]),
         {:ok, attempt_id} <- Records.uuid(attrs[:attempt_id]),
         {:ok, version} <- Records.count(attrs[:expected_version]) do
      {:ok, %{operation_id: operation_id, attempt_id: attempt_id, expected_version: version}}
    end
  end

  defp write_prepare(repo, input) do
    case repo.get(Operation, input.operation.id, log: false) do
      %Operation{} = stored ->
        replay_prepare(repo, stored, input)

      nil ->
        insert_prepare(repo, input)
    end
  end

  defp replay_prepare(repo, stored, input) do
    attempt = attempt_for(repo, stored.id)

    cond do
      stored.description_digest != input.operation.description_digest ->
        {:error, :conflict}

      not same_attempt?(attempt, input.attempt) ->
        {:error, :conflict}

      true ->
        {:ok, prepare_response(stored, attempt)}
    end
  end

  defp same_attempt?(nil, nil), do: true
  defp same_attempt?(nil, _attempt), do: false
  defp same_attempt?(_stored, nil), do: false

  defp same_attempt?(stored, attempt) do
    stored.attempt_id == attempt.attempt_id and stored.executor_id == attempt.executor_id and
      stored.executor_boot_id == attempt.executor_boot_id
  end

  defp insert_prepare(repo, input) do
    operation = input.operation

    with {:ok, seq, scope} <- prepare_history(repo, input),
         {:ok, _operation} <- Records.insert(repo, operation_changeset(operation, seq)),
         {:ok, attempt} <- insert_attempt(repo, operation, input.attempt),
         {:ok, _event} <-
           Records.insert(
             repo,
             event_changeset(input.event, scope, seq, %{operation_id: operation.id})
           ) do
      {:ok,
       %{
         "operation_id" => operation.id,
         "description_digest" => operation.description_digest,
         "history_seq" => seq,
         "lock_version" => 0,
         "attempt_id" => attempt && attempt.attempt_id,
         "dispatch_state" => attempt && attempt.dispatch_state
       }}
    end
  end

  # Owned Operations share the Agent's history order; independent Operations own
  # their own sequence and need no Agent version.
  defp prepare_history(_repo, %{operation: %{owner_agent_id: nil} = operation}) do
    {:ok, 1, operation.id}
  end

  defp prepare_history(repo, input) do
    %{owner_agent_id: owner, expected_version: version, expected_generation: generation} =
      Map.merge(input.operation, input.agent)

    with {:ok, _agent} <- Records.get(repo, Agent, owner),
         {:ok, seq} <- Records.advance_agent_history(repo, owner, version, generation) do
      {:ok, seq, owner}
    end
  end

  defp insert_attempt(_repo, _operation, nil), do: {:ok, nil}

  defp insert_attempt(repo, operation, attempt) do
    attrs = %{
      attempt_id: attempt.attempt_id,
      operation_id: operation.id,
      executor_id: attempt.executor_id,
      executor_boot_id: attempt.executor_boot_id,
      description_digest: operation.description_digest,
      dispatch_state: "prepared",
      budget: attempt.budget,
      lock_version: 0,
      recorded_at: DateTime.utc_now()
    }

    changeset =
      Execution.changeset(%Execution{}, attrs)
      |> Ecto.Changeset.unique_constraint(:operation_id,
        name: :executions_operation_id_index
      )

    Records.insert(repo, changeset)
  end

  defp operation_changeset(operation, seq) do
    Operation.changeset(%Operation{}, %{
      id: operation.id,
      owner_agent_id: operation.owner_agent_id,
      turn_id: operation.turn_id,
      tool_call_id: operation.tool_call_id,
      ordinal: operation.ordinal,
      description: operation.description,
      description_digest: operation.description_digest,
      lock_version: 0,
      history_seq: seq,
      schema_version: 1,
      recorded_at: DateTime.utc_now()
    })
  end

  defp prepare_response(stored, attempt) do
    %{
      "operation_id" => stored.id,
      "description_digest" => stored.description_digest,
      "history_seq" => stored.history_seq,
      "lock_version" => stored.lock_version,
      "attempt_id" => attempt && attempt.attempt_id,
      "dispatch_state" => attempt && attempt.dispatch_state
    }
  end

  ## Dispatch claim

  defp write_claim(repo, input) do
    with {:ok, execution} <- Records.get(repo, Execution, input.attempt_id),
         :ok <- same_operation(execution, input.operation_id) do
      query =
        from(e in Execution,
          where:
            e.attempt_id == ^input.attempt_id and e.dispatch_state == "prepared" and
              e.lock_version == ^input.expected_version,
          update: [
            set: [dispatch_state: "send_claimed", lock_version: ^(input.expected_version + 1)]
          ]
        )

      case repo.update_all(query, [], log: false) do
        {1, _} ->
          {:ok,
           %{
             "operation_id" => execution.operation_id,
             "attempt_id" => execution.attempt_id,
             "executor_id" => execution.executor_id,
             "executor_boot_id" => execution.executor_boot_id,
             "description_digest" => execution.description_digest,
             "dispatch_state" => "send_claimed",
             "lock_version" => input.expected_version + 1
           }}

        {0, _} ->
          # Already claimed (or version moved). Returning success here would invite
          # a second admit for work that may already be in flight.
          {:error, :conflict}
      end
    end
  end

  defp same_operation(execution, operation_id) do
    if execution.operation_id == operation_id, do: :ok, else: {:error, :invalid_data}
  end

  ## Evidence

  defp validate_evidence(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [:id, :operation_id, :attempt_id, :executor_id, :evidence_id, :content],
             [:digest, :resolution]
           ),
         {:ok, id} <- Records.uuid(attrs[:id]),
         {:ok, operation_id} <- Records.uuid(attrs[:operation_id]),
         {:ok, attempt_id} <- Records.uuid(attrs[:attempt_id]),
         {:ok, executor_id} <- Records.uuid(attrs[:executor_id]),
         {:ok, evidence_id} <- Records.uuid(attrs[:evidence_id]),
         {:ok, content} <- Records.json(attrs[:content], :event),
         {:ok, resolution} <- Records.json(attrs[:resolution], :event),
         {:ok, digest} <- digest_of(content, :event),
         :ok <- matching_digest(attrs[:digest], digest) do
      {:ok,
       %{
         id: id,
         operation_id: operation_id,
         attempt_id: attempt_id,
         executor_id: executor_id,
         evidence_id: evidence_id,
         content: content,
         resolution: resolution,
         digest: digest
       }}
    end
  end

  defp matching_digest(nil, _digest), do: :ok
  defp matching_digest(digest, digest), do: :ok
  defp matching_digest(_, _), do: {:error, :invalid_data}

  defp write_evidence(repo, input) do
    with {:ok, execution} <- Records.get(repo, Execution, input.attempt_id),
         :ok <- same_operation(execution, input.operation_id),
         :ok <- same_executor(execution, input.executor_id),
         {:ok, _operation} <- Records.get(repo, Operation, input.operation_id) do
      case stored_evidence(repo, input) do
        nil ->
          Records.insert(
            repo,
            evidence_changeset(input)
            |> Ecto.Changeset.unique_constraint([:executor_id, :evidence_id],
              name: :execution_evidence_executor_id_evidence_id_index
            )
          )
          |> case do
            {:ok, evidence} -> {:ok, evidence_response(evidence)}
            error -> error
          end

        %ExecutionEvidence{digest: digest} = stored ->
          if digest == input.digest,
            do: {:ok, evidence_response(stored)},
            else: {:error, :conflict}
      end
    end
  end

  defp same_executor(execution, executor_id) do
    if execution.executor_id == executor_id, do: :ok, else: {:error, :invalid_data}
  end

  defp stored_evidence(repo, input) do
    from(e in ExecutionEvidence,
      where: e.executor_id == ^input.executor_id and e.evidence_id == ^input.evidence_id
    )
    |> repo.one(log: false)
  end

  defp evidence_changeset(input) do
    ExecutionEvidence.changeset(%ExecutionEvidence{}, %{
      id: input.id,
      operation_id: input.operation_id,
      attempt_id: input.attempt_id,
      executor_id: input.executor_id,
      evidence_id: input.evidence_id,
      digest: input.digest,
      content: input.content,
      resolution: input.resolution,
      recorded_at: DateTime.utc_now()
    })
  end

  defp evidence_response(evidence) do
    %{
      "id" => evidence.id,
      "operation_id" => evidence.operation_id,
      "attempt_id" => evidence.attempt_id,
      "evidence_id" => evidence.evidence_id,
      "digest" => evidence.digest
    }
  end

  ## Result acceptance

  defp validate_accept(attrs) do
    with {:ok, _} <-
           Records.fields(
             attrs,
             [:operation_id, :expected_version, :result, :event],
             [:evidence_id, :artifact_ids, :agent]
           ),
         {:ok, operation_id} <- Records.uuid(attrs[:operation_id]),
         {:ok, version} <- Records.count(attrs[:expected_version]),
         {:ok, result} <- Records.json(attrs[:result], :result),
         {:ok, evidence_id} <- Records.optional_uuid(attrs[:evidence_id]),
         {:ok, artifact_ids} <- artifact_ids(attrs[:artifact_ids]),
         {:ok, agent} <- agent(attrs[:agent]),
         {:ok, event} <- Records.event_input(attrs[:event]) do
      {:ok,
       %{
         operation_id: operation_id,
         expected_version: version,
         result: result,
         evidence_id: evidence_id,
         artifact_ids: artifact_ids,
         agent: agent,
         event: event
       }}
    end
  end

  defp artifact_ids(nil), do: {:ok, []}

  defp artifact_ids(ids) when is_list(ids) and length(ids) <= @max_artifacts do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case Records.uuid(id) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp artifact_ids(ids) when is_list(ids), do: {:error, :limit}
  defp artifact_ids(_), do: {:error, :invalid_data}

  defp write_accept(repo, input) do
    with {:ok, operation} <- Records.get(repo, Operation, input.operation_id),
         :ok <- evidence_reference(repo, operation, input.evidence_id),
         :ok <- Artifacts.verify_references(repo, input.artifact_ids) do
      apply_accept(repo, operation, input)
    end
  end

  defp evidence_reference(_repo, _operation, nil), do: :ok

  defp evidence_reference(repo, operation, evidence_id) do
    case repo.get(ExecutionEvidence, evidence_id, log: false) do
      %ExecutionEvidence{operation_id: operation_id} when operation_id == operation.id -> :ok
      _ -> {:error, :conflict}
    end
  end

  defp apply_accept(repo, operation, input) do
    if is_nil(operation.accepted_result) do
      do_accept(repo, operation, input)
    else
      # A second acceptance never overwrites; identical evidence replays, any
      # other value stays a conflict and the original Result remains the fact.
      replay_accept(repo, operation, input)
    end
  end

  defp do_accept(repo, operation, input) do
    with {:ok, seq, scope} <- accept_history(repo, operation, input) do
      query =
        from(o in Operation,
          where:
            o.id == ^operation.id and is_nil(o.accepted_result) and
              o.lock_version == ^input.expected_version,
          update: [
            set: [
              accepted_result: ^input.result,
              accepted_evidence_id: ^input.evidence_id,
              lock_version: ^(input.expected_version + 1),
              history_seq: ^seq
            ]
          ]
        )

      case repo.update_all(query, [], log: false) do
        {1, _} ->
          with {:ok, _event} <-
                 Records.insert(
                   repo,
                   event_changeset(input.event, scope, seq, %{operation_id: operation.id})
                 ) do
            {:ok,
             %{
               "operation_id" => operation.id,
               "accepted_result" => input.result,
               "accepted_evidence_id" => input.evidence_id,
               "history_seq" => seq,
               "lock_version" => input.expected_version + 1
             }}
          end

        {0, _} ->
          replay_accept(repo, operation, input)
      end
    end
  end

  defp accept_history(_repo, %Operation{owner_agent_id: nil} = operation, _input) do
    {:ok, operation.history_seq + 1, operation.id}
  end

  defp accept_history(repo, operation, input) do
    with %{expected_version: version, expected_generation: generation} <- input.agent,
         {:ok, seq} <-
           Records.advance_agent_history(
             repo,
             operation.owner_agent_id,
             version,
             generation
           ) do
      {:ok, seq, operation.owner_agent_id}
    else
      nil -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay_accept(repo, operation, input) do
    stored = repo.get(Operation, operation.id, log: false)

    cond do
      stored.accepted_result != input.result ->
        {:error, :conflict}

      stored.accepted_evidence_id != input.evidence_id ->
        {:error, :conflict}

      true ->
        {:ok,
         %{
           "operation_id" => stored.id,
           "accepted_result" => stored.accepted_result,
           "accepted_evidence_id" => stored.accepted_evidence_id,
           "history_seq" => stored.history_seq,
           "lock_version" => stored.lock_version
         }}
    end
  end

  ## Shared helpers

  defp attempt_for(repo, operation_id) do
    from(e in Execution, where: e.operation_id == ^operation_id)
    |> repo.one(log: false)
  end

  defp digest_of(value, kind) do
    case Codec.digest(value, kind) do
      {:ok, digest} -> {:ok, digest}
      {:error, reason} -> {:error, reason}
    end
  end

  defp optional_count(nil), do: {:ok, nil}
  defp optional_count(value), do: Records.count(value)

  defp event_changeset(event, scope_id, seq, extra) do
    Records.event_changeset(
      Map.merge(
        %{
          id: event.id,
          scope_id: scope_id,
          seq: seq,
          type: event.type,
          schema_version: 1,
          payload: event.payload,
          causation_id: event.causation_id,
          recorded_at: DateTime.utc_now()
        },
        extra
      )
    )
  end
end
