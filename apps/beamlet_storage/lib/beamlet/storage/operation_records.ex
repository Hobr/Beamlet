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
  alias Beamlet.Storage.{AgentRecords, Artifacts, Codec, Records, Transaction}
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
      Transaction.read(fn -> read_operation(repo, id) end)
    end
  end

  defp read_operation(repo, id) do
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
    if description_shape_valid?(description) do
      with {:ok, _kind} <- Records.text(description["kind"], 255) do
        Records.json(description, :operation)
      end
    else
      {:error, :invalid_data}
    end
  end

  defp description_shape_valid?(description) do
    plain_map?(description) and description != %{} and
      Enum.all?(Map.keys(description), &(&1 in @description_keys)) and
      Enum.all?(@description_required, &Map.has_key?(description, &1)) and
      plain_map?(description["payload"]) and
      valid_protocol_version?(description["protocol_version"])
  end

  defp plain_map?(value), do: is_map(value) and not is_struct(value)

  defp valid_protocol_version?(version), do: is_integer(version) and version >= 1

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
         "attempt_version" => attempt && attempt.lock_version,
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
      "attempt_version" => attempt && attempt.lock_version,
      "dispatch_state" => attempt && attempt.dispatch_state
    }
  end

  ## Whole-batch preparation

  @doc """
  Commits every Operation of one legal Tool batch, its one prepared attempt, its
  event and the batch checkpoint in a single transaction. Either the whole batch
  is stored or nothing is; dispatch is the caller's later, separate step.

  A batch dispatches its Operations concurrently, so each member reserves two
  Agent history positions: the `operation.prepared` event and the position its
  own accepted Result will write (`accept_seq` in the response). An accept then
  never contends on the Agent version with a sibling of the same batch.
  """
  def prepare_batch(repo, attrs) do
    with {:ok, input} <- validate_batch(attrs) do
      Records.transact(repo, fn -> write_batch(repo, input) end)
    end
  end

  defp validate_batch(attrs) do
    with {:ok, _} <- Records.fields(attrs, [:operations, :agent, :checkpoint, :events], []),
         {:ok, operations} <- batch_operations(attrs[:operations]),
         {:ok, events} <- batch_events(attrs[:events], length(operations)),
         {:ok, agent} <- agent(attrs[:agent]),
         {:ok, checkpoint} <- AgentRecords.checkpoint(attrs[:checkpoint]),
         :ok <- single_owner(operations, agent) do
      {:ok, %{operations: operations, events: events, agent: agent, checkpoint: checkpoint}}
    end
  end

  defp batch_operations(list) when is_list(list) and length(list) in 1..8 do
    list
    |> Enum.reduce_while({:ok, []}, &collect_batch_member/2)
    |> reverse_batch()
  end

  defp batch_operations(list) when is_list(list), do: {:error, :limit}
  defp batch_operations(_), do: {:error, :invalid_data}

  defp collect_batch_member(requested, {:ok, acc}) do
    with {:ok, attempt} <- batch_attempt(requested),
         {:ok, operation} <- operation(Map.delete(requested, :attempt)) do
      if owned_batch_member?(operation) and not duplicate_batch_member?(acc, operation),
        do: {:cont, {:ok, [%{operation: operation, attempt: attempt} | acc]}},
        else: {:halt, {:error, :invalid_data}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp duplicate_batch_member?(acc, operation) do
    Enum.any?(
      acc,
      &(&1.operation.id == operation.id or &1.operation.ordinal == operation.ordinal)
    )
  end

  defp reverse_batch({:ok, acc}), do: {:ok, Enum.reverse(acc)}
  defp reverse_batch(error), do: error

  # Every batch member is dispatchable on its own: exactly one prepared attempt.
  defp batch_attempt(requested) when is_map(requested) and not is_struct(requested) do
    case Map.get(requested, :attempt) do
      nil -> {:error, :invalid_data}
      attempt -> attempt(attempt)
    end
  end

  defp batch_attempt(_), do: {:error, :invalid_data}

  defp owned_batch_member?(operation) do
    not is_nil(operation.owner_agent_id) and not is_nil(operation.turn_id) and
      not is_nil(operation.tool_call_id) and not is_nil(operation.ordinal)
  end

  defp batch_events(events, count) when is_list(events) and length(events) == count do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      case Records.event_input(event) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp batch_events(_, _), do: {:error, :invalid_data}

  defp single_owner([%{operation: %{owner_agent_id: owner, turn_id: turn}} | rest], agent) do
    if not is_nil(agent) and
         Enum.all?(rest, &(&1.operation.owner_agent_id == owner and &1.operation.turn_id == turn)),
       do: :ok,
       else: {:error, :invalid_data}
  end

  defp write_batch(repo, input) do
    case stored_batch(repo, input.operations) do
      {:ok, :new} -> insert_batch(repo, input)
      {:ok, {:stored, stored}} -> batch_replay(repo, stored)
      {:error, reason} -> {:error, reason}
    end
  end

  # A replayed batch returns the same members (attempt identity included) as the
  # original commit, so a caller that reuses it still gets a usable version.
  defp stored_batch(repo, operations) do
    Enum.reduce_while(operations, {:ok, []}, fn %{operation: operation}, {:ok, acc} ->
      case repo.get(Operation, operation.id, log: false) do
        nil ->
          {:cont, {:ok, [{nil, operation} | acc]}}

        %Operation{description_digest: digest} = stored
        when digest == operation.description_digest ->
          {:cont, {:ok, [{stored, operation} | acc]}}

        %Operation{} ->
          {:halt, {:error, :conflict}}
      end
    end)
    |> case do
      {:ok, pairs} ->
        stored = Enum.reject(pairs, fn {stored, _requested} -> is_nil(stored) end)

        cond do
          stored == [] -> {:ok, :new}
          length(stored) == length(pairs) -> {:ok, {:stored, Enum.reverse(stored)}}
          true -> {:error, :conflict}
        end

      error ->
        error
    end
  end

  defp batch_replay(repo, [{first, _requested} | _] = stored) do
    case Records.get(repo, Agent, first.owner_agent_id) do
      {:ok, agent} ->
        case replay_members(repo, stored) do
          {:ok, members} ->
            {:ok,
             %{
               "agent_id" => agent.id,
               "checkpoint_id" => agent.head_checkpoint_id,
               "history_seq" => agent.history_seq,
               "lock_version" => agent.lock_version,
               "operations" => members
             }}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp replay_members(repo, stored) do
    Enum.reduce_while(stored, {:ok, []}, fn {operation, _requested}, {:ok, acc} ->
      case attempt_for(repo, operation.id) do
        nil -> {:halt, {:error, :conflict}}
        attempt -> {:cont, {:ok, [batch_member(operation, attempt, operation.history_seq) | acc]}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp insert_batch(repo, input) do
    owner = hd(input.operations).operation.owner_agent_id
    count = length(input.operations)
    reserved = 2 * count

    with {:ok, agent} <- Records.get(repo, Agent, owner),
         base = agent.history_seq,
         {:ok, _checkpoint} <-
           AgentRecords.insert_checkpoint(repo, input.checkpoint, owner, batch_turn(input)),
         {:ok, version} <-
           Records.cas_agent(
             repo,
             agent,
             input.agent.expected_version,
             input.agent.expected_generation,
             head_checkpoint_id: input.checkpoint.id,
             history_seq: base + reserved
           ),
         {:ok, stored} <- insert_batch_operations(repo, input, base) do
      {:ok,
       %{
         "agent_id" => owner,
         "checkpoint_id" => input.checkpoint.id,
         "history_seq" => base + reserved,
         "lock_version" => version,
         "operations" => stored
       }}
    end
  end

  defp batch_turn(input),
    do: input.operations |> hd() |> Map.fetch!(:operation) |> Map.fetch!(:turn_id)

  defp insert_batch_operations(repo, input, base) do
    Enum.reduce_while(Enum.with_index(input.operations), {:ok, []}, fn
      {%{operation: operation, attempt: attempt}, index}, {:ok, acc} ->
        seq = base + 2 * index + 1
        event = Enum.at(input.events, index)

        with {:ok, _operation} <- Records.insert(repo, operation_changeset(operation, seq)),
             {:ok, attempt} <- insert_attempt(repo, operation, attempt),
             {:ok, _event} <-
               Records.insert(
                 repo,
                 event_changeset(event, operation.owner_agent_id, seq, %{
                   operation_id: operation.id,
                   turn_id: operation.turn_id
                 })
               ) do
          {:cont, {:ok, [batch_member(operation, attempt, seq) | acc]}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp batch_member(operation, attempt, seq) do
    %{
      "operation_id" => operation.id,
      "tool_call_id" => operation.tool_call_id,
      "ordinal" => operation.ordinal,
      "description_digest" => operation.description_digest,
      "lock_version" => Map.get(operation, :lock_version, 0),
      "history_seq" => seq,
      "accept_seq" => seq + 1,
      "attempt_id" => attempt.attempt_id,
      "attempt_version" => attempt.lock_version,
      "dispatch_state" => attempt.dispatch_state
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
        nil -> insert_evidence(repo, input)
        %ExecutionEvidence{} = stored -> stored_evidence_result(stored, input.digest)
      end
    end
  end

  defp insert_evidence(repo, input) do
    changeset =
      evidence_changeset(input)
      |> Ecto.Changeset.unique_constraint([:executor_id, :evidence_id],
        name: :execution_evidence_executor_id_evidence_id_index
      )

    case Records.insert(repo, changeset) do
      {:ok, evidence} -> {:ok, evidence_response(evidence)}
      error -> error
    end
  end

  defp stored_evidence_result(%ExecutionEvidence{digest: digest} = stored, digest),
    do: {:ok, evidence_response(stored)}

  defp stored_evidence_result(_stored, _digest), do: {:error, :conflict}

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
         {:ok, agent} <- accept_agent(attrs[:agent]),
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
          insert_accept_event(repo, operation, input, seq, scope)

        {0, _} ->
          replay_accept(repo, operation, input)
      end
    end
  end

  defp insert_accept_event(repo, operation, input, seq, scope) do
    event = event_changeset(input.event, scope, seq, %{operation_id: operation.id})

    case Records.insert(repo, event) do
      {:ok, _event} ->
        {:ok,
         %{
           "operation_id" => operation.id,
           "accepted_result" => input.result,
           "accepted_evidence_id" => input.evidence_id,
           "history_seq" => seq,
           "lock_version" => input.expected_version + 1
         }}

      error ->
        error
    end
  end

  defp accept_history(_repo, %Operation{owner_agent_id: nil} = operation, _input) do
    {:ok, operation.history_seq + 1, operation.id}
  end

  defp accept_history(repo, operation, input) do
    with %{expected_generation: generation} <- input.agent,
         {:ok, agent} <- Records.get(repo, Agent, operation.owner_agent_id),
         :ok <- generation_only(agent, generation) do
      case input.agent do
        # A batch member writes the position its preparation reserved; several
        # accepts of one batch must not contend on the Agent version.
        %{accept_seq: seq} when is_integer(seq) -> reserved_position(operation, agent, seq)
        %{expected_version: version} -> advance_position(repo, operation, version, generation)
      end
    else
      nil -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  # The position was reserved by this batch's prepare; anything beyond the
  # Agent's committed history sequence is forged or stale.
  defp reserved_position(operation, agent, seq) do
    if seq > 0 and seq <= agent.history_seq,
      do: {:ok, seq, operation.owner_agent_id},
      else: {:error, :conflict}
  end

  defp advance_position(repo, operation, version, generation) do
    with {:ok, seq} <-
           Records.advance_agent_history(repo, operation.owner_agent_id, version, generation) do
      {:ok, seq, operation.owner_agent_id}
    end
  end

  # The accepting Agent identity is either a strict version CAS for one owned
  # Operation or the batch-preallocated position when siblings accept at once.
  defp accept_agent(nil), do: {:ok, nil}

  defp accept_agent(agent) do
    with {:ok, _} <-
           Records.fields(agent, [:expected_generation], [:expected_version, :accept_seq]),
         {:ok, generation} <- Records.count(agent[:expected_generation]),
         {:ok, version} <- optional_count(agent[:expected_version]),
         {:ok, accept_seq} <- optional_count(agent[:accept_seq]),
         :ok <- one_position(version, accept_seq) do
      {:ok, %{expected_version: version, expected_generation: generation, accept_seq: accept_seq}}
    end
  end

  defp one_position(nil, nil), do: {:error, :invalid_data}
  defp one_position(nil, _accept_seq), do: :ok
  defp one_position(_version, nil), do: :ok
  defp one_position(_version, _accept_seq), do: {:error, :invalid_data}

  defp generation_only(agent, generation) do
    if agent.generation == generation, do: :ok, else: {:error, :stale_generation}
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
